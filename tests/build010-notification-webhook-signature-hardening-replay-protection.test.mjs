import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/webhooks/security-notification-receipts/route.ts", import.meta.url), "utf8");

test("webhook bodies are capped while streaming, before full allocation", () => {
  assert.match(route, /MAX_BODY_BYTES = 1024 \* 1024/);
  assert.match(route, /getReader\(\)/);
  assert.match(route, /value\.byteLength/);
  assert.match(route, /reader\.cancel\(\)/);
});

test("provider timestamps must be numeric and within the replay window", () => {
  assert.match(route, /MAX_CLOCK_SKEW_SECONDS = 300/);
  assert.match(route, /freshTimestamp\(timestamp\)/);
  assert.match(route, /Math\.abs\(Math\.floor\(Date\.now\(\) \/ 1000\) - seconds\)/);
});

test("Resend signatures bind event id, timestamp, and exact raw body", () => {
  assert.match(route, /id \+ "\." \+ timestamp \+ "\." \+ raw/);
  assert.match(route, /svix-id/);
  assert.match(route, /svix-signature/);
});

test("pager and push signatures bind a fresh timestamp to the raw body", () => {
  assert.match(route, /x-mme-timestamp/);
  assert.match(route, /timestamp \+ "\." \+ raw/);
  assert.match(route, /timingSafeEqual/);
});

test("Twilio signature validation remains provider-compatible and constant-time", () => {
  assert.match(route, /x-twilio-signature/);
  assert.match(route, /MME_TWILIO_STATUS_CALLBACK_URL/);
  assert.match(route, /safeEqual\(signature, expected\)/);
});

test("malformed payloads and invalid correlation fields fail closed", () => {
  assert.match(route, /invalid_payload/);
  assert.match(route, /receipt_correlation_fields_invalid/);
  assert.match(route, /eventId\.length > 250/);
  assert.match(route, /reference\.length > 500/);
});

test("webhook persistence calls the exact migration RPC contract", () => {
  assert.match(route, /mme_security_notification_ingest_provider_receipt/);
  assert.match(route, /p_reference: reference/);
  assert.match(route, /p_channel: channel/);
  assert.match(route, /p_event: event/);
  assert.doesNotMatch(route, /mme_security_notification_apply_provider_receipt/);
});

test("provider receipt persistence remains server-side and cache-disabled", () => {
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(route, /mme_security_notification_apply_provider_receipt/);
  assert.match(route, /cache: "no-store"/);
});
