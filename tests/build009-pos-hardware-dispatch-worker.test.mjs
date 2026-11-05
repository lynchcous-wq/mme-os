import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/internal/pos/hardware/dispatch/route.ts", import.meta.url), "utf8");
const registry = await readFile(new URL("../lib/pos/hardware-dispatch.ts", import.meta.url), "utf8");

test("dispatch worker requires a server-only bearer token and constant-time comparison", () => {
  assert.ok(route.includes("MME_POS_HARDWARE_WORKER_TOKEN"));
  assert.ok(route.includes("timingSafeEqual"));
  assert.ok(route.includes("Bearer"));
});

test("dispatch worker fails closed before claiming when no approved provider transport exists", () => {
  const guard = route.indexOf("No approved hardware transport is installed.");
  const claim = route.indexOf("mme_pos_claim_hardware_commands");
  assert.ok(guard >= 0 && claim > guard);
  assert.ok(registry.includes("registerPosHardwareTransport"));
  assert.ok(registry.includes("transports.has(providerCode)"));
});

test("dispatch worker uses bounded claims, leases, and provider timeouts", () => {
  assert.ok(route.includes("p_limit: 10"));
  assert.ok(route.includes("p_lease_seconds: 45"));
  assert.ok(route.includes("AbortSignal.timeout(10000)"));
});

test("dispatch worker completes commands only with their lease token", () => {
  assert.ok(route.includes("p_lease_token: command.lease_token"));
  assert.ok(route.includes("mme_pos_finish_hardware_command_delivery"));
  assert.ok(route.includes("completion_unconfirmed"));
});

test("dispatch worker exposes only safe command outcomes, not provider errors or secrets", () => {
  assert.ok(route.includes("Provider transport failed or timed out."));
  assert.ok(route.includes("TRANSPORT_ERROR"));
  assert.ok(route.includes("Cache-Control"));
  assert.ok(route.includes("process.env.SUPABASE_SERVICE_ROLE_KEY"));
  assert.ok(!route.includes("SUPABASE_SERVICE_ROLE_KEY:"));
});
const deliverySafety = await readFile(new URL("../supabase/migrations/20261105001010_build009_pos_hardware_uncertain_delivery.sql", import.meta.url), "utf8");

test("drawer transport exceptions are quarantined for reconciliation instead of retried", () => {
  assert.ok(route.includes('if (command.command_type === "open_drawer")'));
  assert.ok(route.includes("markCommandUncertain(baseUrl, serviceKey, command"));
  assert.ok(route.includes('"reconciliation_required"'));
  assert.ok(route.includes("mme_pos_mark_hardware_command_uncertain"));
});

test("an accepted drawer command whose completion write is unconfirmed is not blindly retried", () => {
  assert.ok(route.includes("!completed.ok && result.accepted && command.command_type === \"open_drawer\""));
  assert.ok(route.includes("Provider accepted the drawer command but durable completion could not be confirmed."));
});

test("expired drawer leases are terminalized and excluded from automatic re-claim", () => {
  assert.ok(deliverySafety.includes("c.dispatch_lease_until<now()"));
  assert.ok(deliverySafety.includes("delivery_uncertain=true,reconciliation_required=true"));
  assert.ok(deliverySafety.includes("and not c.reconciliation_required"));
  assert.ok(deliverySafety.includes("status='timed_out'"));
});

test("only an active lease can be marked uncertain and only drawer-open commands qualify", () => {
  assert.ok(deliverySafety.includes("v.dispatch_lease_token is distinct from p_lease_token"));
  assert.ok(deliverySafety.includes("v.command_type<>'open_drawer'"));
  assert.ok(deliverySafety.includes("grant execute on function public.mme_pos_mark_hardware_command_uncertain(uuid,uuid,text) to service_role"));
});
