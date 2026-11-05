import test, { mock } from "node:test";
import assert from "node:assert/strict";

const { GET: listCatalog } = await import("../app/api/catalog/route.ts");
const { GET: productDetail } = await import("../app/api/catalog/[id]/route.ts");
const { GET: unitAvailability } = await import("../app/api/catalog/[id]/units/route.ts");
const { POST: validateCart } = await import("../app/api/cart/validate/route.ts");

const commerceId = "11111111-1111-4111-8111-111111111111";
const catalogId = "22222222-2222-4222-8222-222222222222";
const locationId = "33333333-3333-4333-8333-333333333333";
const categoryId = "44444444-4444-4444-8444-444444444444";
const unitId = "55555555-5555-4555-8555-555555555555";

const commerceProduct = (serialized = false) => ({
  id: commerceId, catalog_product_id: catalogId, sku: "MME-TV-001", title: "55-inch TV",
  description: null, category_key: "televisions", condition_grade: "new",
  unit_price_cents: 10000, currency: "USD", serialized, active: true,
});
const catalogProduct = () => ({
  id: catalogId, name: "55-inch TV", brand: "MME", description: "Catalog description",
  condition: "new", specifications: { screen_size: "55-inch" },
  warranty_summary: "1 year", category_id: categoryId, catalog_status: "published",
});
const location = () => ({ id: locationId, display_name: "Main Store", active: true });
const balance = () => ({ product_id: commerceId, location_id: locationId, on_hand_quantity: 5, reserved_quantity: 2 });

function setupFetch(t, overrides = {}) {
  const previousUrl = process.env.SUPABASE_URL;
  const previousKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  process.env.SUPABASE_URL = "https://mme-test.supabase.co";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-only-service-key";
  const defaults = {
    mme_products: [commerceProduct(false)],
    products: [catalogProduct()],
    mme_inventory_balances: [balance()],
    mme_store_locations: [location()],
    product_categories: [{ id: categoryId, name: "Televisions", slug: "televisions" }],
    mme_serialized_units: [],
    product_media: [{
      id: "66666666-6666-4666-8666-666666666666", product_id: catalogId,
      media_type: "image", external_url: "https://images.example.test/tv.jpg",
      alt_text: "Television", is_primary: true, storage_key: "private/internal/object-key",
    }],
  };
  const data = { ...defaults, ...overrides };
  const fetchMock = mock.method(globalThis, "fetch", async (input) => {
    const url = new URL(String(input));
    const table = url.pathname.split("/").pop();
    if (!(table in data)) return new Response("[]", { status: 200 });
    return new Response(JSON.stringify(data[table]), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  });
  t.after(() => {
    fetchMock.mock.restore();
    if (previousUrl === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = previousUrl;
    if (previousKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    else process.env.SUPABASE_SERVICE_ROLE_KEY = previousKey;
  });
}

test("GET /api/catalog returns published products with reserved stock subtracted", async (t) => {
  setupFetch(t);
  const response = await listCatalog();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const body = await response.json();
  assert.equal(body.products.length, 1);
  assert.equal(body.products[0].available_quantity, 3);
  assert.equal(body.products[0].availability[0].location_name, "Main Store");
  assert.equal(JSON.stringify(body).includes("location_code"), false);
  assert.equal(JSON.stringify(body).includes("serial_number"), false);
});

test("GET /api/catalog/:id returns public media fields and no internal storage keys", async (t) => {
  setupFetch(t);
  const response = await productDetail(new Request("http://localhost"), { params: Promise.resolve({ id: commerceId }) });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.product.available_quantity, 3);
  assert.equal(body.product.media[0].external_url, "https://images.example.test/tv.jpg");
  assert.equal(JSON.stringify(body).includes("storage_key"), false);
  assert.equal(JSON.stringify(body).includes("private/internal"), false);
});

test("GET /api/catalog/:id/units returns aggregate counts, never per-device identity", async (t) => {
  setupFetch(t, {
    mme_products: [{ ...commerceProduct(true) }],
    mme_serialized_units: [
      { id: unitId, product_id: commerceId, location_id: locationId, unit_status: "in_stock", serial_number: "PRIVATE-1", imei: "123456789012345" },
      { id: "77777777-7777-4777-8777-777777777777", product_id: commerceId, location_id: locationId, unit_status: "in_stock", serial_number: "PRIVATE-2" },
    ],
  });
  const response = await unitAvailability(new Request("http://localhost"), { params: Promise.resolve({ id: commerceId }) });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(body.units, [
    { unit_id: unitId, location_id: locationId, location_name: "Main Store", condition_grade: "new" },
    { unit_id: "77777777-7777-4777-8777-777777777777", location_id: locationId, location_name: "Main Store", condition_grade: "new" },
  ]);
  assert.equal(JSON.stringify(body).includes(unitId), true);
  assert.equal(JSON.stringify(body).includes("PRIVATE-1"), false);
  assert.equal(JSON.stringify(body).includes("123456789012345"), false);
});

test("POST /api/cart/validate rejects quantities above available stock without reserving or charging", async (t) => {
  setupFetch(t);
  const request = new Request("http://localhost/api/cart/validate", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ items: [{ product_id: commerceId, location_id: locationId, quantity: 4 }] }),
  });
  const response = await validateCart(request);
  assert.equal(response.status, 409);
  const body = await response.json();
  assert.match(body.error, /Only 3 unit\(s\) are currently available/);
});
