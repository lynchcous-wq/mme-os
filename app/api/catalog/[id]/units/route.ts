import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Row = Record<string, unknown>;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  if (!uuidPattern.test(id)) return NextResponse.json({ error: "Product not found." }, { status: 404 });

  const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !service) return NextResponse.json({ error: "Device availability is not configured." }, { status: 503 });

  try {
    const [productsResponse, unitsResponse, locationsResponse] = await Promise.all([
      fetch(`${base}/rest/v1/mme_products?select=id,serialized,active&id=eq.${id}&limit=1`, {
        headers: { apikey: service, Authorization: `Bearer ${service}` }, cache: "no-store",
      }),
      fetch(`${base}/rest/v1/mme_serialized_units?select=product_id,location_id,unit_status&product_id=eq.${id}&unit_status=eq.in_stock`, {
        headers: { apikey: service, Authorization: `Bearer ${service}` }, cache: "no-store",
      }),
      fetch(`${base}/rest/v1/mme_store_locations?select=id,display_name&active=eq.true`, {
        headers: { apikey: service, Authorization: `Bearer ${service}` }, cache: "no-store",
      }),
    ]);
    if (!productsResponse.ok || !unitsResponse.ok || !locationsResponse.ok) {
      return NextResponse.json({ error: "Device availability could not be loaded." }, { status: 502 });
    }
    const products = await productsResponse.json() as Row[];
    const units = await unitsResponse.json() as Row[];
    const locations = await locationsResponse.json() as Row[];
    if (!products[0] || products[0].active !== true || products[0].serialized !== true) {
      return NextResponse.json({ error: "Serialized product not found." }, { status: 404 });
    }
    const locationById = new Map(locations.map((item) => [String(item.id), String(item.display_name)]));
    const availabilityByLocation = new Map<string, number>();
    for (const unit of units) {
      const locationId = String(unit.location_id);
      if (!locationById.has(locationId)) continue;
      availabilityByLocation.set(locationId, (availabilityByLocation.get(locationId) ?? 0) + 1);
    }
    const availableUnits = [...availabilityByLocation.entries()].map(([locationId, available_quantity]) => ({
      location_id: locationId,
      location_name: locationById.get(locationId),
      available_quantity,
    }));
    return NextResponse.json({ units: availableUnits }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Device availability is temporarily unavailable." }, { status: 502 });
  }
}
