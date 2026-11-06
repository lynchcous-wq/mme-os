# Build 009.55 — Recovered Inventory Pricing & Profitability Engine

## Purpose
Set defensible resale prices for recovered electronics using each asset's actual recovered cost, condition classification and recent market comparables.

## Pricing flow
Asset-level cost ledger -> active category/classification policy -> recent comparable observations -> minimum and target selling prices -> recommendation -> approval or independent override -> catalog publication outbox -> catalog transaction confirmation.

## Pricing controls
- Minimum margin and target margin are policy-controlled.
- The minimum selling price is derived from the asset's own recovered cost and minimum margin.
- Recent comparables are limited to the prior 30 days and the policy currency.
- A comparable median may cap the target price but cannot push the recommendation below the minimum floor.
- No comparable data means the target-margin price is used.
- Policy changes are versionable by creating a new policy record; do not silently rewrite prior recommendation evidence.

## Overrides and markdowns
Price overrides require a reason and independent approver. Markdown plans apply a scheduled percentage step and enforce the minimum-margin floor and maximum cumulative markdown. A price that cannot be reduced without violating the floor moves to approval-required status.

## Website publication
Publication requires a price matching an approved recommendation or approved override, an asset already posted to authoritative inventory, a condition disclosure and an idempotency key. Catalog adapter confirmation is required; this migration does not update website prices directly.

## Profitability
The asset-level profitability view exposes recovered cost, estimated resale value, estimated net recovery and estimated margin. This is recovery economics, not recognized accounting revenue or final realized profit. Actual fees, taxes, shipping, payment fees, warranty reserves and markdown effects must be incorporated by finance before management reporting.

## Security
RLS is enabled on all pricing tables. Browser roles receive no direct access. Trusted API must enforce pricing-policy permissions, CEO override permissions, independent approval, category scope and audit identity before invoking service-role functions. Service-role keys stay server-side.

## Dependencies
Build 009.54 recovery asset, cost and valuation records; authoritative inventory, catalog/website pricing, market research and finance services.

## Validation
Run `npm run lint`, `npm run test:build009:recovered-pricing`, and prior Build 009.53/009.54 suites. PostgreSQL integration tests must verify cost-floor math, comparable currency and age filtering, independent approval, markdown caps, idempotent publication and catalog reconciliation.

## Rollout boundary
Draft implementation only. No live market scraping, price publication, catalog sync, finance posting, tax/fee calculation, production migration or UI is claimed.
