# Build 004 Read-Only Employee Identity Reconciliation

**Branch:** `integration/build004-identity-validation`  
**Status:** Implemented as a server-only diagnostic SQL function and pgTAP coverage; CI validation pending.  
**Safety:** Read-only report. No employee relationship, role, grant, CEO setting, freeze, or identity is created, changed, migrated, or revoked.

## Function

`public.mme_employee_identity_reconciliation_report()`

- Service-role execution only; browser roles cannot execute it.
- Uses a fixed search path and a stable SQL function.
- Returns issue key, severity, opaque Auth user ID where applicable, person identity ID where applicable, and limited technical metadata.
- Does not return email addresses, names, phone numbers, or customer profile data.
- Does not make authorization decisions and must not be used as a replacement for the existing legacy authorization checks.

## Findings

| Finding | Meaning |
|---|---|
| `missing_person_identity` | Legacy employee has no Build 004 person identity |
| `missing_build004_employee` | Person identity exists but no Build 004 employee relationship |
| `employee_status_mismatch` | Legacy and Build 004 employment states do not match the approved transitional mapping |
| `whole_login_locked` | Person-level login lock is active |
| `legacy_permissions_need_migration_review` | Active legacy grants exist without an active Build 004 role assignment |
| `build004_employee_without_legacy_link` | Build 004 employee has no legacy employee relationship |
| `legacy_employee_access_frozen` | Existing global employee-access freeze is active |
| `provisioned_ceo_identity_missing` | Legacy CEO user is configured but has no Build 004 identity |

The report intentionally does not infer that grants should be copied, that a CEO role should be created, or that status differences should be automatically repaired. The existing permission crosswalk and scope/CEO/freeze blockers remain in force.

## Validation

The pgTAP test seeds isolated fixture users inside a transaction, checks function existence and execution privileges, verifies representative findings, confirms the global freeze is reported, and rolls back all fixture changes. The complete migration chain and test suite must pass in GitHub Actions before this dependency is considered validated.

## Next gate

Review the findings against the live development dataset using a controlled service-role execution path, then produce a dry-run grant mapping and old/new authorization equivalence fixtures. No production permission changes or route cutover are authorized by this work.
