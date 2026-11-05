import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };

type Claim = {
  refund_request_id: string;
  tender_attempt_id: string;
  amount_minor: number;
  currency: string;
  provider_account_reference: string;
  provider_payment_reference: string;
  idempotency_key: string;
  lease_token: string;
};

async function rpc(base: string, key: string, name: string, args: Record<string, unknown>) {
  const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(args), cache: "no-store"
  });
  if (!response.ok) throw new Error(`RPC ${name} failed`);
  return response.json();
}

async function finish(base: string, key: string, job: Claim, outcome: "failed" | "unknown_reconciliation",
  operationReference: string | null, refundReference: string | null, failureCode: string | null) {
  return rpc(base, key, "mme_pos_finish_refund_dispatch", {
    p_refund_request_id: job.refund_request_id, p_lease_token: job.lease_token,
    p_outcome: outcome, p_provider_operation_reference: operationReference,
    p_provider_refund_reference: refundReference, p_failure_code: failureCode
  });
}

export async function POST(request: Request) {
  const cronSecret = process.env.CRON_SECRET;
  const stripeSecret = process.env.STRIPE_SECRET_KEY;
  const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!cronSecret || !stripeSecret || !base || !serviceKey)
    return NextResponse.json({ error: "Stripe refund worker is not configured." }, { status: 503, headers });
  if (request.headers.get("authorization") !== `Bearer ${cronSecret}`)
    return NextResponse.json({ error: "Unauthorized." }, { status: 401, headers });

  let claimed = 0, submitted = 0, failed = 0, uncertain = 0, deferred = 0;
  try {
    const jobs = await rpc(base, serviceKey, "mme_pos_claim_stripe_refund_dispatch",
      { p_limit: 10, p_lease_seconds: 90 }) as Claim[];
    if (!Array.isArray(jobs)) throw new Error("Unexpected claim response");
    for (const job of jobs) {
      claimed++;
      if (!job.refund_request_id || !job.lease_token || !job.idempotency_key ||
          !Number.isSafeInteger(job.amount_minor) || job.amount_minor <= 0 ||
          !/^[A-Z]{3}$/.test(job.currency) || !job.provider_payment_reference) {
        deferred++;
        continue;
      }
      const form = new URLSearchParams({
        payment_intent: job.provider_payment_reference,
        amount: String(job.amount_minor),
        'metadata[mme_refund_request_id]': job.refund_request_id
      });
      const stripeHeaders: Record<string, string> = {
        Authorization: `Bearer ${stripeSecret}`, "Content-Type": "application/x-www-form-urlencoded",
        "Idempotency-Key": job.idempotency_key
      };
      if (job.provider_account_reference) stripeHeaders["Stripe-Account"] = job.provider_account_reference;
      let providerResponse: Response;
      try {
        providerResponse = await fetch("https://api.stripe.com/v1/refunds", {
          method: "POST", headers: stripeHeaders, body: form.toString(), cache: "no-store"
        });
      } catch {
        await finish(base, serviceKey, job, "unknown_reconciliation", null, null, "STRIPE_NETWORK_OUTCOME_UNKNOWN");
        uncertain++;
        continue;
      }
      let payload: any = {};
      try { payload = await providerResponse.json(); } catch { /* retain safe failure path */ }
      if (providerResponse.ok && typeof payload.id === "string" && payload.id.startsWith("re_")) {
        // Webhook reconciliation is authoritative; never mark a refund complete from a synchronous response.
        await finish(base, serviceKey, job, "unknown_reconciliation", payload.id, payload.id, null);
        submitted++;
      } else if (providerResponse.status >= 400 && providerResponse.status < 500 && providerResponse.status !== 429) {
        await finish(base, serviceKey, job, "failed", null, null, "STRIPE_REQUEST_REJECTED");
        failed++;
      } else {
        await finish(base, serviceKey, job, "unknown_reconciliation", null, null, "STRIPE_OUTCOME_REQUIRES_RECONCILIATION");
        uncertain++;
      }
    }
    return NextResponse.json({ ok: true, claimed, submitted, failed, uncertain, deferred }, { headers });
  } catch {
    return NextResponse.json({ error: "Refund worker failed; inspect restricted operational logs." }, { status: 503, headers });
  }
}

export async function GET(request: Request) { return POST(request); }
