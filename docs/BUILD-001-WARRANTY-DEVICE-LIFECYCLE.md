# Build 001 — Warranty Management & Device Lifecycle Intelligence

**Status:** Proposed additive migration; not applied.

## Coverage and registration
Maintain product-level manufacturer, supplier, MME-limited and extended warranty policies. Register coverage against an individual serialized device with provider, contract reference, start/end dates, exclusions and immutable coverage-term snapshots. Policy registration validates product match and maximum coverage duration.

## Claims
Open repair, replacement, refund-review or diagnostic claims with evidence. Claims must be within the registered coverage window. When an order is supplied, the order must contain that exact serialized device. A separate reviewer must decide; the requester cannot review their own claim. Record authorized cost and reason.

## Repair and service history
Record diagnostics, repairs, replacement parts, firmware, cleaning and quality checks against the serialized device. A claim-linked service record requires an authorized claim for that same device. Successful service closes the claim. Link inspection evidence to the existing inventory inspection workflow.

## Lifecycle and sellability
Warranty status and claim status do not themselves make a device sellable. A device undergoing service or repair must continue through the existing inspection and serialized disposition workflow. Only inspection resolution can return a device to stock with a saleable condition grade. Warranty expiry is queryable from end dates; a scheduled backend job may mark expired policies without changing inventory.

## Security
All tables and functions are service-role only. Backend must authenticate employee identity, role, location scope, claim authority and cost limits; UUIDs supplied as audit attribution are not proof of identity. Provider/manufacturer integrations and automated claim submission are not implemented by this schema.

## Verification
Run disposable database integration tests for product-policy mismatch, coverage expiry, wrong-device order linkage, requester self-review, claim state transitions, service against a different device, unauthorized repair and inspection-gated return-to-stock.