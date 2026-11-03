import { NextResponse } from "next/server";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

const conditions = new Set(["new","open_box","like_new","refurbished","used_excellent","used_good","used_fair","parts_only","damaged","inspection_required"]);
const trackingModes = new Set(["quantity","serialized"]);
const categories = new Set(["televisions","laptops","tablets","cellphones","smartwatches","accessories","audio","gaming","smart-home","services-subscriptions"]);
const clean = (value: unknown, max: number) => typeof value === "string" && value.trim().length > 0 && value.trim().length <= max ? value.trim() : null;

export async function POST(request: Request) {
  const session = await createSessionClient();
  const { data: { user }, error: authError } = await session.auth.getUser();
  if (authError || !user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });

  let body: Record<string, unknown>;
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) return NextResponse.json({ error: "A JSON object is required." }, { status: 400 });
    body = value as Record<string, unknown>;
  } catch { return NextResponse.json({ error: "Invalid JSON body." }, { status: 400 }); }

  const name=clean(body.name,160), sku=clean(body.sku,64), category=clean(body.category,80);
  const brand=body.brand == null || body.brand === "" ? null : clean(body.brand,100);
  const model=body.model_number == null || body.model_number === "" ? null : clean(body.model_number,100);
  const upc=body.upc_ean == null || body.upc_ean === "" ? null : clean(body.upc_ean,64);
  const description=body.description == null || body.description === "" ? null : clean(body.description,5000);
  const warranty=body.warranty_summary == null || body.warranty_summary === "" ? null : clean(body.warranty_summary,500);
  const condition=typeof body.condition === "string" ? body.condition : "";
  const tracking=typeof body.tracking_mode === "string" ? body.tracking_mode : "";
  const specifications=body.specifications ?? {};
  const media=body.media_url == null || body.media_url === "" ? null : clean(body.media_url,2048);

  if (!name || !sku || !category || !/^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$/.test(sku) ||
      !categories.has(category) || !conditions.has(condition) || !trackingModes.has(tracking) ||
      (body.brand != null && body.brand !== "" && !brand) ||
      (body.model_number != null && body.model_number !== "" && !model) ||
      (body.upc_ean != null && body.upc_ean !== "" && !upc) ||
      (body.description != null && body.description !== "" && !description) ||
      (body.warranty_summary != null && body.warranty_summary !== "" && !warranty)) {
    return NextResponse.json({ error: "One or more product fields are invalid." }, { status: 400 });
  }
  if (media) {
    try { if (new URL(media).protocol !== "https:") throw new Error(); }
    catch { return NextResponse.json({ error: "Media link must be a valid HTTPS URL." }, { status: 400 }); }
  }
  if (!specifications || typeof specifications !== "object" || Array.isArray(specifications) || JSON.stringify(specifications).length>12000)
    return NextResponse.json({ error: "Specifications must be a JSON object no larger than 12,000 characters." }, { status: 400 });

  try {
    const admin=createAdminClient();
    const {data,error}=await admin.rpc("mme_catalog_create_product_draft",{
      p_actor_user_id:user.id,
      p_product_data:{name,sku,category,brand,model_number:model,upc_ean:upc,description,condition,
        tracking_mode:tracking,specifications,warranty_summary:warranty,media_url:media},
    });
    if(error){
      if(error.code==="42501") return NextResponse.json({error:"Active employee catalog-create permission is required."},{status:403});
      if(error.code==="22023") return NextResponse.json({error:error.message},{status:400});
      if(error.code==="23505") return NextResponse.json({error:"That SKU or product slug already exists."},{status:409});
      return NextResponse.json({error:"Atomic product draft creation failed."},{status:500});
    }
    return NextResponse.json({product:data},{status:201});
  } catch { return NextResponse.json({error:"Catalog service is not configured or unavailable."},{status:503}); }
}
