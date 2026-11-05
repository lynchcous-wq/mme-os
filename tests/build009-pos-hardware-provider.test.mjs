import test from "node:test";
import assert from "node:assert/strict";
import {
  normalizeProviderHardwareEvent,
  signHardwareWebhookForTest,
  verifyHardwareWebhook,
} from "../lib/pos/hardware-provider.ts";

const secret = "test-only-provider-webhook-secret";
const body = JSON.stringify({ event_id: "evt_001", device_id: "drawer_01", event_type: "drawer.failed", occurred_at: "2026-11-05T18:00:00.000Z", safe_detail: "drawer motor stalled" });
const timestamp = "1793901600";

test("verifies an authentic provider signature against exact raw bytes", () => {
  const signatureHeader = signHardwareWebhookForTest(body, timestamp, secret);
  assert.deepEqual(verifyHardwareWebhook({ rawBody: body, signatureHeader, timestampHeader: timestamp, secret, nowEpochSeconds: Number(timestamp) }), { valid: true });
});

test("rejects modified body, wrong secret, malformed signature and stale timestamp", () => {
  const signatureHeader = signHardwareWebhookForTest(body, timestamp, secret);
  assert.equal(verifyHardwareWebhook({ rawBody: body + " ", signatureHeader, timestampHeader: timestamp, secret, nowEpochSeconds: Number(timestamp) }).valid, false);
  assert.equal(verifyHardwareWebhook({ rawBody: body, signatureHeader, timestampHeader: timestamp, secret: "wrong", nowEpochSeconds: Number(timestamp) }).valid, false);
  assert.equal(verifyHardwareWebhook({ rawBody: body, signatureHeader: "sha256=bad", timestampHeader: timestamp, secret, nowEpochSeconds: Number(timestamp) }).valid, false);
  assert.equal(verifyHardwareWebhook({ rawBody: body, signatureHeader, timestampHeader: timestamp, secret, nowEpochSeconds: Number(timestamp) + 301 }).reason, "timestamp_out_of_window");
});

test("rejects oversized bodies and missing verification inputs", () => {
  assert.equal(verifyHardwareWebhook({ rawBody: "x".repeat(65537), signatureHeader: "sha256=" + "a".repeat(64), timestampHeader: timestamp, secret, nowEpochSeconds: Number(timestamp) }).reason, "invalid_signature");
  assert.equal(verifyHardwareWebhook({ rawBody: body, signatureHeader: null, timestampHeader: timestamp, secret }).reason, "missing_header");
});

test("normalizes a provider event through an explicit event mapping", () => {
  const normalized = normalizeProviderHardwareEvent({
    payload: JSON.parse(body),
    mapping: { "drawer.failed": "drawer_open_failed" },
  });
  assert.deepEqual(normalized, {
    providerEventId: "evt_001",
    deviceReference: "drawer_01",
    eventType: "drawer_open_failed",
    occurredAt: "2026-11-05T18:00:00.000Z",
    safeDetail: "drawer motor stalled",
  });
});

test("rejects unknown provider event types and malformed payloads", () => {
  assert.throws(() => normalizeProviderHardwareEvent({ payload: JSON.parse(body), mapping: {} }));
  assert.throws(() => normalizeProviderHardwareEvent({ payload: null, mapping: {} }));
});

test("normalizer bounds safe detail and removes control-line injection", () => {
  const normalized = normalizeProviderHardwareEvent({
    payload: { ...JSON.parse(body), safe_detail: "line1\nline2\t" + "x".repeat(400) },
    mapping: { "drawer.failed": "drawer_open_failed" },
  });
  assert.equal(normalized.safeDetail?.includes("\n"), false);
  assert.equal(normalized.safeDetail?.includes("\t"), false);
  assert.equal(normalized.safeDetail?.length, 300);
});
