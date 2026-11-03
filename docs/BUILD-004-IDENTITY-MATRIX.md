# Build 004 — Identity Matrix & Optional Role-Based Color Architecture

**Platform:** Much More Electronics Operating System (MME OS)  
**Status:** Updated specification for implementation review; no production implementation claim  
**Dependencies:** Builds 001, 002, and 003  
**Authority:** CEO retains ultimate identity and access governance, with privileged actions authenticated, scoped, and audited.  
**Repository:** `lynchcous-wq/mme-os`

## 1. Purpose and design principles

Build 004 specifies a centralized identity, employment/customer relationship, organizational role, permission, integration entitlement, lifecycle, and optional visual preference model. These are related but distinct records and policy domains.

1. A unique person/login identity is not the same thing as an employee record, customer account, role, permission, or profile preference.
2. A role assignment is not itself unrestricted access: each action is authorized by explicit, scoped grants and policy.
3. Appearance is never an authorization signal. Neither role color nor profile preference can grant, deny, or imply permission.
4. Employment lifecycle changes must not silently change a separate customer relationship.
5. Deny by default; grant least privilege; enforce authorization on the server for every protected action and data access.
6. CEO-controlled changes are attributable and auditable. No employee or AI process may silently override CEO-governed settings.
7. Migrate additively and preserve verified existing authentication. Do not replace an identity provider without an approved migration and rollback plan.

## 2. Current repository boundary

The existing repository is a Next.js storefront shell with placeholder product and account routes. The previously inspected `package.json` contains Next.js, React, and TypeScript; no authentication provider, employee records, customer identity service, role matrix, permission store, role-color registry, or preference persistence was present in the inspected files. This specification does not implement these capabilities or establish that a provider/integration exists. Before implementation, re-inspect the current project and any Replit configuration, data stores, secrets, and identity-provider settings; the repository alone cannot prove what exists outside version control.

## 3. Identity and relationship model

### 3.1 Conceptual entities

| Entity | Purpose | Authority / boundary |
|---|---|---|
| `PersonIdentity` | Stable, opaque person identifier and identity lifecycle | Central IAM; do not use email as the permanent primary key |
| `LoginIdentity` | Authentication subject, verified email/username and identity-provider reference | IAM/approved identity provider; secrets/credential material remain with provider or secure auth service |
| `CustomerRelationship` | Customer-specific account status, preferences and customer permissions | Customer Account System; independent of employment state |
| `EmployeeRelationship` | Employee ID, employment state, department, position, manager and employment dates | HR is authoritative for employment facts; IAM references them for access provisioning |
| `ExternalRelationship` | Approved vendor/partner relationship, sponsor, scope and expiry | Named sponsoring business owner; restricted and time-bound |
| `OrganizationalRole` | Versioned position/role definition and organizational metadata | Identity Matrix; role definitions do not silently grant unrestricted data access |
| `RoleAssignment` | Person-to-role link, scope, effective dates, status, approver and source | Identity Matrix with HR lifecycle input and audit trail |
| `PermissionGrant` | Action/resource/scope grants, constraints and expiry | Identity Matrix/policy service; checked server-side by consuming modules |
| `IntegrationEntitlement` | Explicit access to a module or connected integration | Identity Matrix; separately scoped and revocable |
| `ProfileAppearancePreference` | Standard, role-based, personal-approved, or system/default appearance choice | User preference domain, subject to company policy; no permission effect |
| `RoleColorAssignment` | Optional centrally managed unique role color token/value and version | Identity Matrix/design registry; used only as supplemental visual metadata |
| `Session` | Active authentication context, device/session metadata, expiry and revocation | IAM/identity provider; independently governed from display preferences |
| `AuditEvent` | Append-only evidence of identity, grant, lifecycle and admin changes | Central Audit Service, restricted access |

Use stable opaque identifiers across modules; maintain mappings to external identity-provider subjects. Email changes are verified identity updates, not a new person by default. Define account linking and recovery procedures to prevent mistaken merges or account takeover.

### 3.2 One identity, distinct relationships

One person may use one verified email/username and login identity for both employee and customer experiences. Employee and customer relationships remain separately addressable and independently governed.

