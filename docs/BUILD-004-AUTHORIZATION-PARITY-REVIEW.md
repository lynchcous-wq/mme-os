# Build 004 — Legacy and person-keyed authorization parity review

**Status:** Static contract review; parity is not established  
**Branch:** `work/build008-build001-catalog-routes`  
**Execution boundary:** No live identity rows queried, no backfill, no permission writes, no cutover

## Verified source contracts

### Legacy catalog authorization

Migration: `20261103000003_catalog_integration_employee_authorization_engine.sql`

- Actor key: Auth user UUID (`p_actor_user_id`).
- Employee lookup: `employee_relationships.user_id`.
- Grant lookup: `employee_permission_grants.employee_user_id`.
- CEO override: `employee_security_settings.ceo_user_id`.
- Company freeze and active employment are required.
- Self-approval prevention depends on caller-supplied `p_submitter_user_id`; the function does not derive the submitter from the protected product row.
- Grant scope supports global or product scope.

### Person-keyed catalog and inventory authorization

Migrations: `20261103008430_build004_person_keyed_authorization.sql` and `20261103008440_build004_require_active_person_identity.sql`

- Actor key: MME person UUID.
- Requires `mme_person_identities.lifecycle_status = 'active'`.
- Employee lookup: `employee_relationships.person_id`.
- Grant lookup: `employee_permission_grants.person_id`.
- CEO override: `employee_security_settings.ceo_person_id`.
- Company freeze and active employment are required.
- Catalog approval derives the submitter from `products.created_by` through the verified Auth-subject resolver; caller-supplied submitter identity is not trusted.
- Catalog and inventory grant scopes support product/location conditions as implemented by their respective functions.
- Functions are service-role only and do not fall back to Auth UUID authorization.

## Known semantic differences — parity blockers

| Area | Legacy | Person-keyed | Required disposition |
|---|---|---|---|
| Identity lifecycle | No person lifecycle check | Requires active person | Preserve stricter person check; explicitly classify as intended deny |
| Self-approval | Caller-supplied submitter UUID | Protected product creator resolved to person | Update legacy caller path or compare using the protected creator mapping |
| CEO identity | `ceo_user_id` | `ceo_person_id` | Verify both resolve to the same approved human; never infer from UUID equality |
| Employee link | `user_id` | `person_id` | Require verified one-to-one subject/person/employee relationship |
| Permission grants | `employee_user_id` | `person_id` | Verify grant attribution and preserve revocation/expiry/scope |
| Inventory authorization | No matching legacy decision function located in the current migration set | Person-keyed inspection decision function exists | Do not claim inventory parity; identify the actual current inventory enforcement path first |

## Required parity fixture matrix

Use synthetic identities only in an isolated disposable database. For every case, record legacy decision, person decision, expected disposition, and reason:

1. Active employee, valid global grant.
2. Active employee, product-scoped grant matching and not matching target.
3. Active employee, expired grant.
4. Active employee, revoked grant.
5. Suspended, terminated, locked, merged, archived, and missing person identity.
6. Missing or inactive employee relationship.
7. Company-wide access freeze on and off.
8. Missing CEO configuration.
9. CEO actor with active and inactive employee relationship.
10. Catalog creator attempting own approval and publication.
11. Different approver with pending, already-approved, rejected, and missing product.
12. Missing, ambiguous, revoked, or inactive Auth-subject mapping.
13. Duplicate employee links, duplicate subject mappings, and cross-person grant collisions.
14. Product and location scoped inventory permissions, including no-scope and wrong-scope cases.

## Acceptance rules

- Compare only synthetic fixture identities; never enumerate real user identity rows for this test.
- A mismatch is a reported result, not an automatic reconciliation or permission grant.
- Denials caused by stronger lifecycle requirements must be explicitly approved as intended policy changes.
- Legacy self-approval must not be considered equivalent until it derives the submitter from the protected product record or the caller is demonstrably trusted and validated.
- No inventory parity claim until the legacy inventory authorization mechanism has been identified.
- Any unresolved mapping, duplicate, ambiguous CEO assignment, or missing permission attribution blocks cutover.
- Shadow comparison is read-only and cannot mutate grants, identity links, sessions, or employee records.

## Current disposition

**Parity status: NOT ESTABLISHED.** The person-keyed implementation is an additive parallel authorization path, not a drop-in equivalent. The source contracts expose meaningful differences that must be resolved with policy approval and isolated synthetic integration tests before shadow comparison or cutover.

No production merge, deployment, identity backfill, or authorization cutover has been performed.
