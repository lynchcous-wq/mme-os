import { NextRequest, NextResponse } from "next/server";
import { createHash, createHmac, timingSafeEqual, randomUUID } from "node:crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_BODY_BYTES = 1024 * 1024;
const MAX_CLOCK_SKEW_SECONDS = 300;
const digest = (value: string) => createHash("sha256").update(value).digest("hex");

function safeEqual(left: string, right: string) {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function readLimitedBody(req: NextRequest) {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) return null;
  if (!req.body) return "";
  const reader = req.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  let body = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BODY_BYTES) {
        await reader.cancel();
        return null;
      }
      body += decoder.decode(value, { stream: true });
    }
    return body + decoder.decode();
  } finally {
    reader.releaseLock();
  }
}

function freshTimestamp(value: string) {
  if (!/^\d{10}$/.test(value)) return false;
  const seconds = Number(value);
  return Number.isSafeInteger(seconds) &&
    Math.abs(Math.floor(Date.now() / 1000) - seconds) <= MAX_CLOCK_SKEW_SECONDS;
}

function verifyResend(raw: string, req: NextRequest) {
  const secret = process.env.RESEND_WEBHOOK_SECRET;
  const id = req.headers.get("svix-id") ?? "";
  const timestamp = req.headers.get("svix-timestamp") ?? "";
  const signature = req.headers.get("svix-signature") ?? "";
  if (!secret || !id || !freshTimestamp(timestamp) || !signature) return false;
  try {
    const key = Buffer.from(secret.replace(/^whsec_/, ""), "base64");
    const expected = createHmac("sha256", key)
      .update(id + "." + timestamp + "." + raw)
      .digest("base64");
    return signature.split(" ").some((part) => {
      const [version, value, ...extra] = part.split(",");
      return version === "v1" && !!value && extra.length === 0 && safeEqual(value, expected);
    });
  } catch {
    return false;
  }
}

function verifyTwilio(raw: string, req: NextRequest) {
  const token = process.env.TWILIO_AUTH_TOKEN;
  const signature = req.headers.get("x-twilio-signature") ?? "";
  const callbackUrl = process.env.MME_TWILIO_STATUS_CALLBACK_URL;
  if (!token || !signature || !callbackUrl) return false;
  const params = new URLSearchParams(raw);
  const canonical = callbackUrl + [...params.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => key + value)
    .join("");
  const expected = createHmac("sha1", token).update(canonical).digest("base64");
  return safeEqual(signature, expected);
}

function verifyTimestampedHmac(raw: string, req: NextRequest, provider: "pagerduty" | "push") {
  const secret = process.env[provider === "pagerduty" ? "MME_PAGER_WEBHOOK_SECRET" : "MME_PUSH_WEBHOOK_SECRET"];
  const timestamp = req.headers.get("x-mme-timestamp") ?? "";
  const signature = req.headers.get("x-mme-signature") ?? "";
  if (!secret || !freshTimestamp(timestamp) || !signature.startsWith("sha256=")) return false;
  const expected = createHmac("sha256", secret).update(timestamp + "." + raw).digest("hex");
  return safeEqual(signature.slice(7), expected);
}

async function persist(provider: string, eventId: string, reference: string, channel: string, status: string, event: Record<string, any>) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return { ok: false, status: 503 };
  const response = await fetch(url + "/rest/v1/rpc/mme_security_notification_ingest_provider_receipt", {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: "Bearer " + key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_provider: provider,
      p_event_id: eventId,
      p_reference: reference,
      p_channel: channel,
      p_status: status,
      p_event: event,
    }),
    cache: "no-store",
  });
  return { ok: response.ok, status: response.status, body: response.ok ? await response.json() : null };
}

export async function POST(req: NextRequest) {
  const requestId = randomUUID();
  const provider = req.nextUrl.searchParams.get("provider") ?? "";
  const raw = await readLimitedBody(req);
  if (raw === null) {
    return NextResponse.json({ error: "payload_too_large", requestId }, { status: 413 });
  }

  let event: Record<string, any> = {};
  let eventId = "";
  let reference = "";
  let type = "";
  let status = "unknown";

  try {
    if (provider === "resend") {
      if (!verifyResend(raw, req)) return NextResponse.json({ error: "invalid_provider_signature", requestId }, { status: 401 });
      event = JSON.parse(raw);
      eventId = String(event.id ?? req.headers.get("svix-id") ?? "");
      reference = String(event.data?.email_id ?? event.data?.id ?? "");
      type = String(event.type ?? "unknown");
      status = type === "email.delivered" ? "delivered" :
        type === "email.bounced" || type === "email.complained" ? "failed" :
        type === "email.sent" ? "accepted" : "unknown";
    } else if (provider === "twilio") {
      if (!verifyTwilio(raw, req)) return NextResponse.json({ error: "invalid_provider_signature", requestId }, { status: 401 });
      const params = new URLSearchParams(raw);
      event = Object.fromEntries(params.entries());
      eventId = String(event.MessageSid ?? "") + ":" + String(event.MessageStatus ?? "unknown") + ":" + String(event.ErrorCode ?? "");
      reference = String(event.MessageSid ?? "");
      type = String(event.MessageStatus ?? "unknown");
      status = type === "delivered" ? "delivered" :
        type === "undelivered" ? "undelivered" :
        type === "failed" ? "failed" :
        type === "sent" ? "accepted" :
        type === "queued" ? "accepted" : "unknown";
    } else if (provider === "pagerduty" || provider === "push") {
      if (!verifyTimestampedHmac(raw, req, provider)) {
        return NextResponse.json({ error: "invalid_provider_signature", requestId }, { status: 401 });
      }
      event = JSON.parse(raw);
      eventId = String(event.eventId ?? event.id ?? "");
      reference = String(event.reference ?? event.deliveryId ?? "");
      type = String(event.eventType ?? event.status ?? "unknown");
      status = ["delivered", "failed", "undelivered", "accepted", "sent"].includes(type) ? type : "unknown";
    } else {
      return NextResponse.json({ error: "unsupported_provider", requestId }, { status: 400 });
    }
  } catch {
    return NextResponse.json({ error: "invalid_payload", requestId }, { status: 400 });
  }

  if (!eventId.trim() || !reference.trim() || eventId.length > 250 || reference.length > 500) {
    return NextResponse.json({ error: "receipt_correlation_fields_invalid", requestId }, { status: 400 });
  }

  const channel = provider === "resend" ? "email" : provider === "twilio" ? "sms" : provider === "pagerduty" ? "pager" : "push";
  const saved = await persist(provider, eventId, reference, channel, status, event);
  if (!saved.ok) {
    return NextResponse.json({ error: "receipt_persistence_failed", requestId }, { status: saved.status });
  }
  return NextResponse.json({ requestId, ...saved.body }, { headers: { "Cache-Control": "no-store" } });
}
