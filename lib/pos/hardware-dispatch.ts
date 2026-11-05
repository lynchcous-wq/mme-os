import type { PosHardwareEventType } from "./hardware-provider";

export type HardwareCommand = {
  command_id: string; device_id: string; provider: string; device_reference: string;
  command_type: "open_drawer" | "status_check"; idempotency_key: string;
  lease_token: string; attempt_count: number;
};

export type HardwareDispatchResult = { accepted: boolean; providerCommandId?: string };
export type PosHardwareTransport = {
  dispatch(command: HardwareCommand, signal: AbortSignal): Promise<HardwareDispatchResult>;
};

const transports = new Map<string, PosHardwareTransport>();
const PROVIDER_CODE = /^[a-z0-9][a-z0-9_-]{0,79}$/;

/** Register only an in-code, reviewed provider transport. Arbitrary database URLs are never executed. */
export function registerPosHardwareTransport(providerCode: string, transport: PosHardwareTransport): void {
  if (!PROVIDER_CODE.test(providerCode)) throw new Error("Invalid provider code.");
  if (transports.has(providerCode)) throw new Error("A transport is already registered for this provider.");
  transports.set(providerCode, transport);
}

export function getPosHardwareTransport(providerCode: string): PosHardwareTransport | null {
  return transports.get(providerCode) ?? null;
}

export function getRegisteredPosHardwareProviders(): string[] { return [...transports.keys()].sort(); }