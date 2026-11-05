import { NextResponse } from "next/server";
import { authenticatePosRequest, isUuid } from "@/lib/pos/authenticated-server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(
  request: Request,
  { params }: { params: Promise<{ transactionId: string }> },
) {
  const authenticated = await authenticatePosRequest(request);
  if (!authenticated.ok) return authenticated.response;
  const { context } = authenticated;
  const { transactionId } = await params;
  if (!isUuid(transactionId)) return NextResponse.json({ error: "A valid transaction ID is required." }, { status: 400 });

  try {
    const lookup = await fetch(
      `${context.baseUrl}/rest/v1/mme_pos_transactions?select=id,order_id,status,revision,currency,total_cents,created_at,updated_at,finalized_at&id=eq.${transactionId}&limit=1`,
      { headers: { apikey: context.serviceKey, Authorization: `Bearer ${context.serviceKey}` }, cache: "no-store" },
    );
    if (!lookup.ok) return NextResponse.json({ error: "POS transaction could not be loaded." }, { status: 502 });
    const rows = await lookup.json() as Array<Record<string, unknown>>;
    const transaction = rows[0];
    if (!transaction || typeof transaction.order_id !== "string") {
      return NextResponse.json({ error: "POS transaction was not found." }, { status: 404 });
    }

    const permission = await fetch(`${context.baseUrl}/rest/v1/rpc/mme_person_authorize_pos_action`, {
      method: "POST",
      headers: { apikey: context.serviceKey, Authorization: `Bearer ${context.serviceKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_actor_person_id: context.personId,
        p_permission_key: "pos.transaction.view",
        p_order_id: transaction.order_id,
      }),
      cache: "no-store",
    });
    if (!permission.ok) return NextResponse.json({ error: "POS access could not be verified." }, { status: 503 });
    if (await permission.json() !== true) return NextResponse.json({ error: "You do not have permission to view this POS transaction." }, { status: 403 });

    const eventsResponse = await fetch(
      `${context.baseUrl}/rest/v1/mme_pos_transaction_events?select=id,revision,event_type,previous_status,next_status,actor_person_id,created_at&transaction_id=eq.${transactionId}&order=revision.asc`,
      { headers: { apikey: context.serviceKey, Authorization: `Bearer ${context.serviceKey}` }, cache: "no-store" },
    );
    if (!eventsResponse.ok) return NextResponse.json({ error: "POS transaction history could not be loaded." }, { status: 502 });
    const events = await eventsResponse.json();
    return NextResponse.json({ transaction: { ...transaction, order_id: undefined }, events }, {
      headers: { "Cache-Control": "no-store" },
    });
  } catch {
    return NextResponse.json({ error: "POS transaction service is temporarily unavailable." }, { status: 503 });
  }
}