- Ending employment revokes employee grants and sessions according to policy; it does not deactivate the customer account.
- Customer restrictions affect customer actions only unless a distinct, approved security/legal policy applies; they do not terminate employment.
- Employee permissions do not authorize customer data access outside explicit business purpose, scope, and auditing requirements.
- CEO-authorized account freezes identify the affected relationship(s), scope, reason, duration/review date, and restore path. A freeze must not implicitly freeze every relationship on a shared person identity unless a separately approved security measure requires it.
- If a security incident requires a whole-login lock, document it as an authentication/session security action distinct from an employment or customer-account status change.

## 4. Organizational role architecture

The Identity Matrix supports a configurable, versioned organizational hierarchy. Initial role examples include:

- **Executive leadership:** CEO, CIO, COO, CFO, other approved executives.
- **Management:** General Manager, Assistant General Manager, Department Manager, Operations Manager, Sales Manager, Warehouse Manager, HR Manager, Loss Prevention Manager.
- **Accounting and finance:** Accounting Administrator, Accountant, Accounts Payable, Accounts Receivable, Payroll Administrator, Financial Analyst.
- **Sales and customer operations:** Sales Associate, Senior Sales Associate, Sales Specialist, Customer Service Representative, CRM Representative, Deal Desk Specialist.
- **Inventory and warehouse:** Inventory Manager, Inventory Specialist, Receiving Associate, Warehouse Associate, Shipping and Fulfillment Associate.
- **Technology and administration:** IT Administrator, Systems Administrator, Security Administrator, Marketing Specialist, Administrative Specialist.

These are examples, not a fixed limit. Role definitions have stable IDs, names, department, description, active/deprecated state, version, reporting metadata, optional role-color reference, and permission policy references. Editing a role definition must not silently rewrite historical assignments or retroactively change access without a reviewed grant migration. Deactivate/deprecate roles rather than deleting records referenced by history.

Separate **position/title**, **department**, **manager/reporting line**, and **authorization role** when their meanings differ. A displayed title does not confer access. Multiple roles may be assigned only when approved and with explicit scope/expiry and conflict-of-interest review.

## 5. Permissions and Identity Matrix

### 5.1 Permission dimensions

For each resource/module, policy must explicitly define permitted actions, as applicable:

- Module discovery/visibility (presentation only; not a security boundary).
- Read, create, edit, archive/delete, execute, and approve.
- Export/report access.
- Financial, employee, customer, restricted-identifier, configuration, and audit data access.
- Integration/API access, action scope, and resource/location/department constraints.

Use action/resource/scope grants and attributes such as department, assigned location, record ownership, case assignment, data classification, and effective dates. Deny by default. Require separate approval authority from ordinary edit permission where appropriate. Destructive or high-impact permissions require documented business purpose, approver, and periodic review.

### 5.2 Authorization enforcement

- Enforce authorization in server-side handlers/services and at data-access boundaries for every request, job, export, and integration; client-side navigation controls are not enforcement.
- Check current grant status and session validity. Revocation and policy changes must take effect within the documented propagation target, including long-lived sessions and background jobs.
- Service identities are non-human, uniquely named, narrowly scoped, environment-specific, and revocable; do not reuse employee accounts or secrets.
- Record authorization denials and privileged data exports with appropriate privacy controls; avoid logging sensitive payloads.
- A role's color, an employee's preference, UI theme, job title, department label, or AI output must never grant or modify permissions.

### 5.3 Role-specific integration entitlements

Example default candidates, to be approved rather than assumed: sales roles may request CRM/POS/customer lookup/Deal Desk; accounting roles accounting/reconciliation/authorized financial reports; warehouse roles receiving/inventory/picking/fulfillment; HR roles restricted employee records/onboarding/training; IT roles approved support tools; executive roles authorized command/reporting. Each entitlement is independently grantable, scoped, reviewable, monitored, and revocable. A new role must not automatically inherit every integration used by a similarly named role.

Role or department changes trigger a diff of existing versus required grants, approval of new access, removal/expiry of obsolete access, session re-evaluation, notification, and audit evidence. Avoid “add new grants without removing old grants” privilege accumulation.

## 6. Optional visual profile preferences and role-color registry

