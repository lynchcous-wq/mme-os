import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { getPosHardwareTransport, type HardwareCommand } from "@/lib/pos/hardware-dispatch";

export const dynamic = "force-dynamic";
export const revalidate = 0;
export const runtime = "nodejs";

function validWorkerToken(supplied: string | null): boolean {
  const expected = process.env.MME_POS_HARDWARE_WORKER_TOKEN;
  if (!expected || expected.length < 32 || !supplied) return false;
  const left = Buffer.from(expected, "utf8"); const right = Buffer.from(supplied, "utf8");
  return left.length === right.length && timingSafeEqual(left, right);
}

async function finishCommand(baseUrl: string, serviceKey: string, command: HardwareCommand, result: { accepted: boolean; providerCommandId?: string; failureCode?: string; failureDetail?: string }) {
  return fetch(baseUrl + "/rest/v1/rpc/mme_pos_finish_hardware_command_delivery", {
    method: "POST", headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      p_command_id: command.command_id, p_lease_token: command.lease_token,
      p_provider_accepted: result.accepted, p_provider_command_id: result.providerCommandId ?? null,
      p_failure_code: result.failureCode ?? null, p_failure_detail: result.failureDetail ?? null, p_retry_seconds: 30,
    }), cache: "no-store",
  });
}

async function markCommandUncertain(baseUrl: string, serviceKey: string, command: HardwareCommand, reason: string) {
  return fetch(baseUrl + "/rest/v1/rpc/mme_pos_mark_hardware_command_uncertain", {
    method: "POST", headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      p_command_id: command.command_id, p_lease_token: command.lease_token,
      p_reason: reason,
    }), cache: "no-store",
  });
}

export async function POST(request: Request) {
  if (!validWorkerToken(request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? null)) {
    return NextResponse.json({ error: "Worker authentication failed." }, { status: 401 });
  }
  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !serviceKey) return NextResponse.json({ error: "Hardware worker is not configured." }, { status: 503 });
  // Fail closed before claiming anything if no reviewed provider transport is registered in this deployment.
  const { getRegisteredPosHardwareProviders } = await import("@/lib/pos/hardware-dispatch");
  const providers = getRegisteredPosHardwareProviders();
  if (providers.length === 0) return NextResponse.json({ error: "No approved hardware transport is installed." }, { status: 503 });
  const claimResponse = await fetch(baseUrl + "/rest/v1/rpc/mme_pos_claim_hardware_commands", {
    method: "POST", headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" },
    body: JSON.stringify({ p_limit: 10, p_lease_seconds: 45 }), cache: "no-store",
  });
  if (!claimResponse.ok) return NextResponse.json({ error: "Hardware command queue is unavailable." }, { status: 502 });
  const commands = await claimResponse.json() as HardwareCommand[];
  const outcomes: Array<{ command_id: string; state: string }> = [];
  for (const command of commands) {
    const transport = getPosHardwareTransport(command.provider);
    if (!transport) {
      const completed = await finishCommand(baseUrl, serviceKey, command, { accepted: false, failureCode: "NO_APPROVED_TRANSPORT", failureDetail: "No reviewed transport is registered for this provider." });
      outcomes.push({ command_id: command.command_id, state: completed.ok ? "retry_scheduled" : "completion_unconfirmed" });
      continue;
    }
    try {
      const result = await transport.dispatch(command, AbortSignal.timeout(10000));
      if (!result || typeof result.accepted !== "boolean" || (result.providerCommandId && result.providerCommandId.length > 160)) throw new Error("INVALID_PROVIDER_RESPONSE");
      const completed = await finishCommand(baseUrl, serviceKey, command, { accepted: result.accepted, providerCommandId: result.providerCommandId, failureCode: result.accepted ? undefined : "PROVIDER_REJECTED", failureDetail: result.accepted ? undefined : "Provider did not accept the command." });
      if (!completed.ok && result.accepted && command.command_type === "open_drawer") {
        const held = await markCommandUncertain(baseUrl, serviceKey, command, "Provider accepted the drawer command but durable completion could not be confirmed.");
        outcomes.push({ command_id: command.command_id, state: held.ok ? "reconciliation_required" : "completion_unconfirmed" });
      } else {
        outcomes.push({ command_id: command.command_id, state: completed.ok ? (result.accepted ? "acknowledged" : "retry_scheduled") : "completion_unconfirmed" });
      }
    } catch (error) {
      const code = error instanceof Error && /^[A-Z0-9_]{1,80}$/.test(error.message) ? error.message : "TRANSPORT_ERROR";
      if (command.command_type === "open_drawer") {
        const held = await markCommandUncertain(baseUrl, serviceKey, command, "Drawer command delivery outcome is unknown after transport failure: " + code);
        outcomes.push({ command_id: command.command_id, state: held.ok ? "reconciliation_required" : "completion_unconfirmed" });
      } else {
        const completed = await finishCommand(baseUrl, serviceKey, command, { accepted: false, failureCode: code, failureDetail: "Provider transport failed or timed out." });
        outcomes.push({ command_id: command.command_id, state: completed.ok ? "retry_scheduled" : "completion_unconfirmed" });
      }
    }
  }
  return NextResponse.json({ processed: outcomes.length, outcomes }, { status: 200, headers: { "Cache-Control": "no-store" } });
}