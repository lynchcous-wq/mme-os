import { NextResponse } from "next/server";
import { authenticatePosRequest, isUuid } from "@/lib/pos/authenticated-server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type CreatedTransaction = {
  id: string;
  status: string;
  revision: number;
  currency: string;
  total_cents: number;
  created_at: string;
};

export async function POST(request: Request) {
  const authenticated = await authenticatePosRequest(request);
  if (!authenticated.ok) return authenticated.response;
  const { context } = authenticated;

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

  if (!body || typeof body !== "object" || Array.isArray(body) ||
      Object.keys(body).some((key) => key !== "order_id") ||
      !isUuid((body as { order_id?: unknown }).order_id)) {
    return NextResponse.json({ error: "Provide only a valid order_id." }, { status: 400 });
  }

  const orderId = (body as { order_id: string }).order_id;

  try {
    const createResponse = await fetch(`${context.baseUrl}/rest/v1/rpc/mme_pos_create_transaction`, {
      method: "POST",
      headers: {
        apikey: context.serviceKey,
        Authorization: `Bearer ${context.serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_order_id: orderId,
        p_idempotency_key: idempotencyKey,
        p_actor_person_id: context.personId,
      }),
      cache: "no-store",
    });

    if (!createResponse.ok) {
      const errorText = await createResponse.text();
      if (createResponse.status === 403 || /permission denied/i.test(errorText)) {
        return NextResponse.json({ error: "You do not have permission to start a POS transaction for this order." }, { status: 403 });
      }
      if (createResponse.status === 404 || /Pending order not found|Active inventory reservation required/i.test(errorText)) {
        return NextResponse.json({ error: "The order is not eligible for POS checkout. Refresh the order and try again." }, { status: 409 });
      }
      if (createResponse.status === 409 || /23505|idempotency key/i.test(errorText)) {
        return NextResponse.json({ error: "This idempotency key conflicts with an existing POS transaction." }, { status: 409 });
      }
      return NextResponse.json({ error: "POS transaction could not be created." }, { status: 502 });
    }

    const transactionId = await createResponse.json() as unknown;
    if (!isUuid(transactionId)) {
      return NextResponse.json({ error: "POS transaction service returned an invalid result." }, { status: 502 });
    }

    const readResponse = await fetch(
      `${context.baseUrl}/rest/v1/mme_pos_transactions?select=id,status,revision,currency,total_cents,created_at&id=eq.${transactionId}&limit=1`,
      {
        headers: {
          apikey: context.serviceKey,
          Authorization: `Bearer ${context.serviceKey}`,
          Accept: "application/json",
        },
        cache: "no-store",
      },
    );
    if (!readResponse.ok) {
      return NextResponse.json({ error: "Transaction was created but its confirmation could not be loaded. Retry with the same Idempotency-Key." }, { status: 503 });
    }

    const rows = await readResponse.json() as CreatedTransaction[];
    const transaction = rows[0];
    if (!transaction) {
      return NextResponse.json({ error: "Transaction was created but its confirmation is unavailable. Retry with the same Idempotency-Key." }, { status: 503 });
    }

    return NextResponse.json({ transaction }, {
      status: 201,
      headers: { "Cache-Control": "no-store" },
    });
  } catch {
    return NextResponse.json({ error: "POS transaction service is temporarily unavailable." }, { status: 503 });
  }
}
