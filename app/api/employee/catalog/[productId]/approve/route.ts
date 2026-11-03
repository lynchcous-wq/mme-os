import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(_request: Request, context: { params: Promise<{ productId: string }> }) {
  const session = await createSessionClient();
  const { data: { user }, error } = await session.auth.getUser();
  if (error || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  const { productId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId))
    return NextResponse.json({ error: "Invalid product identifier." }, { status: 400 });
  try {
    const admin = createAdminClient();
    const { data, error: rpcError } = await admin.rpc("mme_catalog_approve_product", { p_actor_user_id: user.id, p_product_id: productId });
    if (rpcError) {
      if (rpcError.code === "42501") return NextResponse.json({ error: "Approval permission required. Self-approval is prohibited." }, { status: 403 });
      if (rpcError.code === "40001") return NextResponse.json({ error: "Product is no longer awaiting approval." }, { status: 409 });
      return NextResponse.json({ error: "Atomic product approval failed." }, { status: 500 });
    }
    return NextResponse.json({ product: data });
  } catch { return NextResponse.json({ error: "Catalog approval service unavailable." }, { status: 503 }); }
}
