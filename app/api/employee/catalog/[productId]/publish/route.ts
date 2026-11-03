import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(_request: Request, context: { params: Promise<{ productId: string }> }) {
  const session = await createSessionClient();
  const { data: { user }, error } = await session.auth.getUser();
  if (error || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  const { productId } = await context.params;
  if (!/^[0-9a-f-]{36}$/i.test(productId)) return NextResponse.json({ error: "Invalid product identifier." }, { status: 400 });
  try {
    const admin = createAdminClient();
    const { data: allowed, error: authError } = await admin.rpc("mme_employee_authorize_catalog_action", {
      p_actor_user_id: user.id, p_permission_key: "catalog.publish", p_target_product_id: productId, p_submitter_user_id: null,
    });
    if (authError) return NextResponse.json({ error: "Publication authorization unavailable." }, { status: 503 });
    if (allowed !== true) return NextResponse.json({ error: "Publication permission required. The product must be approved first." }, { status: 403 });
    const { data: product, error: updateError } = await admin.from("products")
      .update({ catalog_status: "published", published_at: new Date().toISOString() })
      .eq("id", productId).eq("catalog_status", "pending_approval")
      .not("approved_by", "is", null).not("approved_at", "is", null)
      .select("id,sku,name,catalog_status,approved_by,approved_at,published_at,version").maybeSingle();
    if (updateError) return NextResponse.json({ error: "Product could not be published." }, { status: 500 });
    if (!product) return NextResponse.json({ error: "Product is not approved or is no longer awaiting publication." }, { status: 409 });
    const { error: auditError } = await admin.from("product_catalog_events").insert({
      product_id: product.id, event_type: "published", actor_id: user.id, product_version: product.version, event_data: {},
    });
    if (auditError) return NextResponse.json({ error: "Publication saved but audit event failed. Contact an administrator.", product_id: product.id }, { status: 500 });
    return NextResponse.json({ product });
  } catch {
    return NextResponse.json({ error: "Catalog publication service unavailable." }, { status: 503 });
  }
}
