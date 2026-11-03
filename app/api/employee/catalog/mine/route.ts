import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const session = await createSessionClient();
  const { data: { user }, error } = await session.auth.getUser();
  if (error || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  try {
    const admin = createAdminClient();
    const [{ data: employee, error: employeeError }, { data: settings, error: settingsError }] = await Promise.all([
      admin.from("employee_relationships").select("employment_status").eq("user_id",user.id).maybeSingle(),
      admin.from("employee_security_settings").select("employee_access_frozen,ceo_user_id").eq("singleton",true).maybeSingle(),
    ]);
    if (employeeError || settingsError) return NextResponse.json({ error: "Employee access could not be verified." }, { status: 503 });
    if (employee?.employment_status !== "active" || !settings?.ceo_user_id || settings.employee_access_frozen) return NextResponse.json({ error: "Active employee access is required." }, { status: 403 });

    const { data: products, error: queryError } = await admin.from("products")
      .select("id,sku,name,brand,model_number,upc_ean,description,condition,tracking_mode,specifications,warranty_summary,catalog_status,correction_notes,version,updated_at,product_categories(slug)")
      .eq("created_by",user.id).eq("catalog_status","changes_requested").order("updated_at",{ascending:false}).limit(100);
    if (queryError) return NextResponse.json({ error: "Returned drafts could not be loaded. Confirm the correction migration is applied." }, { status: 500 });
    return NextResponse.json({ products: (products ?? []).map(product => ({ ...product, category: Array.isArray(product.product_categories) ? product.product_categories[0]?.slug ?? "televisions" : product.product_categories?.slug ?? "televisions" })) });
  } catch {
    return NextResponse.json({ error: "Employee draft service unavailable." }, { status: 503 });
  }
}