### 6.1 Signup and preference behavior

After the employee relationship and approved role are created, show appearance options only if enabled by company policy:

- **Standard MME profile appearance:** default and safe fallback for all new employees; does not use role color as the employee's primary profile color.
- **Role-based appearance:** optional; uses the current approved role-color token in supported profile interfaces. It is not official proof of role and never substitutes for visible text, labels, or access checks.
- **Personal approved color:** optional and only available if enabled; selected from a centrally approved palette. It cannot impersonate another role, alter organizational identity, or replace official role metadata.

Standard is preselected. Skip, unavailable preference service, unassigned color, or disabled option results in standard appearance without blocking onboarding. Employees may change preferences only when administrator policy permits; administrators may reset a preference. Save the preference against the employee relationship/profile—not the authoritative role record—and audit administrative changes and policy-required preference changes.

Unauthenticated public visitors may receive a local display preference if separately approved, but this is not a user identity/profile record. Do not claim cross-device persistence until an authenticated preference store exists.

### 6.2 Role-color registry

The registry is optional and centrally administered. Each designated active role has a unique canonical color assignment; no two designated roles may share the same registered color value/token under the uniqueness policy. Use stable role IDs and a versioned design token rather than embedding raw color choices in permission logic.

Registry rules:

- Reserve colors transactionally to prevent concurrent duplicate assignments.
- Validate permitted color formats and palette policy; reject invalid or duplicate assignments.
- Prevent deletion or reassignment that would make active and historical role views ambiguous; define effective dates and preserve prior values in history.
- Record actor, timestamp, role, previous/new value, reason, approval reference, and version.
- If no unique accessible color is available, mark the role unassigned or expand the approved palette; do not silently reuse a value.
- Maintain a non-color role label/icon/pattern so the role remains distinguishable to people with color-vision differences and in monochrome/assistive contexts.

Role colors may appear in authorized organizational charts, directories, and management reports irrespective of individual profile preference. They remain descriptive metadata and are never the sole indicator of official identity, authorization, status, or department. Verify text/background contrast and do not assume globally unique hues are perceptually distinguishable for every viewer.

## 7. CEO governance and privileged access

CEO-governed capabilities include creating/editing/deactivating roles, approving privileged access, managing role-color and company profile settings, approving critical permissions, freezing/restoring accounts, reviewing access history, revoking unauthorized access, and auditing administrative changes.

Requirements for privileged actions:

- Strong authentication and step-up/MFA as supported; re-confirm intent for sensitive actions.
- Server-side CEO authorization, explicit target relationship/scope, reason, effective time/duration, and approval reference where applicable.
- Immutable/tamper-evident audit record and notification to designated reviewers.
- No silent override by an employee, module, automation, or AI agent.
- Emergency/break-glass access is narrowly scoped and time-limited, alerted, and subject to post-use review.
- Where feasible, separate proposer, approver, and executor for high-risk changes; CEO retains final governance authority.
- Applicable law, contractual obligations, and security incident response remain binding.

## 8. Onboarding, role changes, and offboarding lifecycle

### 8.1 Onboarding and provisioning

1. HR creates/validates the employee relationship and employment record.
2. IAM creates or links a person identity and verified login without duplicating an existing customer identity.
3. Identity Matrix assigns an approved role, department, reporting relationship, scope, effective date, and approver.
4. Policy computes a proposed minimum permission set; manager/authorized approver reviews and CEO approves designated privileged access.
5. Scoped integration entitlements are provisioned with result/error tracking.
6. Training, competency, equipment and onboarding tasks are generated by their owning systems.
7. Employee selects an allowed appearance or keeps the preselected standard appearance; skip/unavailable path is supported.
8. User receives only authorized employee experience access; access and appearance events are separately recorded.

### 8.2 Role, department, and status change

Changes create a versioned proposal/diff, apply required approvals, reconcile grants and sessions, expire old entitlements, notify responsible parties, and audit before/after state. HR remains the authority for employment facts; Identity Matrix remains the authority for permissions.

### 8.3 Termination, suspension, freeze, archive

