import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

const allowedConditions = new Set([
  "new", "open_box", "like_new", "refurbished", "used_excellent",
  "used_good", "used_fair", "parts_only", "damaged", "inspection_required",
]);
const allowedTracking = new Set(["quantity", "serialized"]);
const allowedCategorySlugs = new Set([
  "televisions", "laptops", "tablets", "cellphones", "smartwatches",
  "accessories", "audio", "gaming", "smart-home", "services-subscriptions",
]);

function textField(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  return cleaned.length > 0 && cleaned.length <= max ? cleaned : null;
}

function isHttpsUrl(value: string | null): boolean {
  if (!value) return false;
  try { return new URL(value).protocol === "https:"; } catch { return false; }
}

function slugify(value: string): string {
  return value.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 80);
}

export async function POST(request: Request) {
  const session = await createSessionClient();
  const { data: { user }, error: authError } = await session.auth.getUser();
  if (authError || !user) {
    return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return NextResponse.json({ error: "A JSON object is required." }, { status: 400 });
    }
    body = value as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body." }, { status: 400 });
  }

  const name = textField(body.name, 160);
  const sku = textField(body.sku, 64);
  const category = textField(body.category, 80);
  const brand = body.brand == null || body.brand === "" ? null : textField(body.brand, 100);
  const modelNumber = body.model_number == null || body.model_number === "" ? null : textField(body.model_number, 100);
  const upcEan = body.upc_ean == null || body.upc_ean === "" ? null : textField(body.upc_ean, 64);
  const description = body.description == null || body.description === "" ? null : textField(body.description, 5000);
  const warranty = body.warranty_summary == null || body.warranty_summary === "" ? null : textField(body.warranty_summary, 500);
  const condition = typeof body.condition === "string" ? body.condition : "";
  const tracking = typeof body.tracking_mode === "string" ? body.tracking_mode : "";
  const specifications = body.specifications;
  const mediaUrl = body.media_url == null || body.media_url === "" ? null : textField(body.media_url, 2048);

  if (!name || !sku || !category || !allowedConditions.has(condition) || !allowedTracking.has(tracking)) {
    return NextResponse.json({ error: "Name, SKU, category, condition, and tracking method are required and must be valid." }, { status: 400 });
  }
  if (!allowedCategorySlugs.has(category) || (body.brand != null && body.brand !== "" && !brand) ||
      (body.model_number != null && body.model_number !== "" && !modelNumber) ||
      (body.upc_ean != null && body.upc_ean !== "" && !upcEan) ||
      (body.description != null && body.description !== "" && !description) ||
      (body.warranty_summary != null && body.warranty_summary !== "" && !warranty) ||
      (body.media_url != null && body.media_url !== "" && !isHttpsUrl(mediaUrl))) {
    return NextResponse.json({ error: "One or more fields are invalid or too long." }, { status: 400 });
  }
  if (!specifications || typeof specifications !== "object" || Array.isArray(specifications)) {
    return NextResponse.json({ error: "Specifications must be a JSON object." }, { status: 400 });
  }
  if (JSON.stringify(specifications).length > 12000) {
    return NextResponse.json({ error: "Specifications are too large." }, { status: 400 });
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$/.test(sku)) {
    return NextResponse.json({ error: "SKU format is invalid." }, { status: 400 });
  }

  try {
    const admin = createAdminClient();
    const [{ data: employee, error: employeeError }, { data: settings, error: settingsError }] = await Promise.all([
      admin.from("employee_relationships").select("employment_status").eq("user_id", user.id).maybeSingle(),
      admin.from("employee_security_settings").select("employee_access_frozen,ceo_user_id").eq("singleton", true).maybeSingle(),
    ]);

    if (employeeError || settingsError) {
      return NextResponse.json({ error: "Employee access could not be verified." }, { status: 503 });
    }
    if (employee?.employment_status !== "active" || !settings?.ceo_user_id || settings.employee_access_frozen) {
      return NextResponse.json({ error: "Active employee access is required." }, { status: 403 });
    }

    const { data: authorized, error: authorizationError } = await admin.rpc(
      "mme_employee_authorize_catalog_action",
      {
        p_actor_user_id: user.id,
        p_permission_key: "catalog.create",
        p_target_product_id: null,
        p_submitter_user_id: null,
      },
    );
    if (authorizationError) {
      return NextResponse.json({ error: "Catalog authorization service is unavailable." }, { status: 503 });
    }
    if (authorized !== true) {
      return NextResponse.json({ error: "You do not have permission to create catalog drafts." }, { status: 403 });
    }

    const { data: categoryRow, error: categoryError } = await admin
      .from("product_categories").select("id").eq("slug", category).eq("is_active", true).maybeSingle();
    if (categoryError || !categoryRow) {
      return NextResponse.json({ error: "Selected product category is unavailable." }, { status: 400 });
    }

    const baseSlug = slugify(name) || "product";
    const productSlug = `${baseSlug}-${slugify(sku)}`.slice(0, 160);
    const { data: product, error: insertError } = await admin
      .from("products")
      .insert({
        category_id: categoryRow.id,
        sku,
        slug: productSlug,
        name,
        brand,
        model_number: modelNumber,
        upc_ean: upcEan,
        description,
        condition,
        tracking_mode: tracking,
        catalog_status: "draft",
        specifications,
        warranty_summary: warranty,
        created_by: user.id,
      })
      .select("id,sku,name,catalog_status,version,created_at")
      .single();

    if (insertError || !product) {
      if (insertError?.code === "23505") {
        return NextResponse.json({ error: "That SKU or product slug already exists." }, { status: 409 });
      }
      return NextResponse.json({ error: "Product draft could not be saved." }, { status: 500 });
    }

    if (mediaUrl) {
      const { error: mediaError } = await admin.from("product_media").insert({
        product_id: product.id,
        media_type: new URL(mediaUrl).pathname.match(/\.(mp4|webm|mov)$/i) ? "video" : "image",
        external_url: mediaUrl,
        alt_text: `${name} product media`,
        is_primary: true,
      });
      if (mediaError) {
        return NextResponse.json({ error: "Draft was created but media could not be attached. Contact an administrator before retrying.", product_id: product.id }, { status: 500 });
      }
    }

    const { error: auditError } = await admin.from("product_catalog_events").insert({
      product_id: product.id,
      event_type: "draft_created",
      actor_id: user.id,
      product_version: product.version,
      event_data: { source: "employee_catalog_api" },
    });
    if (auditError) {
      // Do not return a success response when the required audit event failed.
      // The product row remains visible to administrators for reconciliation.
      return NextResponse.json({ error: "Draft was created but its audit event failed. Contact an administrator before retrying.", product_id: product.id }, { status: 500 });
    }

    return NextResponse.json({ product }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "Catalog service is not configured or unavailable." }, { status: 503 });
  }
}
