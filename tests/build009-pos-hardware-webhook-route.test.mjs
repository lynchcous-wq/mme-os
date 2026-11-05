import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/pos/hardware/webhook/[providerCode]/route.ts", import.meta.url), "utf8");

test("hardware webhook authenticates raw bytes before parsing or ingestion", () => {
  const verify = route.indexOf("verifyHardwareWebhook({");
  const parse = route.indexOf('try { payload = JSON.parse(rawBody.toString("utf8"));\n  catch');
  const ingest = route.indexOf('"/rest/v1/rpc/" + rpcName');
  assert.ok(verify >= 0 && parse > verify && ingest > parse);
  assert.ok(route.includes('request.headers.get("x-mme-signature")'));
  assert.ok(route.includes('request.headers.get("x-mme-timestamp")'));
});

test("hardware webhook resolves secret references only from server environment", () => {
  assert.ok(route.includes("MME_POS_WEBHOOK_SECRET_REFS_JSON"));
  assert.ok(route.includes("webhook_secret_ref"));
  assert.ok(route.includes("secretForReference(adapter.webhook_secret_ref)"));
  assert.ok(!route.includes("NEXT_PUBLIC_MME_POS"));
});

test("hardware webhook requires enabled adapter and exact provider device match", () => {
  assert.ok(route.includes("enabled=eq.true"));
  assert.ok(route.includes("provider=eq."));
  assert.ok(route.includes("device_reference=eq."));
  assert.ok(route.includes('device.status === "retired"'));
});

test("hardware webhook routes heartbeat through protected heartbeat RPC and other events through event ledger", () => {
  assert.ok(route.includes('"mme_pos_record_hardware_heartbeat"'));
  assert.ok(route.includes('"mme_pos_ingest_drawer_hardware_event"'));
  assert.ok(route.includes("p_provider_event_id"));
  assert.ok(route.includes("Cache-Control"));
});

test("hardware webhook bounds payload and rejects invalid provider and JSON", () => {
  assert.ok(route.includes("64 * 1024"));
  assert.ok(route.includes("providerCode"));
  assert.ok(route.includes("Webhook payload must be valid JSON."));
  assert.ok(route.includes("Webhook event is not valid for this provider."));
});
