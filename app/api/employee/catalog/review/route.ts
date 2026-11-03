import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const session = await createSessionClient();
  const { data: { user }, error: authError } = await session.auth.getUser();
  if (authError || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });

  try {
    const admin = createAdminClient();
    const { data: allowed, error: authzError } = await admin.rpc("mme_employee_authorize_catalog_action", {
      p_actor_user_id: user.id,
      p_permission_key: "catalog.review",
      p_target_product_id: null,
      p_submitter_user_id: null,
    });
    if (authzError) return NextResponse.json({ error: "Review authorization service unavailable." }, { status: 503 });
    if (allowed !== true) return NextResponse.json({ error: "Catalog review permission required." }, { status: 403 });

    const { data: products, error } = await admin
      .from("products")
      .select("id,sku,name,brand,model_number,condition,tracking_mode,catalog_status,specifications,description,warranty_summary,created_by,approved_by,approved_at,version,created_at,updated_at,product_categories(name,slug)")
      .eq("catalog_status", "pending_approval")
      .order("created_at", { ascending: true })
      .limit(100);
    if (error) return NextResponse.json({ error: "Review queue could not be loaded." }, { status: 500 });

    const ids = (products ?? []).map((product) => product.id);
    const { data: events, error: eventsError } = ids.length
      ? await admin.from("product_catalog_events").select("id,product_id,event_type,actor_id,product_version,event_data,created_at").in("product_id", ids).order("created_at", { ascending: false }).limit(500)
      : { data: [], error: null };
    if (eventsError) return NextResponse.json({ error: "Product history could not be loaded." }, { status: 500 });

    const submitterIds = [...new Set((products ?? []).map((product) => product.created_by).filter(Boolean))] as string[];
    const userResults = await Promise.all(submitterIds.map((id) => admin.auth.admin.getUserById(id)));
    if (userResults.some((result) => result.error || !result.data.user)) return NextResponse.json({ error: "Submitter identity details unavailable." }, { status: 500 });
    const names = new Map(userResults.flatMap((result) => result.data.user ? [[result.data.user.id, result.data.user.email ?? "Employee"] as const] : []));

    return NextResponse.json({
      products: (products ?? []).map((product) => ({
        ...product,
        submitter_label: product.created_by ? names.get(product.created_by) ?? "Employee" : "Unknown",
        history: (events ?? []).filter((event) => event.product_id === product.id).map((event) => ({
          ...event, actor_label: event.actor_id ? names.get(event.actor_id) ?? "Employee" : "System",
        })),
      })),
    });
  } catch {
    return NextResponse.json({ error: "Catalog review service is not configured." }, { status: 503 });
  }
}
