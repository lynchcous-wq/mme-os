import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

const conditions = new Set(["new","open_box","like_new","refurbished","used_excellent","used_good","used_fair","parts_only","damaged","inspection_required"]);
const trackingModes = new Set(["quantity","serialized"]);
const categories = new Set(["televisions","laptops","tablets","cellphones","smartwatches","accessories","audio","gaming","smart-home","services-subscriptions"]);
const field = (value: unknown, max: number) => typeof value === "string" && value.trim().length > 0 && value.trim().length <= max ? value.trim() : null;

export async function PATCH(request: Request, context: { params: Promise<{ productId: string }> }) {
  const session = await createSessionClient();
  const { data: { user }, error: authError } = await session.auth.getUser();
  if (authError || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  const { productId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId)) return NextResponse.json({ error: "Invalid product identifier." }, { status: 400 });

  let body: Record<string, unknown>;
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) return NextResponse.json({ error: "A JSON object is required." }, { status: 400 });
    body = value as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body." }, { status: 400 });
  }

  const expectedVersion = body.expected_version;
  if (!Number.isInteger(expectedVersion) || Number(expectedVersion) < 1) return NextResponse.json({ error: "A valid expected_version is required." }, { status: 400 });
  const name = field(body.name,160), sku = field(body.sku,64), category = field(body.category,80);
  const brand = body.brand == null || body.brand === "" ? null : field(body.brand,100);
  const model = body.model_number == null || body.model_number === "" ? null : field(body.model_number,100);
  const upc = body.upc_ean == null || body.upc_ean === "" ? null : field(body.upc_ean,64);
  const description = body.description == null || body.description === "" ? null : field(body.description,5000);
  const warranty = body.warranty_summary == null || body.warranty_summary === "" ? null : field(body.warranty_summary,500);
  const condition = typeof body.condition === "string" ? body.condition : "";
  const tracking = typeof body.tracking_mode === "string" ? body.tracking_mode : "";
  const specifications = body.specifications;

  if (!name || !sku || !category || !categories.has(category) || !conditions.has(condition) || !trackingModes.has(tracking) ||
      (body.brand != null && body.brand !== "" && !brand) || (body.model_number != null && body.model_number !== "" && !model) ||
      (body.upc_ean != null && body.upc_ean !== "" && !upc) || (body.description != null && body.description !== "" && !description) ||
      (body.warranty_summary != null && body.warranty_summary !== "" && !warranty) || !/^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$/.test(sku)) {
    return NextResponse.json({ error: "One or more product fields are invalid." }, { status: 400 });
  }
  if (!specifications || typeof specifications !== "object" || Array.isArray(specifications) || JSON.stringify(specifications).length > 12000) {
    return NextResponse.json({ error: "Specifications must be a JSON object under 12 KB." }, { status: 400 });
  }

  try {
    const admin = createAdminClient();
    const { data: allowed, error: authzError } = await admin.rpc("mme_employee_authorize_catalog_action", {
      p_actor_user_id: user.id, p_permission_key: "catalog.edit", p_target_product_id: productId, p_submitter_user_id: null,
    });
    if (authzError) return NextResponse.json({ error: "Edit authorization unavailable." }, { status: 503 });
    if (allowed !== true) return NextResponse.json({ error: "Catalog edit permission required." }, { status: 403 });

    const { data: current, error: currentError } = await admin.from("products")
      .select("id,category_id,sku,slug,name,brand,model_number,upc_ean,description,condition,tracking_mode,specifications,warranty_summary,created_by,catalog_status,version")
      .eq("id",productId).maybeSingle();
    if (currentError) return NextResponse.json({ error: "Product could not be loaded." }, { status: 500 });
    if (!current || current.catalog_status !== "changes_requested") return NextResponse.json({ error: "Only returned drafts can be revised." }, { status: 409 });
    if (current.created_by !== user.id) return NextResponse.json({ error: "Only the original draft creator may revise this product." }, { status: 403 });
    if (current.version !== expectedVersion) return NextResponse.json({ error: "This draft has changed. Reload it before editing." }, { status: 409 });

    const { data: categoryRow, error: categoryError } = await admin.from("product_categories")
      .select("id").eq("slug",category).eq("is_active",true).maybeSingle();
    if (categoryError || !categoryRow) return NextResponse.json({ error: "Selected category is unavailable." }, { status: 400 });

    const snapshot = {
      category_id: current.category_id, sku: current.sku, slug: current.slug, name: current.name,
      brand: current.brand, model_number: current.model_number, upc_ean: current.upc_ean,
      description: current.description, condition: current.condition, tracking_mode: current.tracking_mode,
      specifications: current.specifications, warranty_summary: current.warranty_summary,
      catalog_status: current.catalog_status, version: current.version,
    };
    const { data: updated, error: updateError } = await admin.from("products")
      .update({
        category_id: categoryRow.id, sku, slug: name.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"").slice(0,100)+"-"+sku.toLowerCase(),
        name, brand, model_number: model, upc_ean: upc, description, condition, tracking_mode: tracking,
        specifications, warranty_summary: warranty, catalog_status: "draft",
        correction_notes: null, returned_by: null, returned_at: null,
      })
      .eq("id",productId).eq("version",Number(expectedVersion)).eq("catalog_status","changes_requested")
      .select("id,sku,name,catalog_status,version,updated_at").maybeSingle();
    if (updateError) {
      if (updateError.code === "23505") return NextResponse.json({ error: "SKU or product slug is already in use." }, { status: 409 });
      return NextResponse.json({ error: "Product revision could not be saved. Confirm the correction migration is applied." }, { status: 500 });
    }
    if (!updated) return NextResponse.json({ error: "Draft changed during editing. Reload and try again." }, { status: 409 });

    const { error: revisionError } = await admin.from("product_catalog_revisions").insert({
      product_id: productId, product_version: Number(expectedVersion), actor_id: user.id,
      revision_reason: "Employee correction after reviewer return", snapshot,
    });
    if (revisionError) return NextResponse.json({ error: "Revision saved but version history could not be recorded. Contact an administrator.", product_id: productId }, { status: 500 });

    const { error: auditError } = await admin.from("product_catalog_events").insert({
      product_id: productId, event_type: "employee_revised", actor_id: user.id,
      product_version: updated.version, event_data: { prior_version: Number(expectedVersion) },
    });
    if (auditError) return NextResponse.json({ error: "Revision saved but audit event failed. Contact an administrator.", product_id: productId }, { status: 500 });
    return NextResponse.json({ product: updated });
  } catch {
    return NextResponse.json({ error: "Catalog edit service unavailable." }, { status: 503 });
  }
}
