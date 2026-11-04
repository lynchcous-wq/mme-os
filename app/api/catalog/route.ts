import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type CommerceProduct = {
  id: string;
  catalog_product_id: string | null;
  sku: string;
  title: string;
  description: string | null;
  category_key: string | null;
  condition_grade: string;
  unit_price_cents: number;
  currency: string;
  serialized: boolean;
};

type CatalogProduct = {
  id: string;
  name: string;
  brand: string | null;
  description: string | null;
  condition: string;
  specifications: Record<string, unknown>;
  warranty_summary: string | null;
  category_id: string;
};

type InventoryBalance = {
  product_id: string;
  location_id: string;
  on_hand_quantity: number;
  reserved_quantity: number;
};

type StoreLocation = {
  id: string;
  location_code: string;
  display_name: string;
};

type Category = { id: string; name: string; slug: string };
type SerializedUnit = { product_id: string; location_id: string; unit_status: string };

async function readTable<T>(baseUrl: string, serviceKey: string, table: string, query: string): Promise<T[]> {
  const response = await fetch(`${baseUrl}/rest/v1/${table}?${query}`, {
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      Accept: "application/json",
    },
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`Catalog data source unavailable: ${table} (${response.status})`);
  }

  return (await response.json()) as T[];
}

export async function GET() {
  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!baseUrl || !serviceKey) {
    return NextResponse.json(
      { error: "Live catalog is not configured yet.", products: [] },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }

  try {
    const [commerceProducts, catalogProducts, balances, locations, categories] = await Promise.all([
      readTable<CommerceProduct>(
        baseUrl,
        serviceKey,
        "mme_products",
        "select=id,catalog_product_id,sku,title,description,category_key,condition_grade,unit_price_cents,currency,serialized&active=eq.true&catalog_product_id=not.is.null&order=title.asc",
      ),
      readTable<CatalogProduct>(
        baseUrl,
        serviceKey,
        "products",
        "select=id,name,brand,description,condition,specifications,warranty_summary,category_id&catalog_status=eq.published",
      ),
      readTable<InventoryBalance>(
        baseUrl,
        serviceKey,
        "mme_inventory_balances",
        "select=product_id,location_id,on_hand_quantity,reserved_quantity",
      ),
      readTable<StoreLocation>(
        baseUrl,
        serviceKey,
        "mme_store_locations",
        "select=id,location_code,display_name&active=eq.true",
      ),
      readTable<Category>(
        baseUrl,
        serviceKey,
        "product_categories",
        "select=id,name,slug&is_active=eq.true",
      ),
      readTable<SerializedUnit>(
        baseUrl,
        serviceKey,
        "mme_serialized_units",
        "select=product_id,location_id,unit_status&unit_status=eq.in_stock",
      ),
    ]);

    const catalogById = new Map(catalogProducts.map((product) => [product.id, product]));
    const categoryById = new Map(categories.map((category) => [category.id, category]));
    const locationsById = new Map(locations.map((location) => [location.id, location]));
    const serializedStock = new Map<string, number>();\n    for (const unit of serializedUnits) {\n      const key = `${unit.product_id}:${unit.location_id}`;\n      serializedStock.set(key, (serializedStock.get(key) ?? 0) + 1);\n    }

    const products = commerceProducts.flatMap((commerce) => {
      if (!commerce.catalog_product_id) return [];
      const catalog = catalogById.get(commerce.catalog_product_id);
      if (!catalog) return [];

      const availability = commerce.serialized === true
        ? locations.flatMap((location) => {
            const available = serializedStock.get(`${commerce.id}:${location.id}`) ?? 0;
            return available > 0 ? [{
              location_id: location.id,
              location_code: location.location_code,
              location_name: location.display_name,
              available_quantity: available,
            }] : [];
          })
        : balances
            .filter((balance) => balance.product_id === commerce.id)
            .flatMap((balance) => {
              const location = locationsById.get(balance.location_id);
              if (!location) return [];
              return [{
                location_id: location.id,
                location_code: location.location_code,
                location_name: location.display_name,
                available_quantity: Math.max(0, balance.on_hand_quantity - balance.reserved_quantity),
              }];
            });

      return [{
        id: commerce.id,
        sku: commerce.sku,
        title: commerce.title,
        description: commerce.description ?? catalog.description,
        brand: catalog.brand,
        category: categoryById.get(catalog.category_id)?.name ?? commerce.category_key ?? "Electronics",
        condition: commerce.condition_grade,
        catalog_condition: catalog.condition,
        specifications: catalog.specifications,
        warranty_summary: catalog.warranty_summary,
        price_cents: Number(commerce.unit_price_cents),
        currency: commerce.currency,
        serialized: commerce.serialized,
        availability,
        available_quantity: availability.reduce((total, item) => total + item.available_quantity, 0),
      }];
    });

    return NextResponse.json(
      { products },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return NextResponse.json(
      { error: "Live catalog could not be loaded.", products: [] },
      { status: 502, headers: { "Cache-Control": "no-store" } },
    );
  }
}
