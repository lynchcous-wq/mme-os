# Catalog API and Employee Workspace Contract

**Status:** UI prototype authored; authentication, persistence and API integration are not connected.

## Employee catalog workflow

1. An authenticated employee with catalog-create permission may prepare a draft.
2. Server validates SKU uniqueness, category, condition, tracking mode and category-specific specification schema.
3. Employee submits draft for review; catalog status becomes `pending_approval`.
4. A CEO or explicitly authorized approver reviews and approves or rejects the record.
5. Publication service writes approval identity/time and publishes only approved products.
6. Every create, edit, submit, approve, reject, publish and archive action appends a catalog event.

## Proposed API boundary

- `GET /api/employee/catalog`: paginated records; permission `catalog.read`.
- `POST /api/employee/catalog`: create draft; permission `catalog.create`.
- `GET /api/employee/catalog/:id`: record detail; permission `catalog.read`.
- `PATCH /api/employee/catalog/:id`: version-checked edit; permission `catalog.edit`.
- `POST /api/employee/catalog/:id/submit`: submit for approval; permission `catalog.submit`.
- `POST /api/employee/catalog/:id/approve`: approve; permission `catalog.approve`.
- `POST /api/employee/catalog/:id/reject`: reject with reason; permission `catalog.approve`.
- `POST /api/employee/catalog/:id/publish`: publish approved product; permission `catalog.publish`.

Approval and publication are CEO-only by default. Delegation requires an explicit server-side grant from the CEO. The submitting employee must not approve their own submission. A client-provided role, status, approval identity or permission flag is never trusted.

All write endpoints must:
- Require a server-verified employee session and permission check.
- Validate request bodies server-side; never trust client-side validation.
- Use optimistic concurrency via product `version`.
- Write audit events in the same database transaction as the state change.
- Enforce rate limits and CSRF/origin protections appropriate to the auth design.
- Return generic errors without leaking secrets or internal SQL details.

## Domain boundaries

Catalog APIs must not write inventory unit balances, reservations, orders, costs, active selling prices, payments, customer records, IMEI or full serial numbers. Product images/demo videos must use controlled storage upload flows; do not accept arbitrary untrusted file paths. External media links must be HTTPS and validated against an approved policy.

## Integration blockers

The current repository's package manifest has only Next.js, React and TypeScript. No Supabase client, auth provider, employee session model, database environment configuration, storage bucket policy or role/permission service is present. Do not expose write endpoints until those are implemented and verified. The current `/employee/catalog` screen is a local-only preview and intentionally does not persist records.
