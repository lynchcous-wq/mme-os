import { readJsonObject } from "@/lib/http/read-json-object";
import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: Request, context: { params: Promise<{ productId: string }> }) {
  const session = await createSessionClient();
  const { data: { user }, error } = await session.auth.getUser();
  if (error || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  const { productId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(productId))
    return NextResponse.json({ error: "Invalid product identifier." }, { status: 400 });
  const parsed = await readJsonObject(request, 4_000);
  if (!parsed.ok) return NextResponse.json({ error: parsed.error }, { status: parsed.status });
  const body = parsed.value;
  const notes = typeof body.correction_notes === "string" ? body.correction_notes.trim() : "";
  if (notes.length < 10 || notes.length > 2000) return NextResponse.json({ error: "Correction notes must be between 10 and 2,000 characters." }, { status: 400 });
  try {
    const admin = createAdminClient();
    const { data, error: rpcError } = await admin.rpc("mme_catalog_return_for_correction", {
      p_actor_user_id: user.id, p_product_id: productId, p_correction_notes: notes,
    });
    if (rpcError) {
      if (rpcError.code === "42501") return NextResponse.json({ error: "You are not authorized to return this product, or self-review is prohibited." }, { status: 403 });
      if (rpcError.code === "40001") return NextResponse.json({ error: "Product review state changed. Refresh the queue." }, { status: 409 });
      if (rpcError.code === "22023") return NextResponse.json({ error: rpcError.message }, { status: 400 });
      return NextResponse.json({ error: "Atomic correction request failed." }, { status: 500 });
    }
    return NextResponse.json({ product: data });
  } catch { return NextResponse.json({ error: "Catalog review service unavailable." }, { status: 503 }); }
}
