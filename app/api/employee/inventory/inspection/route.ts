import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

type InspectionBody = {
  reference?: string;
  inspection_type?: string;
  reason?: string;
  findings?: Record<string, unknown>;
  battery_health_percent?: number | null;
  battery_test?: string;
  screen_test?: string;
  camera_test?: string;
  charging_port_test?: string;
  buttons_audio_test?: string;
  connectivity_test?: string;
  imei_serial_verification?: string;
  activation_lock_status?: string;
  notes?: string;
};

const testValues = ["pass", "fail", "not_applicable"] as const;
const inspectionTypes = [
  "customer_return",
  "receiving_damage",
  "warehouse_damage",
  "repair_intake",
  "quality_check",
  "warranty_return",
] as const;

function isTestValue(value: unknown): value is (typeof testValues)[number] {
  return typeof value === "string" && testValues.includes(value as (typeof testValues)[number]);
}

async function supabaseRequest<T>(
  url: string,
  key: string,
  method: string,
  body?: unknown,
  bearer?: string,
): Promise<{ ok: boolean; status: number; data: T | null }> {
  const response = await fetch(url, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${bearer ?? key}`,
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      Accept: "application/json",
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    cache: "no-store",
  });
  const data = response.ok ? await response.json().catch(() => null) as T | null : null;
  return { ok: response.ok, status: response.status, data };
}

export async function POST(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer ([^\s]+)$/);
  if (!match) {
    return NextResponse.json({ error: "A valid employee session is required." }, { status: 401 });
  }

  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !anonKey || !serviceKey) {
    return NextResponse.json({ error: "Inspection submission is not configured." }, { status: 503 });
  }

  const session = await supabaseRequest<{ id?: string }>(
    `${baseUrl}/auth/v1/user`, anonKey, "GET", undefined, match[1],
  );
  const actorUserId = session.data?.id;
  if (!session.ok || !actorUserId) {
    return NextResponse.json({ error: "Employee session is invalid or expired." }, { status: 401 });
  }

  let body: InspectionBody;
  try {
    body = await request.json() as InspectionBody;
  } catch {
    return NextResponse.json({ error: "Invalid inspection request." }, { status: 400 });
  }

  const reference = body.reference?.trim();
  const reason = body.reason?.trim();
  const inspectionType = body.inspection_type;
  const battery = body.battery_health_percent ?? null;
  if (!reference || reference.length > 128 || !reason || reason.length < 5 || reason.length > 4000 ||
      !inspectionTypes.includes(inspectionType as (typeof inspectionTypes)[number]) ||
      !body.findings || typeof body.findings !== "object" || Array.isArray(body.findings) ||
      (battery !== null && (!Number.isInteger(battery) || battery < 0 || battery > 100)) ||
      !isTestValue(body.battery_test) || !isTestValue(body.screen_test) ||
      !isTestValue(body.camera_test) || !isTestValue(body.charging_port_test) ||
      !isTestValue(body.buttons_audio_test) || !isTestValue(body.connectivity_test) ||
      !isTestValue(body.imei_serial_verification) ||
      !["clear", "locked", "not_applicable"].includes(body.activation_lock_status ?? "") ||
      typeof body.notes !== "string" || body.notes.length > 4000) {
    return NextResponse.json({ error: "Inspection fields are incomplete or invalid." }, { status: 400 });
  }

  if (battery !== null && body.battery_test === "not_applicable") {
    return NextResponse.json({ error: "Battery percentage cannot be supplied when the battery test is not applicable." }, { status: 400 });
  }

  try {
    const lookup = async (column: "serial_number" | "imei") => {
      const query = new URLSearchParams({ select: "id", [column]: `eq.${reference}`, limit: "2" });
      return supabaseRequest<Array<{ id: string }>>(
        `${baseUrl}/rest/v1/mme_serialized_units?${query.toString()}`,
        serviceKey, "GET",
      );
    };

    const serialResult = await lookup("serial_number");
    if (!serialResult.ok) throw new Error("unit_lookup_failed");
    let units = serialResult.data ?? [];
    if (units.length === 0) {
      const imeiResult = await lookup("imei");
      if (!imeiResult.ok) throw new Error("unit_lookup_failed");
      units = imeiResult.data ?? [];
    }
    if (units.length !== 1) {
      return NextResponse.json(
        { error: units.length > 1 ? "Device identifier is ambiguous." : "No serialized device matches that identifier." },
        { status: 404 },
      );
    }

    // In the current Build 001 schema, employee_relationships.user_id is the
    // auth.users primary key and inspection identity columns have no separate
    // identity table/mapping. The validated Auth subject is therefore the
    // canonical employee identity UUID for these inspection records.
    const rpc = await supabaseRequest<string>(
      `${baseUrl}/rest/v1/rpc/mme_submit_serialized_inspection`,
      serviceKey,
      "POST",
      {
        p_reference: reference,
        p_unit_id: units[0].id,
        p_inspection_type: inspectionType,
        p_reason: reason,
        p_findings: body.findings,
        p_battery_health_percent: battery,
        p_battery_test: body.battery_test,
        p_screen_test: body.screen_test,
        p_camera_test: body.camera_test,
        p_charging_port_test: body.charging_port_test,
        p_buttons_audio_test: body.buttons_audio_test,
        p_connectivity_test: body.connectivity_test,
        p_imei_serial_verification: body.imei_serial_verification,
        p_activation_lock_status: body.activation_lock_status,
        p_notes: body.notes,
        p_actor_user_id: actorUserId,
        p_actor_identity_id: actorUserId,
      },
    );

    if (!rpc.ok || !rpc.data) {
      return NextResponse.json(
        { error: rpc.status === 401 || rpc.status === 403
            ? "Employee is not authorized to submit this inspection."
            : "Inspection could not be submitted. Verify the device and try again." },
        { status: rpc.status === 401 || rpc.status === 403 ? 403 : 409 },
      );
    }

    return NextResponse.json(
      { inspection_id: rpc.data, status: "quarantined_pending_review" },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return NextResponse.json({ error: "Inspection service is temporarily unavailable." }, { status: 502 });
  }
}
