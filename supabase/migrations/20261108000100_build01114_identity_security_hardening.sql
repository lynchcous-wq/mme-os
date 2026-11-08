-- Build 011.14 — additive identity security and FK index hardening
-- Verified against live Supabase project cyatezcfjvewdnibthox on 2026-11-08.
-- No tables, rows, relationship states, or RLS policies are changed.
-- RLS remains enabled with no policies: direct client access remains denied.

-- Trigger functions are invoked by PostgreSQL triggers. They are not public RPCs.
-- Remove default PUBLIC execution and explicitly deny client API roles.
revoke execute on function public.mme_audit_person_identity_created()
  from public, anon, authenticated;

revoke execute on function public.mme_reject_identity_audit_mutation()
  from public, anon, authenticated;

-- Cover foreign keys flagged by the Supabase performance advisor.
create index if not exists mme_identity_audit_events_actor_identity_idx
  on public.mme_identity_audit_events (actor_identity_id);

create index if not exists mme_integration_entitlements_employee_idx
  on public.mme_integration_entitlements (employee_relationship_id);

create index if not exists mme_permission_grants_role_assignment_idx
  on public.mme_permission_grants (role_assignment_id);

create index if not exists mme_person_identities_security_locked_by_idx
  on public.mme_person_identities (security_locked_by_identity_id);

create index if not exists mme_role_assignments_role_idx
  on public.mme_role_assignments (role_id);
