# Build 009.20 — POS Hardware Dispatch Worker

Status: implementation changes committed to a review branch; database migration and runtime validation pending.

## Existing foundation reused
- `app/api/internal/pos/hardware/dispatch/route.ts`: authenticated server-side worker.
- `lib/pos/hardware-dispatch.ts`: reviewed in-code provider transport registry.
- `mme_pos_claim_hardware_commands` and `mme_pos_finish_hardware_command_delivery`: bounded, leased, service-role-only queue operations.
- Existing device registry, provider pairing, heartbeat supervision, webhook ingestion and IT incident workflow.

## Safety correction in this implementation
Cash-drawer `open_drawer` commands are not automatically retried after an ambiguous transport outcome. A timeout, thrown transport error, or provider acceptance whose durable completion cannot be confirmed is marked `timed_out` with `delivery_uncertain=true` and `reconciliation_required=true`. Expired drawer-open leases are terminalized before the queue claims more work. The claim function excludes commands awaiting reconciliation.

The new RPC `mme_pos_mark_hardware_command_uncertain` requires the current lease token and permits only `open_drawer` commands. It is service-role only. A drawer command in this state requires device-state reconciliation and an authorized human resolution; a new open command must not be generated merely to clear the alert.

Other command types retain bounded retry behavior. Queue claims remain bounded to 1–50 commands and 10–300 second leases. Provider calls remain time-limited. Worker authentication uses a server-only token and constant-time comparison. Service-role credentials remain server-only.

## Provider transport boundary
The worker deliberately fails closed when no reviewed provider transport is registered. A concrete provider adapter must be implemented and reviewed against the actual device model, vendor protocol, authentication, idempotency semantics, and physical test environment before it can send commands. No generic URL from a database row is executed and no physical device is assumed connected.

## Required environment
- `MME_POS_HARDWARE_WORKER_TOKEN` — high-entropy server-only worker token (at least 32 characters).
- `SUPABASE_URL` (or server-side `NEXT_PUBLIC_SUPABASE_URL`) and `SUPABASE_SERVICE_ROLE_KEY` — server-side only.
- A reviewed provider transport registered in code for the target provider.

## Validation gates
1. Apply migrations in order, including `20261105001010_build009_pos_hardware_uncertain_delivery.sql`.
2. Run `npm run test:build009:hardware-dispatch`, the hardware command-delivery, hardware provider, webhook, and hardware monitoring suites.
3. Run TypeScript and full application build.
4. Test normal acceptance, explicit provider rejection, transport timeout, process interruption/expired lease, stale lease token, duplicate command idempotency, and DB completion response loss.
5. Physically verify a supported device in a non-production environment. Never enable drawer commands in production based solely on mocked tests.
6. Verify IT incident and device-state reconciliation workflows before authorizing any follow-up drawer command.

## Not claimed complete
No migration has been applied to the connected Supabase project, no provider adapter has been registered, no physical hardware has been tested, and no production deployment has been made by this branch change.
