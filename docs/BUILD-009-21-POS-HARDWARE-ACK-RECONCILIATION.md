# Build 009.21 — POS Hardware Acknowledgment & State Reconciliation Engine

Status: implementation changes committed to a review branch; migration application and runtime validation pending.

## Reused foundation
- Build 009.15 device registry and hardware event ledger.
- Build 009.18 provider adapter and signed webhook verification.
- Build 009.19 command delivery queue, provider command identifier, and bounded worker leases.
- Build 009.20 uncertain cash-drawer delivery quarantine.

## Implementation
1. Provider event normalization accepts an optional bounded `provider_command_id`; it never trusts a provider-supplied internal MME command UUID.
2. The signed webhook continues to verify the exact raw request bytes before parsing and device lookup.
3. Drawer-open confirmation/failure events are additionally written to `mme_pos_hardware_acknowledgments`, keyed idempotently by registered device and provider event ID.
4. Exact provider command correlation is restricted to the same registered device. Multiple matching commands are treated as a conflict; the engine never picks the newest command arbitrarily.
5. A matching device confirmation can transition an uncertain `open_drawer` command from `timed_out` to `confirmed`, clearing its reconciliation hold. A matching device failure transitions it to `failed`.
6. A conflicting late event does not overwrite an already terminal command. Events without a provider command identifier are retained as unmatched; the engine does not guess which drawer command they refer to.
7. `mme_pos_reconcile_hardware_acknowledgments` provides bounded, per-device replay of unmatched events when a provider command identifier was supplied and the matching command becomes available. Events that arrive without a provider command identifier remain unmatched for an authorized manual investigation; the engine does not infer a command.

## Security and integrity
- RLS enabled; acknowledgment table access and reconciliation RPCs are service-role only.
- Provider identity comes from the verified adapter webhook route and registered device mapping.
- Provider event IDs are unique per device; duplicate delivery does not repeat command state transitions.
- Provider command IDs are scoped to the registered device; ambiguity becomes a conflict.
- Raw payment credentials and cardholder data are not part of this acknowledgment payload.
- A provider event is evidence from the registered device integration, not proof of employee misconduct.

## Validation
Run:
- `npm run test:build009:hardware-webhook`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run test:build009:hardware-dispatch`
- `npm run test:build009:hardware-command-delivery`
- `npm run lint`
- Full migration replay and PostgreSQL integration tests in an isolated Supabase environment.

Test normal confirmation, explicit drawer failure, duplicate webhook, provider event ID reuse with conflicting data, missing provider command ID, unknown command ID, wrong-device command ID, multiple matching commands, late acknowledgment after Build 009.20 uncertain delivery, and conflicting acknowledgment after a terminal command.

## Not claimed complete
The migration has not been applied to the connected Supabase project. No hardware provider has been certified or physically tested. CI results and end-to-end device acknowledgment behavior must be reviewed before production activation.
