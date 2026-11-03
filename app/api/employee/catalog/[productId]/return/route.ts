import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: Request, context: { params: Promise<{ productId: string }> }) {
  const session = await createSessionClient();
  const { data: { user }, error: authError } = await session.auth.getUser();
  if (authError || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });

  const { productId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId)) {
    return NextResponse.json({ error: "Invalid product identifier." }, { status: 400 });
  }

  let body: { correction_notes?: unknown };
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) return NextResponse.json({ error: "A JSON object is required." }, { status: 400 });
    body = value as { correction_notes?: unknown };
  } catch {
    return NextResponse.json({ error: "Invalid JSON body." }, { status: 400 });
  }
  const notes = typeof body.correction_notes === "string" ? body.correction_notes.trim() : "";
  if (notes.length < 10 || notes.length > 2000) {
    return NextResponse.json({ error: "Correction notes must be between 10 and 2,000 characters." }, { status: 400 });
  }

  try {
    const admin = createAdminClient();
    const { data: allowed, error: authzError } = await admin.rpc("mme_employee_authorize_catalog_action", {
      p_actor_user_id: user.id, p_permission_key: "catalog.return", p_target_product_id: productId, p_submitter_user_id: null,
    });
    if (authzError) return NextResponse.json({ error: "Review authorization unavailable." }, { status: 503 });
    if (allowed !== true) return NextResponse.json({ error: "Catalog return-for-correction permission required." }, { status: 403 });

    const { data: existing, error: lookupError } = await admin.from("products")
      .select("id,created_by,catalog_status").eq("id", productId).maybeSingle();
    if (lookupError) return NextResponse.json({ error: "Product could not be loaded." }, { status: 500 });
    if (!existing || existing.catalog_status !== "pending_approval") return NextResponse.json({ error: "Product is no longer awaiting review." }, { status: 409 });
    if (existing.created_by === user.id) return NextResponse.json({ error: "A submitter cannot review their own product." }, { status: 403 });

    const { data: product, error: updateError } = await admin.from("products")
      .update({ catalog_status: "changes_requested", correction_notes: notes, returned_by: user.id, returned_at: new Date().toISOString() })
      .eq("id", productId).eq("catalog_status", "pending_approval")
      .select("id,sku,name,catalog_status,correction_notes,returned_by,returned_at,version").maybeSingle();
    if (updateError) return NextResponse.json({ error: "Product could not be returned for correction. Confirm the new database migration is applied." }, { status: 500 });
    if (!product) return NextResponse.json({ error: "Product review state changed. Refresh the queue." }, { status: 409 });

    const { error: auditError } = await admin.from("product_catalog_events").insert({
      product_id: product.id, event_type: "changes_requested", actor_id: user.id,
      product_version: product.version, event_data: { correction_notes: notes },
    });
    if (auditError) return NextResponse.json({ error: "Correction request saved but audit event failed. Contact an administrator.", product_id: product.id }, { status: 500 });
    return NextResponse.json({ product });
  } catch {
    return NextResponse.json({ error: "Catalog review service unavailable." }, { status: 503 });
  }
}
