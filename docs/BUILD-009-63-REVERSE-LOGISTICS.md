# Build 009.63 — Returns, Exchanges & Reverse Logistics

## Existing foundations reused
Build 009.53 customer return cases, inspections, evidence, condition grades, refund decisions and exchanges remain the case-management source of truth. Build 009.40 serialized return/warranty lifecycle and Build 009.59 inventory ledger remain authoritative for serialized cost and aggregate inventory. This build adds a governed disposition-to-ledger bridge; it does not replace those systems.

## Disposition workflow
Receive and inspect the item, request a disposition, obtain independent approval, then post a controlled outcome. Direct sellable restock requires grade A/B, passed inspection, serial match, clear or not-applicable activation lock and verified item identity. Only new/open-box disposition can increase sellable on-hand inventory.

## Non-sellable routes
Quarantine, refurbishment and parts recovery create a separate quarantine record and do not increase sellable on-hand quantity. Vendor return remains pending supplier workflow. Secure disposal records a disposal state and requires external certificate/evidence retention. These routes must never silently enter available-to-promise stock.

## Inventory accounting
Approved direct restock posts one positive return movement to the immutable Build 009.59 inventory ledger, updates balance quantity/value and creates a cost layer at current weighted-average carrying cost. A transaction lock serializes SKU/location/currency postings. Posting is idempotent; ledger entry is linked to the return item disposition. Finance must validate valuation policy before production enablement.

## Separation of duties
Disposition requester cannot approve their own request. Refund decisions and provider refund dispatch remain separate workflows; inventory disposition does not authorize, issue or confirm a refund. Existing independent refund approval and refund reconciliation remain authoritative.

## Security and evidence
RLS enabled on all new tables; browser roles have no direct access. Mutations are service-role RPC only behind an authenticated, role/location-scoped API. Preserve original inspection/evidence references and immutable event history. Do not store raw payment credentials or unnecessary device secrets.

## Validation
Run npm run lint, npm run test:build009:reverse-logistics, and existing returns-management, serialized-returns-warranty, serialized-return-refunds, inventory-ledger and fulfillment suites. PostgreSQL integration tests must cover duplicate posting, concurrent restock, mismatched serial/IMEI, activation lock, quarantine isolation, approval separation and refund independence.

## Rollout boundary
Draft implementation only. No live POS/customer portal screens, carrier/vendor return integration, disposal certificate provider, refund provider changes, production migration replay or deployment is claimed.
