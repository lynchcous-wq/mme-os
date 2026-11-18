# Build 011.27 — Financing Provider Partnerships & Integration Readiness

## Objective
Establish an internal provider directory and onboarding control plane across private-label credit, installment lending, BNPL and lease-to-own models.

## Providers in the research register
Synchrony; Bread Pay / Bread Financial; Citi Retail Services; Affirm; Klarna; PayPal Pay Later; Acima; Snap Finance.

## Deliverables
- Internal employee-gated provider register: `/employee/financing/providers`.
- Employee-authenticated read API: `GET /api/financing/providers`.
- Provider catalog with merchant partnership URLs, product types, underwriting ownership, merchant onboarding requirements, fee model and integration options.
- Private Supabase table `mme_financing_provider_programs` tracking application status, merchant ID, approved products, agreement reference, verified terms, settlement reference and integration mode.
- Seeded providers default to `research`; existing records are preserved using `ON CONFLICT DO NOTHING`.

## Commercial controls
- Provider fees are quote- and contract-dependent unless the provider publishes a current standard schedule; no estimate is represented as MME's quote.
- Consumer underwriting, approval, APR, terms and adverse-action responsibilities remain with the lender/provider.
- Merchant partnership URLs are not consumer application URLs.
- No customer-facing provider application URL becomes available until written merchant approval, approved product/category scope, integration certification and disclosure review are recorded.
- Confirm eligibility of used/refurbished electronics, serial/IMEI-tracked devices, warranties, returns, local pickup and shipped orders.

## Security
- API requires authenticated user plus active MME employee identity.
- Provider registry table has RLS enabled and all direct browser-role privileges revoked.
- Service-role access is server-side only.
- No consumer SSN, DOB, bank details, credit score, identity documents, provider credentials or API secrets are stored in this registry.
- No production activation is permitted from this research screen.

## Acceptance tests / release gates
- [x] Eight provider categories represented in the catalog.
- [x] Employee-only server API gate implemented.
- [x] Private provider status schema and safe idempotent seed.
- [x] No customer credit application links exposed.
- [ ] Apply migration to preview Supabase.
- [ ] Verify employee access succeeds and customer/non-employee access is denied.
- [ ] Verify all eight providers load from the authenticated API.
- [ ] Verify current commercial terms and public eligibility directly with each provider.
- [ ] Obtain written merchant approval and signed terms before marking any provider active.
- [ ] Implement provider-specific adapters only against approved documentation and sandbox credentials.
- [ ] Test application handoff, webhook signature verification, settlement, refund, dispute and reconciliation.
- [ ] Complete legal/compliance and privacy review.
- [ ] Explicit production release approval.

## Release decision
**INTERNAL RESEARCH / PREVIEW ONLY.** No lender is represented as approved or active. No consumer credit application, credit pull, approval, offer, funding or payment is performed. Production database and environment are unchanged.
