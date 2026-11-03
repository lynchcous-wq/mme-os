import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(_request: Request, context: { params: Promise<{ productId: string }> }) {
  const session = await createSessionClient();
  const { data: { user }, error: authError } = await session.auth.getUser();
  if (authError || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  const { productId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId)) {
    return NextResponse.json({ error: "Invalid product identifier." }, { status: 400 });
  }
  try {
    const admin = createAdminClient();
    const { data: allowed, error: authzError } = await admin.rpc("mme_employee_authorize_catalog_action", {
      p_actor_user_id: user.id, p_permission_key: "catalog.approve", p_target_product_id: productId, p_submitter_user_id: null,
    });
    if (authzError) return NextResponse.json({ error: "Approval authorization unavailable." }, { status: 503 });
    if (allowed !== true) return NextResponse.json({ error: "You are not authorized to approve this product. Self-approval is prohibited." }, { status: 403 });

    const { data: product, error: updateError } = await admin.from("products")
      .update({ approved_by: user.id, approved_at: new Date().toISOString() })
      .eq("id", productId).eq("catalog_status", "pending_approval")
      .is("approved_by", null).select("id,sku,name,catalog_status,approved_by,approved_at,version").maybeSingle();
    if (updateError) return NextResponse.json({ error: "Product approval could not be saved." }, { status: 500 });
    if (!product) return NextResponse.json({ error: "Product is no longer awaiting approval or has already been reviewed." }, { status: 409 });

    const { error: auditError } = await admin.from("product_catalog_events").insert({
      product_id: product.id, event_type: "approved", actor_id: user.id,
      product_version: product.version, event_data: {},
    });
    if (auditError) return NextResponse.json({ error: "Approval saved but audit event failed. Contact an administrator.", product_id: product.id }, { status: 500 });
    return NextResponse.json({ product });
  } catch {
    return NextResponse.json({ error: "Catalog approval service unavailable." }, { status: 503 });
  }
}