Support the specified states—pending, active, temporarily suspended, frozen, terminated, archived—with definitions and allowed transitions. Avoid ambiguous overlapping states by representing authentication status, customer relationship status, and employee relationship status independently where appropriate.

On termination/suspension: revoke or restrict employee entitlements promptly according to policy; invalidate sessions and credentials as appropriate; route equipment/tasks for review; notify system owners; preserve legally required records; retain audit evidence; and leave the customer relationship unchanged unless separately acted upon. Account freezes/restores identify scope, reason, duration/review date, responsible approver, impacted sessions, and notification/audit events.

## 9. Employee profile and sensitive records

An employee profile may include employee ID, name and approved contact information, department, position, role assignment, official role color reference, appearance preference, manager, employment status, hire date, approved access list, training status, tasks, and authorized performance information.

- Restrict HR, disciplinary, performance, payroll, identity recovery, and access-history details by purpose and role.
- Do not expose full access history to ordinary employees or unrelated managers.
- Use field-level access, masking, export controls, retention limits, and audit for sensitive reads/exports.
- Separate the ordinary employee profile view from restricted HR case records.
- Store minimum necessary personal data, define correction/retention/deletion/legal-hold policy, and review applicable legal requirements before implementation.

## 10. Authentication, security, and audit requirements

- Use an established identity provider or reviewed authentication implementation; do not invent credential cryptography. Protect password credentials using established secure mechanisms if locally managed; keep secrets out of the application database/logs where possible.
- MFA for CEO/admin and privileged roles; secure recovery, rate limiting, session rotation/revocation, device/session inventory, and anomaly response.
- Encrypt communications and sensitive persisted data; managed secrets and environment separation; prevent credentials from entering source control.
- Server-side deny-by-default authorization and API/service scopes; periodic access and privileged-grant review; prompt offboarding/revocation.
- Validate all identity, role, permission, integration and color-registry inputs; protect against mass assignment, IDOR, privilege escalation, CSRF/session abuse, and unsafe exports.
- Central audit events for identity creation/linking, account/relationship status, role definition/assignment, grant changes, integration authorization, login/security events, appearance policy and preference changes where policy requires, role-color changes, freezes/restores, termination, exports, and privileged actions.
- Audit events include actor/service, target identity/relationship, action, timestamp, source/correlation ID, outcome, reason/approval reference, and relevant versioned before/after values or hashes. Never include passwords, tokens, recovery codes, or unnecessary sensitive payloads.
- Monitor unusual login, privilege changes, repeated denials, bulk exports, break-glass use, and unexpected integration access; define alert owner and response procedure.
- Apply retention, privacy, access correction, and deletion rules to identity and audit data; applicable jurisdiction and employment/privacy obligations require review.

## 11. Data and API contracts

The Identity Matrix exposes controlled, versioned operations such as:

- Resolve authenticated subject to opaque person/login identity.
- Read authorized relationship summary and status.
- Request role assignment/revocation with approver and effective time.
- Evaluate action/resource/scope authorization.
- Provision/revoke a scoped integration entitlement.
- Read an approved profile preference or company appearance policy.
- Propose/approve role-color changes with uniqueness validation.
- Emit lifecycle, role/grant, session-revocation, and policy-version events.

Contracts must define schema version, owner, authorization scopes, idempotency key for mutating commands, concurrency/version behavior, error semantics, retries, correlation, audit, retention, and revocation propagation. Consumers must not infer permissions from role names, color, UI state, cached tokens beyond their validity, or employee profile fields. Employment and customer lifecycle events must identify relationship type so a consumer cannot confuse termination of employment with closure of the customer account.

## 12. Implementation and migration instructions

Before implementation:

1. Inspect current Replit project and repository for auth provider, users/employee/customer records, role grants, APIs, environment secrets, integrations, tests, and deployment configuration.
2. Map existing identities and roles without exposing credentials; identify duplicates/conflicts and create a reviewed migration plan.
3. Define identity linking, verified-email uniqueness, recovery, merge/unmerge, customer/employee separation, and provider subject mapping.
4. Establish role catalog, permission/action matrix, data scopes, policy versioning, and integration entitlement owners.
5. Implement additive schema/API changes and migration/rollback; preserve existing auth and sessions where safely possible.
6. Add centralized role-color registry with uniqueness constraint/transaction and accessible fallback metadata.
7. Add optional profile preference only after the employee relationship, role and settings policy are authoritative; standard remains default and skip path works.
8. Integrate onboarding/offboarding with HR and session revocation; test customer relationship independence.
9. Add audit, monitoring, access review, and recovery procedures before privileged administration is exposed.
10. Test server-side authorization and role-specific integrations; never rely only on rendered navigation.

