begin;

-- Build 004: read-only legacy-to-identity reconciliation diagnostics.
-- No grants, identities, employee records, or CEO settings are changed.
create or replace function public.mme_employee_identity_reconciliation_report()
returns table (
  issue_key text,
  severity text,
  legacy_user_id uuid,
  person_identity_id uuid,
  details jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with legacy as (
    select
      l.user_id,
      l.employment_status,
      p.id as person_identity_id,
      p.security_status,
      e.id as build004_employee_id,
      e.status as build004_employee_status,
      coalesce((
        select count(*)::integer
        from public.employee_permission_grants g
        where g.employee_user_id = l.user_id
          and g.revoked_at is null
          and (g.expires_at is null or g.expires_at > statement_timestamp())
      ), 0) as active_legacy_grant_count,
      coalesce((
        select count(*)::integer
        from public.mme_role_assignments ra
        where ra.employee_relationship_id = e.id
          and ra.status = 'active'
          and ra.effective_from <= statement_timestamp()
          and (ra.effective_until is null or ra.effective_until > statement_timestamp())
      ), 0) as active_build004_assignment_count
    from public.employee_relationships l
    left join public.mme_person_identities p on p.auth_user_id = l.user_id
    left join public.mme_employee_relationships e on e.person_identity_id = p.id
  ),
  findings as (
    select
      'missing_person_identity'::text as issue_key,
      'high'::text as severity,
      x.user_id as legacy_user_id,
      null::uuid as person_identity_id,
      jsonb_build_object('legacy_employment_status', x.employment_status) as details
    from legacy x
    where x.person_identity_id is null

    union all

    select
      'missing_build004_employee',
      'high',
      x.user_id,
      x.person_identity_id,
      jsonb_build_object('legacy_employment_status', x.employment_status)
    from legacy x
    where x.person_identity_id is not null
      and x.build004_employee_id is null

    union all

    select
      'employee_status_mismatch',
      'high',
      x.user_id,
      x.person_identity_id,
      jsonb_build_object(
        'legacy_employment_status', x.employment_status,
        'build004_employee_status', x.build004_employee_status
      )
    from legacy x
    where x.build004_employee_id is not null
      and not (
        (x.employment_status = 'active' and x.build004_employee_status = 'active')
        or (x.employment_status = 'suspended'
            and x.build004_employee_status in ('temporarily_suspended','frozen'))
        or (x.employment_status = 'terminated'
            and x.build004_employee_status in ('terminated','archived'))
      )

    union all

    select
      'whole_login_locked',
      'critical',
      x.user_id,
      x.person_identity_id,
      jsonb_build_object('security_status', x.security_status)
    from legacy x
    where x.security_status = 'locked'

    union all

    select
      'legacy_permissions_need_migration_review',
      'medium',
      x.user_id,
      x.person_identity_id,
      jsonb_build_object(
        'active_legacy_grant_count', x.active_legacy_grant_count,
        'active_build004_assignment_count', x.active_build004_assignment_count
      )
    from legacy x
    where x.active_legacy_grant_count > 0
      and x.active_build004_assignment_count = 0

    union all

    select
      'build004_employee_without_legacy_link',
      'medium',
      null::uuid,
      p.id,
      jsonb_build_object(
        'build004_employee_relationship_id', e.id,
        'build004_employee_status', e.status
      )
    from public.mme_employee_relationships e
    join public.mme_person_identities p on p.id = e.person_identity_id
    left join public.employee_relationships l on l.user_id = p.auth_user_id
    where l.user_id is null

    union all

    select
      'legacy_employee_access_frozen',
      'high',
      null::uuid,
      null::uuid,
      jsonb_build_object('freeze_reason_present', s.freeze_reason is not null)
    from public.employee_security_settings s
    where s.singleton is true and s.employee_access_frozen is true

    union all

    select
      'provisioned_ceo_identity_missing',
      'critical',
      s.ceo_user_id,
      null::uuid,
      jsonb_build_object('ceo_user_id_configured', true)
    from public.employee_security_settings s
    left join public.mme_person_identities p on p.auth_user_id = s.ceo_user_id
    where s.singleton is true
      and s.ceo_user_id is not null
      and p.id is null
  )
  select f.issue_key, f.severity, f.legacy_user_id, f.person_identity_id, f.details
  from findings f
  order by
    case f.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
    f.issue_key,
    f.legacy_user_id nulls last;
$$;

revoke all on function public.mme_employee_identity_reconciliation_report()
  from public, anon, authenticated;
grant execute on function public.mme_employee_identity_reconciliation_report()
  to service_role;

comment on function public.mme_employee_identity_reconciliation_report() is
  'Build 004 read-only diagnostic report comparing legacy employee relationships and grants with Build 004 identities, employee relationships and active role assignments. Returns technical IDs and status/count metadata only. Does not create, update, migrate, revoke, or authorize anything. Service-role execution only.';

commit;
