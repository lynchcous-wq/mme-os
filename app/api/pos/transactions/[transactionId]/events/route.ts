import { NextResponse } from "next/server";
import { authenticatePosRequest, isUuid } from "@/lib/pos/authenticated-server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const eventTypes = new Set([
  "pricing_confirmed", "tender_submitted", "tender_result",
  "reconciliation_result", "finalization_started", "finalization_confirmed", "cancelled",
]);

const nextStatuses = new Set([
  "pricing_confirmed", "tendering", "partially_tendered", "fully_tendered",
  "reconciliation_required", "finalization_pending", "finalized", "cancelled",
]);

export async function POST(
  request: Request,
  { params }: { params: Promise<{ transactionId: string }> },
) {
  const authenticated = await authenticatePosRequest(request);
  if (!authenticated.ok) return authenticated.response;
  const { context } = authenticated;
  const { transactionId } = await params;

  if (!isUuid(transactionId)) {
    return NextResponse.json({ error: "A valid transaction ID is required." }, { status: 400 });
  }

  const idempotencyKey = request.headers.get("idempotency-key")?.trim();
  if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 128) {
    return NextResponse.json({ error: "A valid Idempotency-Key header is required." }, { status: 400 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Request body must be valid JSON." }, { status: 400 });
  }

  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return NextResponse.json({ error: "A valid event object is required." }, { status: 400 });
  }
  const input = body as Record<string, unknown>;
  if (Object.keys(input).some((key) => !["expected_revision", "event_type", "next_status", "event_data"].includes(key)) ||
      !Number.isSafeInteger(input.expected_revision) || (input.expected_revision as number) < 0 ||
      typeof input.event_type !== "string" || !eventTypes.has(input.event_type) ||
      typeof input.next_status !== "string" || !nextStatuses.has(input.next_status) ||
      !input.event_data || typeof input.event_data !== "object" || Array.isArray(input.event_data)) {
    return NextResponse.json({ error: "Event fields are invalid." }, { status: 400 });
  }

  try {
    const response = await fetch(`${context.baseUrl}/rest/v1/rpc/mme_pos_append_transaction_event`, {
      method: "POST",
      headers: {
        apikey: context.serviceKey,
        Authorization: `Bearer ${context.serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_transaction_id: transactionId,
        p_expected_revision: input.expected_revision,
        p_event_type: input.event_type,
        p_idempotency_key: idempotencyKey,
        p_actor_person_id: context.personId,
        p_next_status: input.next_status,
        p_event_data: input.event_data,
      }),
      cache: "no-store",
    });

    if (!response.ok) {
      const detail = await response.text();
      if (response.status === 403 || /permission denied/i.test(detail)) {
        return NextResponse.json({ error: "You do not have permission to perform this POS action." }, { status: 403 });
      }
      if (/revision conflict|40001/i.test(detail)) {
        return NextResponse.json({ error: "The transaction changed. Refresh it before retrying." }, { status: 409 });
      }
      if (/idempotency key reused|23505/i.test(detail)) {
        return NextResponse.json({ error: "This idempotency key was already used for a different event." }, { status: 409 });
      }
      if (/Invalid POS transaction state transition|23514/i.test(detail)) {
        return NextResponse.json({ error: "That transaction state transition is not allowed." }, { status: 409 });
      }
      if (/Sensitive payment data/i.test(detail)) {
        return NextResponse.json({ error: "Sensitive payment data cannot be stored in transaction events." }, { status: 400 });
      }
      if (response.status === 404 || /POS transaction not found/i.test(detail)) {
        return NextResponse.json({ error: "POS transaction was not found." }, { status: 404 });
      }
      return NextResponse.json({ error: "POS transaction event could not be recorded." }, { status: 502 });
    }

    const result = await response.json();
    return NextResponse.json({ result }, { status: 200, headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "POS transaction service is temporarily unavailable." }, { status: 503 });
  }
}
