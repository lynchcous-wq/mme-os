import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const token = request.headers.get("authorization")?.match(/^Bearer ([^\s]+)$/)?.[1];
  if (!token) return NextResponse.json({ error: "Employee sign-in required." }, { status: 401 });
  const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !anon || !service) return NextResponse.json({ error: "History is not configured." }, { status: 503 });
  try {
    const auth = await fetch(`${base}/auth/v1/user`, {
      headers: { apikey: anon, Authorization: `Bearer ${token}` }, cache: "no-store",
    });
    if (!auth.ok) return NextResponse.json({ error: "Session expired." }, { status: 401 });
    const user = await auth.json() as { id?: string };
    if (!user.id) return NextResponse.json({ error: "Invalid employee identity." }, { status: 401 });
    const query = new URLSearchParams({
      select: "id,inspection_reference,product_id,location_id,inspection_type,disposition,reason,findings,condition_before,condition_after,created_at,updated_at,resolved_at",
      inspected_by_identity_id: `eq.${user.id}`,
      order: "created_at.desc",
      limit: "50",
    });
    const response = await fetch(`${base}/rest/v1/mme_inventory_inspections?${query}`, {
      headers: { apikey: service, Authorization: `Bearer ${service}` }, cache: "no-store",
    });
    if (!response.ok) return NextResponse.json({ error: "Could not load inspection history." }, { status: 502 });
    const inspections = await response.json() as Array<Record<string, unknown>>;
    const authorized = [];
    for (const item of inspections) {
      const permission = await fetch(`${base}/rest/v1/rpc/mme_employee_authorize_inventory_action`, {
        method: "POST",
        headers: { apikey: service, Authorization: `Bearer ${service}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          p_actor_user_id: user.id,
          p_permission_key: "inventory.inspection.view",
          p_target_product_id: item.product_id,
          p_target_location_id: item.location_id,
        }),
        cache: "no-store",
      });
      if (permission.ok && await permission.json() === true) authorized.push(item);
    }
    const inspectionIds = authorized.map((item) => String(item.id));
    let dispositions: Array<Record<string, unknown>> = [];
    if (inspectionIds.length > 0) {
      const dispositionQuery = new URLSearchParams({
        select: "id,inspection_id,unit_id,product_id,location_id,resolution,prior_unit_status,resulting_unit_status,condition_before,condition_after,reason,actor_identity_id,approved_by_identity_id,created_at",
        inspection_id: `in.(${inspectionIds.join(",")})`,
        order: "created_at.desc",
      });
      const dispositionResponse = await fetch(`${base}/rest/v1/mme_serialized_unit_dispositions?${dispositionQuery}`, {
        headers: { apikey: service, Authorization: `Bearer ${service}` },
        cache: "no-store",
      });
      if (!dispositionResponse.ok) {
        return NextResponse.json({ error: "Disposition history could not be loaded." }, { status: 502 });
      }
      dispositions = await dispositionResponse.json() as Array<Record<string, unknown>>;
    }
    return NextResponse.json(
      { inspections: authorized, dispositions },
      { headers: { "Cache-Control": "no-store, private" } },
    );
  } catch {
    return NextResponse.json({ error: "Inspection history unavailable." }, { status: 502 });
  }
}
