import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

type RequestLine = { product_id: string; location_id: string; quantity: number };
type Row = Record<string, unknown>;

async function readTable<T extends Row>(
  baseUrl: string,
  serviceKey: string,
  table: string,
  query: string,
): Promise<T[]> {
  const response = await fetch(`${baseUrl}/rest/v1/${table}?${query}`, {
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      Accept: "application/json",
    },
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`Unable to validate ${table}`);
  return (await response.json()) as T[];
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function POST(request: Request) {
  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !serviceKey) {
    return NextResponse.json({ error: "Cart validation is not configured." }, { status: 503 });
  }

  let body: { items?: RequestLine[] };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid cart request." }, { status: 400 });
  }

  const items = body.items;
  if (!Array.isArray(items) || items.length < 1 || items.length > 50) {
    return NextResponse.json({ error: "Your cart must contain between 1 and 50 distinct lines." }, { status: 400 });
  }

  const seen = new Set<string>();
  for (const item of items) {
    if (!item || !uuidPattern.test(item.product_id) || !uuidPattern.test(item.location_id) ||
        !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 100) {
      return NextResponse.json({ error: "Cart contains an invalid product, location, or quantity." }, { status: 400 });
    }
    const key = `${item.product_id}:${item.location_id}`;
    if (seen.has(key)) return NextResponse.json({ error: "Combine duplicate product and location lines." }, { status: 400 });
    seen.add(key);
  }

  try {
    const productIds = [...new Set(items.map((item) => item.product_id))];
    const locationIds = [...new Set(items.map((item) => item.location_id))];
    const [commerce, catalog, balances, locations] = await Promise.all([
      readTable<Row>(baseUrl, serviceKey, "mme_products",
        `select=id,catalog_product_id,sku,title,unit_price_cents,currency,active&active=eq.true&id=in.(${productIds.join(",")})`),
      readTable<Row>(baseUrl, serviceKey, "products",
        "select=id,catalog_status&catalog_status=eq.published"),
      readTable<Row>(baseUrl, serviceKey, "mme_inventory_balances",
        `select=product_id,location_id,on_hand_quantity,reserved_quantity&product_id=in.(${productIds.join(",")})&location_id=in.(${locationIds.join(",")})`),
      readTable<Row>(baseUrl, serviceKey, "mme_store_locations",
        `select=id,display_name,active&active=eq.true&id=in.(${locationIds.join(",")})`),
    ]);

    const catalogIds = new Set(catalog.map((row) => String(row.id)));
    const productById = new Map(commerce.map((row) => [String(row.id), row]));
    const locationById = new Map(locations.map((row) => [String(row.id), row]));
    const balanceByKey = new Map(balances.map((row) => [`${row.product_id}:${row.location_id}`, row]));
    const validated = [];

    for (const item of items) {
      const product = productById.get(item.product_id);
      const location = locationById.get(item.location_id);
      if (!product || typeof product.catalog_product_id !== "string" || !catalogIds.has(product.catalog_product_id) || !location) {
        return NextResponse.json({ error: "A cart item is no longer published or its store is unavailable. Refresh your cart." }, { status: 409 });
      }
      const balance = balanceByKey.get(`${item.product_id}:${item.location_id}`);
      const available = balance
        ? Math.max(0, Number(balance.on_hand_quantity ?? 0) - Number(balance.reserved_quantity ?? 0))
        : 0;
      if (item.quantity > available) {
        return NextResponse.json({
          error: `Only ${available} unit(s) are currently available for ${String(product.title)} at ${String(location.display_name)}.`,
        }, { status: 409 });
      }
      validated.push({
        product_id: item.product_id,
        location_id: item.location_id,
        quantity: item.quantity,
        title: product.title,
        sku: product.sku,
        unit_price_cents: Number(product.unit_price_cents),
        currency: String(product.currency ?? "USD"),
        location_name: location.display_name,
        line_total_cents: Number(product.unit_price_cents) * item.quantity,
        available_quantity: available,
      });
    }

    const currencies = [...new Set(validated.map((item) => item.currency))];
    if (currencies.length !== 1) {
      return NextResponse.json({ error: "Cart items must use the same currency." }, { status: 409 });
    }

    return NextResponse.json({
      items: validated,
      currency: currencies[0],
      subtotal_cents: validated.reduce((sum, item) => sum + item.line_total_cents, 0),
      validated_at: new Date().toISOString(),
      note: "Validation only. No inventory is reserved and no payment is created.",
    }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "We could not verify current prices and availability. Please try again." }, { status: 502 });
  }
}
