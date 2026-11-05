import { NextResponse } from "next/server";
import { authenticatePosRequest, isUuid } from "@/lib/pos/authenticated-server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const methods = new Set(["card_present", "card_not_present", "cash", "gift_card", "financing", "store_credit", "other_approved"]);
const operations = new Set(["authorize", "sale"]);

export async function POST(
  request: Request,
  { params }: { params: Promise<{ transactionId: string }> },
) {
  const authenticated = await authenticatePosRequest(request);
  if (!authenticated.ok) return authenticated.response;
  const { context } = authenticated;
  const { transactionId } = await params;
  if (!isUuid(transactionId)) return NextResponse.json({ error: "A valid transaction ID is required." }, { status: 400 });

  const provider = process.env.POS_TENDER_PROVIDER;
  const providerAccountReference = process.env.POS_TENDER_PROVIDER_ACCOUNT_REFERENCE;
  if (!provider || !providerAccountReference) {
    return NextResponse.json({ error: "Tender processing is not configured. No payment has been attempted." }, { status: 503 });
  }

  const idempotencyKey = request.headers.get("idempotency-key")?.trim();
  if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 128) {
    return NextResponse.json({ error: "A valid Idempotency-Key header is required." }, { status: 400 });
  }

  let body: unknown;
  try { body = await request.json(); }
  catch { return NextResponse.json({ error: "Request body must be valid JSON." }, { status: 400 }); }

  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return NextResponse.json({ error: "A valid tender request is required." }, { status: 400 });
  }
  const input = body as Record<string, unknown>;
  const allowed = ["method", "operation", "amount_minor", "currency", "calculation_reference", "payment_method_reference", "policy_reference"];
  if (Object.keys(input).some((key) => !allowed.includes(key)) ||
      typeof input.method !== "string" || !methods.has(input.method) ||
      typeof input.operation !== "string" || !operations.has(input.operation) ||
      !Number.isSafeInteger(input.amount_minor) || (input.amount_minor as number) <= 0 ||
      typeof input.currency !== "string" || !/^[A-Z]{3}$/.test(input.currency) ||
      typeof input.calculation_reference !== "string" || input.calculation_reference.trim().length < 1 ||
      (input.payment_method_reference !== undefined && (typeof input.payment_method_reference !== "string" || input.payment_method_reference.length > 256)) ||
      (input.policy_reference !== undefined && (typeof input.policy_reference !== "string" || input.policy_reference.length > 128))) {
    return NextResponse.json({ error: "Tender request fields are invalid." }, { status: 400 });
  }

  try {
    const response = await fetch(`${context.baseUrl}/rest/v1/rpc/mme_pos_create_tender_attempt`, {
      method: "POST",
      headers: {
        apikey: context.serviceKey,
        Authorization: `Bearer ${context.serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_transaction_id: transactionId,
        p_actor_person_id: context.personId,
        p_method: input.method,
        p_operation: input.operation,
        p_amount_minor: input.amount_minor,
        p_currency: input.currency,
        p_provider: provider,
        p_provider_account_reference: providerAccountReference,
        p_idempotency_key: idempotencyKey,
        p_calculation_reference: input.calculation_reference,
        p_payment_method_reference: input.payment_method_reference ?? null,
        p_policy_reference: input.policy_reference ?? null,
      }),
      cache: "no-store",
    });

    if (!response.ok) {
      const detail = await response.text();
      if (response.status === 403 || /permission denied/i.test(detail)) return NextResponse.json({ error: "You do not have permission to create this tender." }, { status: 403 });
      if (/idempotency key reused|23505/i.test(detail)) return NextResponse.json({ error: "This idempotency key conflicts with an earlier tender request." }, { status: 409 });
      if (/exceeds remaining|not accepting tenders|23514/i.test(detail)) return NextResponse.json({ error: "The transaction cannot accept this tender amount or state." }, { status: 409 });
      if (/not found|P0002/i.test(detail)) return NextResponse.json({ error: "POS transaction was not found." }, { status: 404 });
      if (/Invalid POS tender|token reference|policy reference|currency|calculation/i.test(detail)) return NextResponse.json({ error: "Tender details do not meet POS payment policy." }, { status: 400 });
      return NextResponse.json({ error: "Tender intent could not be recorded." }, { status: 502 });
    }

    const result = await response.json();
    return NextResponse.json({
      tender: result,
      paymentAttempted: false,
      message: "Tender intent recorded. No provider authorization or capture has been performed.",
    }, { status: 202, headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "POS tender service is temporarily unavailable. Check transaction status before retrying." }, { status: 503 });
  }
}
