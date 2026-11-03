import { readJsonObject } from "@/lib/http/read-json-object";
import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

const conditions = new Set(["new","open_box","like_new","refurbished","used_excellent","used_good","used_fair","parts_only","damaged","inspection_required"]);
const trackingModes = new Set(["quantity","serialized"]);
const categories = new Set(["televisions","laptops","tablets","cellphones","smartwatches","accessories","audio","gaming","smart-home","services-subscriptions"]);
const clean = (value: unknown, max: number) => typeof value === "string" && value.trim().length <= max ? value.trim() : null;

export async function PATCH(request: Request, context: { params: Promise<{ productId: string }> }) {
  const session = await createSessionClient();
  const { data: { user }, error: authError } = await session.auth.getUser();
  if (authError || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  const { productId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId))
    return NextResponse.json({ error: "Invalid product identifier." }, { status: 400 });
  const parsed = await readJsonObject(request, 24_000);
  if (!parsed.ok) return NextResponse.json({ error: parsed.error }, { status: parsed.status });
  const body = parsed.value;

  const expectedVersion = body.expected_version;
  const name = clean(body.name,160), sku = clean(body.sku,64), category = clean(body.category,80);
  const brand = body.brand == null ? null : clean(body.brand,100);
  const model = body.model_number == null ? null : clean(body.model_number,100);
  const upc = body.upc_ean == null ? null : clean(body.upc_ean,64);
  const description = body.description == null ? null : clean(body.description,5000);
  const warranty = body.warranty_summary == null ? null : clean(body.warranty_summary,500);
  const condition = typeof body.condition === "string" ? body.condition : "";
  const tracking = typeof body.tracking_mode === "string" ? body.tracking_mode : "";
  const specifications = body.specifications ?? {};
  if (!Number.isInteger(expectedVersion) || Number(expectedVersion)<1 || !name || !sku ||
      !/^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$/.test(sku) || !category || !categories.has(category) ||
      !conditions.has(condition) || !trackingModes.has(tracking) ||
      (body.brand != null && !brand) || (body.model_number != null && !model) ||
      (body.upc_ean != null && !upc) || (body.description != null && !description) ||
      (body.warranty_summary != null && !warranty) ||
      !specifications || typeof specifications !== "object" || Array.isArray(specifications) ||
      JSON.stringify(specifications).length>12000) {
    return NextResponse.json({ error: "One or more product fields are invalid." }, { status: 400 });
  }
  try {
    const admin = createAdminClient();
    const { data, error: rpcError } = await admin.rpc("mme_catalog_revise_returned_product", {
      p_actor_user_id: user.id, p_product_id: productId, p_expected_version: Number(expectedVersion),
      p_product_data: { name, sku, category, brand, model_number:model, upc_ean:upc, description,
        condition, tracking_mode:tracking, specifications, warranty_summary:warranty },
    });
    if (rpcError) {
      if (rpcError.code === "42501") return NextResponse.json({ error: "Only the original draft creator with catalog edit permission may revise this product." }, { status: 403 });
      if (rpcError.code === "40001") return NextResponse.json({ error: "This draft changed or is no longer returned for correction. Reload it." }, { status: 409 });
      if (rpcError.code === "22023") return NextResponse.json({ error: rpcError.message }, { status: 400 });
      if (rpcError.code === "23505") return NextResponse.json({ error: "SKU or product slug is already in use." }, { status: 409 });
      return NextResponse.json({ error: "Atomic product revision failed." }, { status: 500 });
    }
    return NextResponse.json({ product: data });
  } catch { return NextResponse.json({ error: "Catalog edit service unavailable." }, { status: 503 }); }
}
