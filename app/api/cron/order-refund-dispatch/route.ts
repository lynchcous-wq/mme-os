import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };

type RefundJob = {
  refund_request_id: string;
  order_id: string;
  amount_cents: number;
  reason_code: string;
  idempotency_key: string;
  payment_intent_id: string;
  dispatch_attempt: number;
  lease_token: string;
};

async function rpc(base: string, key: string, name: string, args: Record<string, unknown>) {
  const response = await fetch(base + "/rest/v1/rpc/" + name, {
    method: "POST",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify(args),
    cache: "no-store",
  });
  if (!response.ok) throw new Error("REFUND_WORKER_DATABASE_OPERATION_FAILED");
  return response.json() as Promise<any>;
}

export async function POST(request: Request) {
  const cronSecret = process.env.CRON_SECRET;
  const stripeKey = process.env.STRIPE_SECRET_KEY;
  const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!cronSecret || !stripeKey?.startsWith("sk_test_") || !base || !serviceKey) {
    return NextResponse.json({ error: "Test-mode refund dispatch is not configured." }, { status: 503, headers });
  }
  if (request.headers.get("authorization") !== "Bearer " + cronSecret) {
    return NextResponse.json({ error: "Unauthorized worker invocation." }, { status: 401, headers });
  }

  try {
    const jobs = await rpc(base, serviceKey, "mme_claim_order_refund_dispatch", {
      p_limit: 10, p_lease_seconds: 120,
    }) as RefundJob[];
    let submitted = 0, retried = 0, manualReview = 0, skipped = 0;

    for (const job of jobs ?? []) {
      if (!job.refund_request_id || !job.order_id || !job.payment_intent_id?.startsWith("pi_") ||
          !Number.isSafeInteger(job.amount_cents) || job.amount_cents <= 0 ||
          !job.lease_token || !job.idempotency_key) {
        manualReview++;
        continue;
      }

      const form = new URLSearchParams();
      form.set("payment_intent", job.payment_intent_id);
      form.set("amount", String(job.amount_cents));
      form.set("metadata[mme_order_id]", job.order_id);
      form.set("metadata[mme_refund_request_id]", job.refund_request_id);
      form.set("metadata[mme_reason_code]", job.reason_code.slice(0, 80));

      let outcome: "submitted" | "retry" | "manual_review" = "manual_review";
      let refundId: string | null = null;
      let safeError = "STRIPE_REFUND_REQUIRES_REVIEW";
      try {
        const response = await fetch("https://api.stripe.com/v1/refunds", {
          method: "POST",
          headers: {
            Authorization: "Bearer " + stripeKey,
            "Content-Type": "application/x-www-form-urlencoded",
            "Idempotency-Key": "mme-order-refund-" + job.idempotency_key,
          },
          body: form.toString(),
          cache: "no-store",
        });
        const payload = await response.json().catch(() => ({})) as { id?: string; error?: { code?: string; type?: string } };
        if (response.ok && typeof payload.id === "string" && payload.id.startsWith("re_")) {
          outcome = "submitted";
          refundId = payload.id;
          safeError = "";
        } else if (response.status === 429 || response.status >= 500) {
          outcome = "retry";
          safeError = "STRIPE_TEMPORARY_PROVIDER_FAILURE";
        } else {
          outcome = "manual_review";
          safeError = payload.error?.code ? "STRIPE_" + payload.error.code.toUpperCase().replace(/[^A-Z0-9_]/g, "_").slice(0, 70) : "STRIPE_REFUND_REJECTED";
        }
      } catch {
        // Reuse the same Stripe idempotency key after uncertain network outcomes.
        outcome = "retry";
        safeError = "STRIPE_NETWORK_OUTCOME_UNCERTAIN";
      }

      try {
        const finished = await rpc(base, serviceKey, "mme_finish_order_refund_dispatch", {
          p_refund_request_id: job.refund_request_id,
          p_lease_token: job.lease_token,
          p_outcome: outcome,
          p_stripe_refund_id: refundId,
          p_safe_error_code: safeError || null,
        });
        if (finished === "pending_provider") submitted++;
        else if (finished === "retry_scheduled") retried++;
        else if (finished === "manual_review") manualReview++;
        else skipped++;
      } catch {
        // Lease expiry plus Stripe idempotency prevents a duplicate refund on retry.
        skipped++;
      }
    }

    return NextResponse.json({
      ok: true, claimed: jobs?.length ?? 0, submitted, retried, manual_review: manualReview, skipped,
    }, { headers });
  } catch {
    return NextResponse.json({ error: "Refund dispatch failed; inspect restricted worker diagnostics." }, { status: 503, headers });
  }
}

export async function GET(request: Request) { return POST(request); }