Do not replace an existing identity provider without explicit approval, proofed account mapping, staged migration, rollback, incident plan, and user communication. Maintain version history and document dependencies, unresolved risks, and unimplemented integrations.

## 13. Acceptance criteria and test plan

Build 004 is ready for implementation review when evidence demonstrates:

- [ ] Each person/login has a stable unique underlying identity; verified email/username uniqueness and account-link recovery rules are defined.
- [ ] Employee and customer relationships can coexist under one login and remain independently addressable/status-controlled.
- [ ] Employee termination revokes employee access/sessions per policy but does not automatically deactivate customer access; customer restriction does not terminate employment.
- [ ] Role definitions are centrally versioned and can be added/deactivated without breaking historical assignments.
- [ ] Authorization is deny-by-default, action/resource/scope-aware, and enforced server-side for routes, APIs, jobs, data access, and exports.
- [ ] Role colors and visual preferences do not change permissions or represent authorization as a sole signal.
- [ ] Standard profile appearance is selected by default; skip/unavailable paths work; role-based and approved personal choices are controlled by company policy.
- [ ] Role color values are unique among designated roles under concurrent updates; changes have versioned history and audit evidence; non-color role identifiers remain available.
- [ ] Role/department changes reconcile old and new permissions, integrations, and sessions without privilege accumulation.
- [ ] External/vendor and service identities are sponsored, scoped, expiring/revocable, and auditable.
- [ ] CEO privileged actions require approved authentication/authorization, scope/reason, audit, and appropriate notification/review.
- [ ] Restricted HR/customer/financial/identity data is protected, masked, and access/export audited.
- [ ] Tests cover identity linking, duplicate prevention, access denial, escalation attempts, termination/customer separation, session revocation, preference policy, color uniqueness, audit integrity, and integration provisioning.
- [ ] Migration preserves verified existing authentication and has rollback; no existing provider is replaced without approval.
- [ ] Capability status is reported honestly with commit, environment, test evidence, reviewer, and known gaps.

Minimum negative tests include: employee accessing another employee's restricted file; customer session invoking employee API; role color attempting to affect access; unapproved role assignment; stale session after revocation; employee termination closing customer account; customer freeze changing HR status; duplicate color under concurrent admin writes; unapproved personal color; export without permission; and AI/service identity attempting CEO-only actions.

## 14. Decisions required before implementation

1. Identity provider and authoritative authentication subject; MFA, SSO, recovery and account-link policy.
2. Verified email/username change and duplicate-identity resolution process.
3. HR source system and event timing/availability; offboarding revocation target and emergency procedure.
4. Role catalog owner, multiple-role rules, role/version deprecation and access-review cadence.
5. Permission vocabulary, scope model (department/location/record/case), approval thresholds, and segregation-of-duties rules.
6. Role-specific integration owners, available provider APIs, and provisioning/deprovisioning guarantees.
7. Employee appearance preference persistence and synchronization, default company appearance, approved personal palette, and policy for changes after signup.
8. Role-color accessibility palette, uniqueness/effective-date semantics, and behavior when no unique compliant color is available.
9. Account state transition definitions, freeze scope, retention/legal hold, and customer/employee notification rules.
10. Audit storage protections, retention schedule, alert ownership, and applicable privacy/employment jurisdiction review.

## 15. Current completion boundary

This document is the Build 004 architecture and acceptance specification only. No centralized identity provider, Identity Matrix, employee/customer relationship store, role/permission engine, role-specific integration provisioning, role-color registry, onboarding/offboarding integration, or appearance preference persistence is established or verified by this document. Build 004 must not be declared implemented or complete until the capabilities are delivered additively, tested in the actual deployment environment, and reviewed against the acceptance criteria.
