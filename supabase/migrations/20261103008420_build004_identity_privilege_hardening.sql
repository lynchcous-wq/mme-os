-- Build 004 identity bridge privilege hardening.
-- Make the intended server-only grants explicit rather than relying on
-- project-wide default privileges. No identity data is created or changed.
begin;

revoke all on public.mme_person_identities
  from public, anon, authenticated;
revoke all on public.mme_login_identities
  from public, anon, authenticated;

grant select, insert, update on public.mme_person_identities
  to service_role;
grant select, insert, update on public.mme_login_identities
  to service_role;

revoke all on function public.mme_person_identity_set_updated_at()
  from public, anon, authenticated, service_role;

revoke all on function public.mme_resolve_person_for_auth_subject(uuid)
  from public, anon, authenticated;
grant execute on function public.mme_resolve_person_for_auth_subject(uuid)
  to service_role;

comment on function public.mme_person_identity_set_updated_at() is
  'Trigger-only timestamp maintenance function; direct execution is not granted to application roles.';
comment on function public.mme_resolve_person_for_auth_subject(uuid) is
  'Server-only resolver. Execute permission is restricted to service_role; callers must derive the Auth subject from a validated session.';

commit;
