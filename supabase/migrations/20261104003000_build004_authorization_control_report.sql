begin;

-- Build 004: read-only parity report for legacy CEO provisioning and global freeze.
-- The legacy singleton remains authoritative until an approved replacement exists.
create or replace function public.mme_employee_authorization_control_report()
returns table (
  legacy_control_configured boolean,
  employee_access_frozen boolean,
  freeze_reason_present boolean,
  ceo_identity_linked boolean,
  ceo_legacy_employee_active boolean,
  ceo_build004_employee_status text,
  build004_whole_login_locked boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    s.ceo_user_id is not null,
    coalesce(s.employee_access_frozen, true),
    (s.freeze_reason is not null),
    (p.id is not null),
    coalesce(l.employment_status = 'active', false),
    e.status,
    coalesce(p.security_status = 'locked', false)
  from public.employee_security_settings s
  left join public.mme_person_identities p on p.auth_user_id = s.ceo_user_id
  left join public.employee_relationships l on l.user_id = s.ceo_user_id
  left join public.mme_employee_relationships e on e.person_identity_id = p.id
  where s.singleton is true

  union all

  select false, true, false, false, false, null::text, false
  where not exists (
    select 1 from public.employee_security_settings where singleton is true
  )
  limit 1;
$$;

revoke all on function public.mme_employee_authorization_control_report()
  from public, anon, authenticated;
grant execute on function public.mme_employee_authorization_control_report()
  to service_role;

comment on function public.mme_employee_authorization_control_report() is
  'Build 004 read-only compatibility diagnostics for legacy CEO provisioning/global employee freeze and Build 004 CEO identity/employee/security state. Missing legacy control row fails closed in report. Service-role execution only; no writes or authorization decisions.';

commit;
