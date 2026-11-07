# Master Build 011.02 — Vendor Master Reconciliation

Status: **repository-level reconciliation design committed; live database decision pending**.
Branch: `implementation/build-011-purchasing-receiving-integration`.
Date: 2026-11-07.

## Objective

Preserve the useful vendor capabilities in implementation streams 009.57, 010.41 and 010.70 while establishing one canonical vendor identity for MME OS. Do not create a fourth vendor master. Do not drop, rename or migrate any existing production vendor table until the read-only Supabase audit identifies the actual live schema and data.

## Source inventory

| Source stream | Vendor structure | Strengths | Gaps / conflicts |
|---|---|---|---|
| 009.57 | `mme_procurement_vendors` | Legal/display names, vendor code, pending/approved/suspended/inactive status, default currency, lead time, minimum order value, reliability score; referenced by procurement quotes, requests, PO drafts and performance | No dedicated contact table in this migration; actor columns use generic UUID fields; separate from finance and vendor-management structures |
| 010.41 | `mme_vendors` + `mme_vendor_contacts` | Vendor code/name/status, website, phone, email, payment terms, account reference, notes, multiple contacts; used by PO and invoice records | Simpler vendor lifecycle; no explicit default currency/lead time/approval evidence model; PO receiving function directly posts inventory |
| 010.70 | `mme_financial_vendors` reference | Connects supplier catalog items to a financial vendor identity | The referenced table definition is not in this migration; actual schema, ownership and lifecycle are not proven here |
| 010.70 | `mme_vendor_catalog_items` + offers | Supplier SKU, manufacturer part number, product URL, mapped inventory item, offer cost/currency/MOQ/availability/lead time/validity/source | Catalog is coupled to 010.70's financial-vendor and inventory-item schema family |
| 010.71 | price observations / landed-cost scenarios | Historical cost observations and scenario components | Extends 010.70; manual evidence only; not a vendor identity source |

## Recommended logical target

The canonical vendor master should be the single enterprise identity record for a supplier. It should support:

- Stable vendor ID and unique vendor code.
- Legal name and display/trading name.
- Lifecycle status: pending, approved, suspended, inactive.
- Tax/business registration references with restricted access and masking.
- Default currency and supported currencies.
- Payment terms reference (not payment credentials).
- Default lead time and minimum order value.
- Website and general contact details.
- Risk/compliance status and review dates.
- Created/updated actor and timestamp, with append-only change history.

Related records should remain separate, keyed to the canonical vendor ID:

1. Vendor contacts — one-to-many named contacts and contact purposes.
2. Vendor locations/remit-to addresses — controlled address records; no bank account data in the general vendor profile.
3. Vendor documents/compliance — expiring certificates, contracts, W-9/tax documentation and verification status with private storage.
4. Vendor product catalog — supplier SKU and manufacturer identifiers mapped to one canonical MME product.
5. Vendor offers/quotes — price, currency, MOQ, availability, lead time, validity and evidence.
6. Procurement performance — delivery, accepted quantity, quality and service metrics with source evidence.
7. Purchase orders, receipts and invoices — separate transactional entities linked to vendor ID.
8. Vendor audit events — actor, action, reason, before/after references, timestamp and correlation ID.

## Conditional canonical-source selection

The repository alone cannot safely decide which vendor table is already authoritative in production. Apply this decision only after the live read-only audit:

- **If a live enterprise/financial vendor master is already the approved source used by AP or accounting:** retain it as the canonical vendor identity if it has stable IDs, lifecycle governance, uniqueness, RLS and adequate audit history. Extend it additively for procurement fields; map 009.57 and 010.41 references to it.
- **If no suitable enterprise/financial vendor master exists, but 009.57's procurement vendor schema is already live and used:** retain 009.57 as the canonical base and add contact/compliance/finance references as related entities.
- **If 010.41's `mme_vendors` is the only live vendor source:** do not create a replacement. Extend it additively after adding explicit lifecycle approval, currency, lead-time, risk and audit controls.
- **If multiple candidate tables contain production records:** freeze new vendor creation across competing paths; profile duplicate and orphan references read-only; propose a deterministic crosswalk and human-reviewed merge plan. Never merge supplier identities based only on similar names.

No table is selected as canonical by this document. This conditional rule avoids choosing an attractive branch schema that may not match live data.

## Field mapping requirements

