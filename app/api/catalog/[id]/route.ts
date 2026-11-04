import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

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
  if (!response.ok) throw new Error(`Catalog source unavailable: ${table}`);
  return (await response.json()) as T[];
}

export async function GET(
  _request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  if (!uuidPattern.test(id)) {
    return NextResponse.json({ error: "Product not found." }, { status: 404 });
  }

  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !serviceKey) {
    return NextResponse.json({ error: "Live catalog is not configured yet." }, { status: 503 });
  }

  try {
    const [commerceRows, catalogRows, locations, balances, serializedUnits, media] = await Promise.all([
      readTable<Row>(
        baseUrl,
        serviceKey,
        "mme_products",
        `select=id,catalog_product_id,sku,title,description,category_key,condition_grade,unit_price_cents,currency,serialized,active&id=eq.${id}&active=eq.true&limit=1`,
      ),
      readTable<Row>(
        baseUrl,
        serviceKey,
        "products",
        "select=id,name,brand,manufacturer,model_number,upc_ean,description,condition,tracking_mode,specifications,warranty_summary,category_id,catalog_status&catalog_status=eq.published",
      ),
      readTable<Row>(
        baseUrl,
        serviceKey,
        "mme_store_locations",
        "select=id,location_code,display_name&active=eq.true",
      ),
      readTable<Row>(
        baseUrl,
        serviceKey,
        "mme_inventory_balances",
        "select=product_id,location_id,on_hand_quantity,reserved_quantity",
      ),
      readTable<Row>(
        baseUrl,
        serviceKey,
        "mme_serialized_units",
        `select=product_id,location_id,unit_status&product_id=eq.${id}&unit_status=eq.in_stock`,
      ),
      readTable<Row>(
        baseUrl,
        serviceKey,
        "product_media",
        "select=id,product_id,media_type,storage_key,external_url,alt_text,sort_order,is_primary&order=sort_order.asc",
      ),
    ]);

    const commerce = commerceRows[0];
    if (!commerce || typeof commerce.catalog_product_id !== "string") {
      return NextResponse.json({ error: "Product not found." }, { status: 404 });
    }

    const catalog = catalogRows.find((row) => row.id === commerce.catalog_product_id);
    if (!catalog) return NextResponse.json({ error: "Product not found." }, { status: 404 });

    const locationById = new Map(locations.map((location) => [String(location.id), location]));
    const availability = commerce.serialized === true
      ? [...new Set(serializedUnits.map((unit) => String(unit.location_id)))].flatMap((locationId) => {
          const location = locationById.get(locationId);
          if (!location) return [];
          return [{
            location_id: location.id,
            location_code: location.location_code,
            location_name: location.display_name,
            available_quantity: serializedUnits.filter((unit) => unit.location_id === locationId).length,
          }];
        })
      : balances
      .filter((balance) => balance.product_id === commerce.id)
      .flatMap((balance) => {
        const location = locationById.get(String(balance.location_id));
        if (!location) return [];
        const available = Math.max(
          0,
          Number(balance.on_hand_quantity ?? 0) - Number(balance.reserved_quantity ?? 0),
        );
        return [{
          location_id: location.id,
          location_code: location.location_code,
          location_name: location.display_name,
          available_quantity: available,
        }];
      });

    const specifications = catalog.specifications && typeof catalog.specifications === "object"
      ? catalog.specifications
      : {};

    return NextResponse.json({
      product: {
        id: commerce.id,
        sku: commerce.sku,
        title: commerce.title,
        description: commerce.description ?? catalog.description,
        brand: catalog.brand,
        manufacturer: catalog.manufacturer,
        model_number: catalog.model_number,
        upc_ean: catalog.upc_ean,
        category_key: commerce.category_key,
        condition: catalog.condition,
        inventory_condition_grade: commerce.condition_grade,
        tracking_mode: catalog.tracking_mode,
        serialized: commerce.serialized,
        specifications,
        warranty_summary: catalog.warranty_summary,
        price_cents: Number(commerce.unit_price_cents),
        currency: commerce.currency,
        availability,
        available_quantity: availability.reduce((sum, item) => sum + item.available_quantity, 0),
        media: media
          .filter((item) => item.product_id === catalog.id)
          .map((item) => ({
            id: item.id,
            media_type: item.media_type,
            storage_key: item.storage_key,
            external_url: item.external_url,
            alt_text: item.alt_text,
            is_primary: item.is_primary,
          })),
      },
    }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Product details could not be loaded." }, { status: 502 });
  }
}
