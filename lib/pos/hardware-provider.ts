import { createHmac, timingSafeEqual } from "node:crypto";

export type PosHardwareEventType =
  | "heartbeat" | "device_online" | "device_offline" | "drawer_open_confirmed"
  | "drawer_open_failed" | "drawer_closed_confirmed" | "connection_lost" | "connection_restored";

export type NormalizedHardwareEvent = {
  providerEventId: string;
  deviceReference: string;
  eventType: PosHardwareEventType;
  occurredAt: string;
  safeDetail?: string;
};

export type ProviderEventMapping = Readonly<Record<string, PosHardwareEventType>>;
export type WebhookVerification = {
  valid: boolean;
  reason?: "missing_header" | "invalid_timestamp" | "timestamp_out_of_window" | "invalid_signature";
};

const MAX_BODY_BYTES = 64 * 1024;
const MAX_CLOCK_SKEW_SECONDS = 300;

function constantTimeHexEqual(expected: string, supplied: string): boolean {
  if (!/^[a-f0-9]{64}$/i.test(supplied)) return false;
  const left = Buffer.from(expected, "hex");
  const right = Buffer.from(supplied, "hex");
  return left.length === right.length && timingSafeEqual(left, right);
}

/** Verify HMAC-SHA256 over timestamp + "." + exact raw request bytes. */
export function verifyHardwareWebhook(input: {
  rawBody: string | Buffer;
  signatureHeader: string | null;
  timestampHeader: string | null;
  secret: string;
  nowEpochSeconds?: number;
}): WebhookVerification {
  const { rawBody, signatureHeader, timestampHeader, secret } = input;
  if (!signatureHeader || !timestampHeader || !secret) return { valid: false, reason: "missing_header" };
  if (!/^\d{10}$/.test(timestampHeader)) return { valid: false, reason: "invalid_timestamp" };
  const timestamp = Number(timestampHeader);
  const now = input.nowEpochSeconds ?? Math.floor(Date.now() / 1000);
  if (!Number.isSafeInteger(now) || Math.abs(now - timestamp) > MAX_CLOCK_SKEW_SECONDS) {
    return { valid: false, reason: "timestamp_out_of_window" };
  }
  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(rawBody, "utf8");
  if (body.byteLength > MAX_BODY_BYTES) return { valid: false, reason: "invalid_signature" };
  const match = /^sha256=([a-f0-9]{64})$/i.exec(signatureHeader);
  if (!match) return { valid: false, reason: "invalid_signature" };
  const expected = createHmac("sha256", secret).update(timestampHeader).update(".").update(body).digest("hex");
  return constantTimeHexEqual(expected, match[1])
    ? { valid: true }
    : { valid: false, reason: "invalid_signature" };
}

export function signHardwareWebhookForTest(rawBody: string, timestamp: string, secret: string): string {
  return "sha256=" + createHmac("sha256", secret).update(timestamp).update(".").update(rawBody, "utf8").digest("hex");
}

export function normalizeProviderHardwareEvent(input: {
  payload: unknown;
  mapping: ProviderEventMapping;
}): NormalizedHardwareEvent {
  const { payload, mapping } = input;
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("Provider event payload must be an object.");
  }
  const value = payload as Record<string, unknown>;
  const providerEventId = typeof value.event_id === "string" ? value.event_id.trim() : "";
  const deviceReference = typeof value.device_id === "string" ? value.device_id.trim() : "";
  const providerType = typeof value.event_type === "string" ? value.event_type.trim() : "";
  const occurredAt = typeof value.occurred_at === "string" ? value.occurred_at : "";
  const epoch = Date.parse(occurredAt);
  const eventType = mapping[providerType];
  if (!providerEventId || providerEventId.length > 160 ||
      !deviceReference || deviceReference.length > 120 ||
      !eventType || !Number.isFinite(epoch)) {
    throw new Error("Provider event is missing a valid identifier, device, mapped type, or timestamp.");
  }
  const safeDetail = typeof value.safe_detail === "string"
    ? value.safe_detail.replace(/[\r\n\t]/g, " ").slice(0, 300)
    : undefined;
  return {
    providerEventId,
    deviceReference,
    eventType,
    occurredAt: new Date(epoch).toISOString(),
    ...(safeDetail ? { safeDetail } : {}),
  };
}