| Logical attribute | 009.57 source | 010.41 source | Target treatment |
|---|---|---|---|
| Stable identity | `vendor_id` | `vendor_id` | Preserve existing canonical ID; crosswalk other IDs |
| Vendor code | `vendor_code` | `vendor_code` | Unique, collision-reviewed code |
| Legal name | `legal_name` | Not explicit | Add or map; do not infer from display name without review |
| Display name | `display_name` | `vendor_name` | Map as display/trading name |
| Status | pending/approved/suspended/inactive | active/on_hold/inactive | Explicit reviewed state mapping; never auto-approve |
| Currency | `default_currency` | `currency` on PO only | Vendor default is a profile preference; PO currency remains transaction-specific |
| Lead time | `default_lead_time_days` | Not explicit | Additive optional field |
| Minimum order value | `minimum_order_value` | Not explicit | Additive optional field |
| Reliability | `reliability_score` | Not explicit | Preserve as sourced metric; don't treat as verified risk rating |
| Contacts | Not in vendor migration | `mme_vendor_contacts` | Separate one-to-many contacts |
| Terms | `payment_terms` | `payment_terms` | Normalize only after format and semantics review |
| Account reference | Not explicit | `account_reference` | Restrict access; do not store bank credentials |
| Audit actor | `created_by` | `created_by_auth_user_id` | Resolve actor from trusted server identity; preserve original attribution where valid |

## Vendor catalog mapping

- Supplier SKU is not an MME SKU and must not create a new canonical product automatically.
- Map supplier catalog items to the canonical product identifier after matching by manufacturer part number, model, brand and verified attributes.
- Keep unmatched items in a review queue.
- Keep multiple supplier offers for one canonical product.
- Preserve quote/offer currency, source, verification timestamp, validity, MOQ and lead time.
- An unverified/manual offer must be visibly marked as unverified.
- Price observations must be append-only history; never overwrite prior observations.
- Landed-cost scenarios must preserve their component inputs and currency. Do not silently combine unlike currencies or apply unapproved accounting capitalization rules.

## Security and governance requirements

- Vendor master write access must be server-authorized through the canonical MME employee/person identity and permission model.
- Separate vendor create/edit, approve/suspend, banking/AP access, quote entry, PO approval and invoice approval duties.
- Request payload actor IDs must never establish actor identity.
- Vendor tax documents and sensitive account references must be private and masked in ordinary UI/API responses.
- RLS, table grants, storage policies and security-definer functions must be tested against real roles.
- Audit records must be append-only and include a reason for approval, suspension, reactivation and identity merge.
- A vendor cannot approve its own onboarding or approve its own purchase request.

## Migration / data-reconciliation plan (not yet authorized)

1. Export read-only schema, migration history, table counts and key uniqueness/orphan metrics for all vendor-related entities.
2. Determine which table is actively referenced by AP, PO, invoice, catalog, purchasing and finance code in the deployed application.
3. Produce a vendor-ID crosswalk table proposal, including duplicate candidates and unresolved collisions. Do not merge automatically.
4. Review status mapping with procurement/finance. Existing active records must not become approved merely because a prior schema used the word active.
5. Map contacts, terms, currency and catalog references to the canonical vendor.
6. Add constraints and foreign keys only after orphan and duplicate analysis.
7. Update server APIs and UI to read/write through one canonical service boundary.
8. Keep compatibility views/adapters only when needed for a controlled transition; do not keep multiple writable vendor masters.
9. Test migration replay, rollback, RLS, permission boundaries, audit, duplicate prevention and API regression on a disposable database.
10. Obtain review approval before any production migration.

## Acceptance checklist

- [x] Repository SQL for 009.57, 010.41, 010.70 and 010.71 inspected.
- [x] Competing vendor structures and field differences documented.
- [x] One logical vendor master target defined.
- [x] Conditional canonical-source rule defined without guessing live state.
- [x] Supplier SKU/product mapping boundary documented.
- [x] Security and migration safeguards specified.
- [ ] Live Supabase schema and migration history verified.
- [ ] Canonical source selected against live dependencies.
- [ ] Vendor-ID crosswalk and duplicate report reviewed.
- [ ] Additive migration and API implementation completed.
- [ ] Database, security and integration tests passed.

## Completion status

Build 011.02's repository reconciliation design is documented. The vendor master is **not yet implemented or selected in production**. The next work gate is live Supabase evidence, followed by a reviewed ID crosswalk. No database mutation, migration application, merge or deployment is performed by this document.
