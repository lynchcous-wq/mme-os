# Build 010.83 — Customer Account Activation and Identity Linking

## Scope
- Adds a customer-submitted identity-link request page at `/account/link-request`.
- Adds an authenticated API requiring a valid browser session and confirmed Supabase email.
- Allows optional customer/order reference, phone last four digits, and a bounded note.
- Creates a pending review record; it does not create or update a person identity or customer account link.
- Adds a partial unique index to prevent more than one open request per Auth user.
- Adds a database trigger-backed lifecycle audit for request submission and staff review status changes.
- Keeps the existing customer portal gate unchanged: an active account link and active MME person identity are still required.

## Review and approval controls
Requests are visible only to the service role. The customer cannot read or mutate the request queue through direct table access. Staff must verify identity using existing trusted business records and the established MME approval process. Only after independent approval may an authorized operator use the existing service-role-only `mme_customer_portal_provision_account_link` workflow to connect the Auth UUID to the confirmed person UUID. Email equality, customer-supplied references, and notes are not proof of identity.

This build intentionally does not introduce a public approval endpoint or browser-callable provisioning RPC. No customer or employee role is granted by request submission.

## Security and operations
- Requires Supabase service-role environment configuration on the server.
- No full phone, payment-card, password, or government ID data is collected.
- Request payload bounds, same-origin check, verified-email requirement, no-store provider calls.
- Review records and audit trail are restricted to service role; staff workflow and audit attribution must be verified before operational use.
- Add edge rate limiting, abuse monitoring, and a staff review interface in a later build before public rollout.

## Verification status
Contract tests are added but not executed in this environment. Migration has not been applied. No Supabase production data or settings were changed. Not merged or deployed. Production activation requires migration review/application, verified staff authorization workflow, rate limiting, and staging tests.
