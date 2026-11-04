import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

type Resolution = "return_to_stock" | "write_off" | "return_to_supplier";
type Condition = "new" | "open_box" | "refurbished" | "used" | "damaged" | "unusable";

async function rpc<T>(base: string, service: string, name: string, body: unknown) {
  const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  const data = response.ok ? await response.json().catch(() => null) as T | null : null;
  return { ok: response.ok, data };
}

export async function POST(request: Request) {
  const token = request.headers.get("authorization")?.match(/^Bearer ([^\s]+)$/)?.[1];
  if (!token) return NextResponse.json({ error: "Manager sign-in is required." }, { status: 401 });

  const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !anon || !service) {
    return NextResponse.json({ error: "Inspection resolution is not configured." }, { status: 503 });
  }

  try {
    const auth = await fetch(`${base}/auth/v1/user`, {
      headers: { apikey: anon, Authorization: `Bearer ${token}` },
      cache: "no-store",
    });
    if (!auth.ok) return NextResponse.json({ error: "Manager session is invalid or expired." }, { status: 401 });
    const user = await auth.json() as { id?: string };
    if (!user.id) return NextResponse.json({ error: "Manager identity could not be verified." }, { status: 401 });

    const input = await request.json() as {
      inspection_id?: string;
      resolution?: Resolution;
      condition_after?: Condition | null;
      reason?: string;
    };
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const resolutions: Resolution[] = ["return_to_stock", "write_off", "return_to_supplier"];
    const conditions: Condition[] = ["new", "open_box", "refurbished", "used", "damaged", "unusable"];
    if (!input.inspection_id || !uuidPattern.test(input.inspection_id) ||
        !input.resolution || !resolutions.includes(input.resolution) ||
        typeof input.reason !== "string" || input.reason.trim().length < 5 || input.reason.length > 1000 ||
        (input.condition_after !== undefined && input.condition_after !== null && !conditions.includes(input.condition_after))) {
      return NextResponse.json({ error: "Provide a valid inspection, resolution, condition and reason." }, { status: 400 });
    }
    if (input.resolution === "return_to_stock" &&
        (!input.condition_after || !["new", "open_box", "refurbished", "used"].includes(input.condition_after))) {
      return NextResponse.json({ error: "Return-to-stock requires a saleable condition grade." }, { status: 400 });
    }

    const lookup = new URLSearchParams({
      select: "id,product_id,location_id,serialized_unit_id,disposition",
      id: `eq.${input.inspection_id}`,
      limit: "1",
    });
    const recordResponse = await fetch(`${base}/rest/v1/mme_inventory_inspections?${lookup}`, {
      headers: { apikey: service, Authorization: `Bearer ${service}` },
      cache: "no-store",
    });
    if (!recordResponse.ok) return NextResponse.json({ error: "Could not verify inspection record." }, { status: 502 });
    const records = await recordResponse.json() as Array<{
      id: string; product_id: string; location_id: string; serialized_unit_id: string | null; disposition: string;
    }>;
    const record = records[0];
    if (!record || record.disposition !== "pending") {
      return NextResponse.json({ error: "Inspection is missing or no longer pending review." }, { status: 409 });
    }
    if (record.serialized_unit_id && input.resolution !== "return_to_stock") {
      return NextResponse.json({
        error: "Serialized-device write-off and supplier-return workflows require a dedicated unit-ledger transaction and are not enabled yet. The device remains quarantined.",
      }, { status: 409 });
    }

    for (const permissionKey of ["inventory.inspection.approve", "inventory.inspection.resolve"]) {
      const permission = await rpc<boolean>(base, service, "mme_employee_authorize_inventory_action", {
        p_actor_user_id: user.id,
        p_permission_key: permissionKey,
        p_target_product_id: record.product_id,
        p_target_location_id: record.location_id,
      });
      if (!permission.ok || permission.data !== true) {
        return NextResponse.json({ error: "Your account lacks the required manager approval and resolution permissions." }, { status: 403 });
      }
    }

    const functionName = record.serialized_unit_id
      ? "mme_resolve_serialized_inspection"
      : "mme_resolve_aggregate_inspection";
    const resolved = await rpc<boolean>(base, service, functionName, {
      p_inspection_id: record.id,
      p_resolution: input.resolution,
      p_condition_after: input.condition_after ?? null,
      p_reason: input.reason.trim(),
      p_actor_identity_id: user.id,
      p_approved_by_identity_id: user.id,
    });
    if (!resolved.ok) return NextResponse.json({ error: "The database rejected the inspection resolution." }, { status: 409 });
    if (resolved.data !== true) return NextResponse.json({ error: "Inspection was already resolved or its inventory state changed." }, { status: 409 });

    return NextResponse.json(
      { inspection_id: record.id, resolution: input.resolution, status: "resolved" },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return NextResponse.json({ error: "Inspection resolution is temporarily unavailable." }, { status: 502 });
  }
}
