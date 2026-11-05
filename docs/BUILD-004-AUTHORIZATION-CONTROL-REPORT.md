# Build 004 CEO and Global Freeze Compatibility Report

**Branch:** `integration/build004-identity-validation`  
**Status:** Read-only diagnostic implementation; CI validation pending.

## Function

`public.mme_employee_authorization_control_report()`

Service-role only. Returns a single diagnostic row with:
- Whether the legacy CEO control is provisioned.
- Whether the global employee-access freeze is active.
- Whether a freeze reason exists (without exposing the reason).
- Whether the provisioned CEO has a Build 004 person identity.
- Whether the CEO is an active legacy employee.
- Build 004 employee status, when linked.
- Whether the Build 004 whole-login security lock is active.

If the legacy singleton control row is missing, the report fails closed by reporting the freeze as active and CEO as unconfigured.

## Safety boundary

This is a read-only report, not an authorization function and not a CEO provisioning workflow. It does not grant CEO privileges, synchronize records, change global freeze, change person security state, or revoke sessions.

The legacy singleton remains the source of truth until a reviewed migration explicitly establishes equivalent Build 004 controls. Do not infer CEO authority from email, role display name, or client claims.

## Validation

pgTAP checks service-role-only execution, unconfigured CEO behavior, global freeze visibility, privacy of freeze reason, and restored fixture state. Full CI on the latest branch head is required before calling the report validated.
