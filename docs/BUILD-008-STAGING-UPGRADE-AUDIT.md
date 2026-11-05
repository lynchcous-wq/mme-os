# Build 008 — Build 001 Staging Upgrade and Authorization Boundary Audit

**Branch:** `work/build008-build001-catalog-routes`  
**Baseline:** `build-008-inventory-foundation`  
**Review type:** Repository/schema-contract audit; no staging or production database connection  
**Disposition:** Fresh-database CI is green. Existing-database upgrade and authorization cutover remain blocked.

## 1. Verification evidence

The latest branch commit has successful GitHub Actions runs for:
- Build 008 catalog route contract tests.
- Build 001 migration validation: local Supabase startup, complete migration application to a clean database, and `supabase db lint --local`.

These results demonstrate that the checked-in migration chain can initialize a clean local Supabase database and that the route contract workflow passes. They do not prove compatibility with an existing staging/production schema, existing data, previously applied migration history, or external identity configuration.

## 2. Existing Build 008 baseline limitation

The inspected `build-008-inventory-foundation` baseline contains no `supabase/` directory and no SQL migration files. Consequently, this repository baseline does not provide an existing Build 008 database migration chain or schema snapshot against which an in-place upgrade can be rehearsed.

The fresh-database workflow currently validates the imported Build 001 chain from zero. It must not be described as a staging upgrade test.

**Required input before staging rehearsal:** a sanitized staging schema-only dump, the staging `supabase_migrations.schema_migrations` history, and the exact Build 008/Build 004 migration revision already applied to staging. Do not place database credentials, service-role keys, customer data, serials, IMEIs, or inspection evidence in GitHub artifacts.

## 3. Build 004 identity conflict — merge blocker

The imported catalog employee access migrations create:
- `employee_relationships.user_id` as the primary key and direct FK to `auth.users(id)`;
- `employee_permission_grants.employee_user_id` keyed to that Auth UUID;
- `employee_security_settings.ceo_user_id` keyed to `auth.users(id)`;
- catalog and inventory authorization functions that accept an Auth UUID as the actor.

The Build 004 Identity Matrix specification explicitly separates `PersonIdentity` from `LoginIdentity` and the external identity-provider subject. It requires a stable MME person identity, with employee and customer relationships independently governed. The current imported authorization schema therefore encodes the legacy Auth-subject-as-employee-identity assumption and is not the approved final Build 004 identity contract.

**Decision:** do not merge or deploy these employee authorization migrations as the final Build 004 integration. Before release, map catalog/inventory actor and approver references to the approved Build 004 person identity, preserve the distinct Auth-subject mapping, and prove dual-authorization parity and revocation behavior. CEO provisioning must remain fail-closed and out-of-band.

## 4. Catalog and stock contract blockers

### 4.1 Serialized unit availability response

The integration contract document says customer-facing serialized availability is aggregate-only. The current units route returns `unit_id`, `location_id`, `location_name`, and `condition_grade` rows to the caller, while cart validation accepts an exact serialized unit UUID. This is a real consumer-contract conflict, not a test-only issue.

Do not silently remove the unit reference and break cart selection. Before public release, choose and test one of:
1. aggregate-only public availability plus a server-issued short-lived opaque selection token; or
2. a deliberately approved opaque unit-reference contract with no UUID rendering, rate limits, short TTL, strict cart revalidation and documented threat acceptance.

Neither option may expose serial/IMEI or private inventory evidence. Exact serialized selection must be revalidated atomically at reservation/checkout; a read-only availability check is not a reservation.

### 4.2 Inspection/disposition eligibility

The units route filters on `unit_status=in_stock` but does not query the inspection/disposition ledger or a single canonical sellable-eligibility projection. The route and cart validator must be proven equivalent to inspection holds, pending inspection, quarantine, repair, disposition and movement state before serialized checkout is enabled.

### 4.3 Cross-channel claims and aggregate balances

The cart validator computes aggregate availability from `on_hand_quantity - reserved_quantity`. It does not independently reconcile every active cross-channel claim. The database contract must prove claims are reflected exactly once in the reserved balance/projection, with no duplicate reservation or stale-claim overstatement. Do not add a second subtraction in the route until the owning RPC/view contract is verified.

## 5. Staging upgrade rehearsal gate

After a sanitized schema-only snapshot and migration history are supplied:
1. Restore the snapshot to an isolated, disposable staging clone.
2. Verify migration history and checksums before applying anything.
3. Run a preflight diff for existing tables, columns, enum/check constraints, indexes, triggers, RLS policies, functions, grants, storage buckets and extensions.
4. Apply only the reviewed pending migrations in order.
5. Run Supabase database lint, all pgTAP suites, catalog route tests and authorization tests.
6. Verify rollback/forward-repair procedures, row counts, foreign-key integrity, RLS behavior and service-role-only RPC grants.
7. Record the resulting schema diff and test artifacts; require owner approval before any merge or deployment.

No staging database was accessed or changed during this audit.

## 6. Release decision

| Gate | Status |
|---|---|
| Fresh local migration chain | Passed |
| Local Supabase database lint | Passed |
| Catalog route contract CI | Passed |
| Existing Build 008 migration history available in baseline | No |
| Staging schema snapshot/history available | No |
| Build 004 canonical person-identity integration | Blocked |
| Public serialized unit response contract | Needs decision |
| Inspection/disposition sellable eligibility | Needs database-backed proof |
| Cross-channel claim/reserved-balance parity | Needs database-backed proof |
| Staging upgrade rehearsal | Not run |
| Production migration, merge or deployment | Not performed |

**Final audit position:** continue in the isolated branch. The clean-database pass is useful, but it does not authorize a staging/production upgrade. The Build 004 identity mismatch and serialized stock eligibility/response conflicts must be resolved before release.
