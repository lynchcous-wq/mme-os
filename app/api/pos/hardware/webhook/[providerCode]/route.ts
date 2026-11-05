import { NextResponse } from "next/server";
import { normalizeProviderHardwareEvent, verifyHardwareWebhook, type PosHardwareEventType } from "@/lib/pos/hardware-provider";

export const dynamic = "force-dynamic";
export const revalidate = 0;
export const runtime = "nodejs";

type AdapterRow = { provider_code: string; webhook_secret_ref: string | null; capabilities: unknown; enabled: boolean };
type DeviceRow = { id: string; status: string };

function secretForReference(reference: string): string | null {
  const raw = process.env.MME_POS_WEBHOOK_SECRET_REFS_JSON;
  if (!raw) return null;
  try {
    const refs = JSON.parse(raw) as Record<string, unknown>;
    const value = Object.hasOwn(refs, reference) ? refs[reference] : undefined;
    return typeof value === "string" && value.length >= 32 ? value : null;
  } catch { return null; }
}

function eventMapping(capabilities: unknown): Record<string, PosHardwareEventType> {
  const allowed = new Set(["heartbeat","device_online","device_offline","drawer_open_confirmed","drawer_open_failed","drawer_closed_confirmed","connection_lost","connection_restored"]);
  const result: Record<string, PosHardwareEventType> = Object.create(null);
  if (!Array.isArray(capabilities)) return result;
  for (const item of capabilities) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const record = item as Record<string, unknown>;
    if (record.type !== "event_mapping" || !record.mapping || typeof record.mapping !== "object" || Array.isArray(record.mapping)) continue;
    for (const [providerType, canonicalType] of Object.entries(record.mapping as Record<string, unknown>)) {
      if (providerType.length > 80 || typeof canonicalType !== "string" || !allowed.has(canonicalType)) continue;
      result[providerType] = canonicalType as PosHardwareEventType;
    }
  }
  return result;
}

export async function POST(request: Request, context: { params: Promise<{ providerCode: string }> }) {
  const { providerCode } = await context.params;
  if (!/^[a-z0-9][a-z0-9_-]{0,79}$/.test(providerCode)) return NextResponse.json({ error: "Unknown provider." }, { status: 404 });
  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !serviceKey) return NextResponse.json({ error: "Hardware ingestion is not configured." }, { status: 503 });
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > 64 * 1024) return NextResponse.json({ error: "Payload too large." }, { status: 413 });
  const rawBody = Buffer.from(await request.arrayBuffer());
  if (rawBody.byteLength > 64 * 1024) return NextResponse.json({ error: "Payload too large." }, { status: 413 });
  const adapterResponse = await fetch(baseUrl + "/rest/v1/mme_pos_hardware_provider_adapters?select=provider_code,webhook_secret_ref,capabilities,enabled&provider_code=eq." + encodeURIComponent(providerCode) + "&enabled=eq.true&limit=1", {
    headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, Accept: "application/json" }, cache: "no-store",
  });
  if (!adapterResponse.ok) return NextResponse.json({ error: "Provider configuration is unavailable." }, { status: 503 });
  const adapters = await adapterResponse.json() as AdapterRow[];
  const adapter = adapters[0];
  if (!adapter || !adapter.webhook_secret_ref) return NextResponse.json({ error: "Provider is not enabled." }, { status: 404 });
  const secret = secretForReference(adapter.webhook_secret_ref);
  if (!secret) return NextResponse.json({ error: "Provider verification is not configured." }, { status: 503 });
  const verification = verifyHardwareWebhook({
    rawBody, signatureHeader: request.headers.get("x-mme-signature"),
    timestampHeader: request.headers.get("x-mme-timestamp"), secret,
  });
  if (!verification.valid) return NextResponse.json({ error: "Webhook authentication failed." }, { status: 401 });
  let payload: unknown;
  try { payload = JSON.parse(rawBody.toString("utf8")); }
  catch { return NextResponse.json({ error: "Webhook payload must be valid JSON." }, { status: 400 }); }
  let event;
  try { event = normalizeProviderHardwareEvent({ payload, mapping: eventMapping(adapter.capabilities) }); }
  catch { return NextResponse.json({ error: "Webhook event is not valid for this provider." }, { status: 400 }); }
  const deviceResponse = await fetch(baseUrl + "/rest/v1/mme_pos_register_devices?select=id,status&provider=eq." + encodeURIComponent(providerCode) + "&device_reference=eq." + encodeURIComponent(event.deviceReference) + "&limit=1", {
    headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, Accept: "application/json" }, cache: "no-store",
  });
  if (!deviceResponse.ok) return NextResponse.json({ error: "Device lookup failed." }, { status: 503 });
  const devices = await deviceResponse.json() as DeviceRow[];
  const device = devices[0];
  if (!device || device.status === "retired") return NextResponse.json({ error: "Registered device not found." }, { status: 404 });
  const rpcName = event.eventType === "heartbeat" ? "mme_pos_record_hardware_heartbeat" : "mme_pos_ingest_drawer_hardware_event";
  const rpcBody = event.eventType === "heartbeat"
    ? { p_device_id: device.id, p_provider_event_id: event.providerEventId, p_occurred_at: event.occurredAt }
    : { p_device_id: device.id, p_provider_event_id: event.providerEventId, p_event_type: event.eventType, p_occurred_at: event.occurredAt, p_command_attempt_id: null, p_safe_detail: event.safeDetail ?? null };
  const ingestResponse = await fetch(baseUrl + "/rest/v1/rpc/" + rpcName, {
    method: "POST", headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" },
    body: JSON.stringify(rpcBody), cache: "no-store",
  });
  if (!ingestResponse.ok) return NextResponse.json({ error: "Hardware event could not be recorded." }, { status: 502 });
  const eventId = await ingestResponse.json() as unknown;
  if (typeof eventId !== "string") return NextResponse.json({ error: "Hardware event service returned an invalid result." }, { status: 502 });
  return NextResponse.json({ accepted: true, event_id: eventId }, { status: 202, headers: { "Cache-Control": "no-store" } });
}