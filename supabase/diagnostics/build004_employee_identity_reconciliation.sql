-- Build 004: read-only legacy employee / Identity Matrix reconciliation.
-- Run manually in a trusted development/staging SQL session.
-- This script performs no INSERT, UPDATE, DELETE, DDL, or permission changes.
-- Output contains opaque Auth UUIDs only; do not export it to public logs.

begin;
set transaction read only;

-- 1. Summary by reconciliation state.
with legacy as (
  select
    er.user_id,
    er.employment_status,
    er.employee_number,
    p.id as person_identity_id,
    p.security_status,
    me.id as mme_employee_relationship_id,
    me.status as mme_employee_status,
    cr.status as customer_relationship_status,
    coalesce(lg.grant_count, 0) as legacy_active_grant_count,
    coalesce(na.assignment_count, 0) as mme_role_assignment_count,
    coalesce(ng.grant_count, 0) as mme_active_permission_grant_count
  from public.employee_relationships er
  left join public.mme_person_identities p
    on p.auth_user_id = er.user_id
  left join public.mme_employee_relationships me
    on me.person_identity_id = p.id
  left join public.mme_customer_relationships cr
    on cr.person_identity_id = p.id
  left join lateral (
    select count(*)::bigint as grant_count
    from public.employee_permission_grants g
    where g.employee_user_id = er.user_id
      and g.revoked_at is null
      and (g.expires_at is null or g.expires_at > statement_timestamp())
  ) lg on true
  left join lateral (
    select count(*)::bigint as assignment_count
    from public.mme_role_assignments ra
    where ra.employee_relationship_id = me.id
      and ra.status = 'active'
      and ra.effective_from <= statement_timestamp()
      and (ra.effective_until is null or ra.effective_until > statement_timestamp())
  ) na on true
  left join lateral (
    select count(*)::bigint as grant_count
    from public.mme_permission_grants g
    join public.mme_role_assignments ra on ra.id = g.role_assignment_id
    where ra.employee_relationship_id = me.id
      and g.status = 'active'
      and ra.status = 'active'
      and ra.effective_from <= statement_timestamp()
      and (ra.effective_until is null or ra.effective_until > statement_timestamp())
  ) ng on true
),
classified as (
  select *,
    case
      when person_identity_id is null then 'missing_person_identity'
      when mme_employee_relationship_id is null then 'missing_mme_employee_relationship'
      when security_status = 'locked' then 'whole_login_locked_manual_review'
      when employment_status = 'terminated' and mme_employee_status <> 'terminated'
        then 'legacy_terminated_mme_not_terminated'
      when employment_status = 'suspended' and mme_employee_status not in ('temporarily_suspended','frozen','terminated','archived')
        then 'legacy_suspended_mme_active_or_pending'
      when employment_status = 'active' and mme_employee_status <> 'active'
        then 'legacy_active_mme_not_active'
      else 'identity_linked_status_review_required'
    end as reconciliation_state
  from legacy
)
select
  reconciliation_state,
  count(*) as employee_count,
  sum(legacy_active_grant_count) as legacy_active_grants,
  sum(mme_role_assignment_count) as active_mme_role_assignments,
  sum(mme_active_permission_grant_count) as active_mme_permission_grants
from classified
group by reconciliation_state
order by reconciliation_state;

-- 2. Restricted detail for authorized reviewers.
-- This deliberately does not expose email, phone, name, role display name,
-- permission payload, or customer profile data.
with legacy as (
  select
    er.user_id,
    er.employment_status,
    er.employee_number,
    p.id as person_identity_id,
    p.security_status,
    me.id as mme_employee_relationship_id,
    me.employee_number as mme_employee_number,
    me.status as mme_employee_status,
    cr.status as customer_relationship_status,
    coalesce(lg.grant_count, 0) as legacy_active_grant_count,
    coalesce(na.assignment_count, 0) as mme_active_assignment_count,
    coalesce(ng.grant_count, 0) as mme_active_grant_count
  from public.employee_relationships er
  left join public.mme_person_identities p
    on p.auth_user_id = er.user_id
  left join public.mme_employee_relationships me
    on me.person_identity_id = p.id
  left join public.mme_customer_relationships cr
    on cr.person_identity_id = p.id
  left join lateral (
    select count(*)::bigint as grant_count
    from public.employee_permission_grants g
    where g.employee_user_id = er.user_id
      and g.revoked_at is null
      and (g.expires_at is null or g.expires_at > statement_timestamp())
  ) lg on true
  left join lateral (
    select count(*)::bigint as assignment_count
    from public.mme_role_assignments ra
    where ra.employee_relationship_id = me.id
      and ra.status = 'active'
      and ra.effective_from <= statement_timestamp()
      and (ra.effective_until is null or ra.effective_until > statement_timestamp())
  ) na on true
  left join lateral (
    select count(*)::bigint as grant_count
    from public.mme_permission_grants g
    join public.mme_role_assignments ra on ra.id = g.role_assignment_id
    where ra.employee_relationship_id = me.id
      and g.status = 'active'
      and ra.status = 'active'
      and ra.effective_from <= statement_timestamp()
      and (ra.effective_until is null or ra.effective_until > statement_timestamp())
  ) ng on true
)
select
  user_id as auth_user_id,
  employee_number as legacy_employee_number,
  person_identity_id,
  security_status,
  mme_employee_relationship_id,
  mme_employee_number,
  employment_status as legacy_employment_status,
  mme_employee_status,
  customer_relationship_status,
  legacy_active_grant_count,
  mme_active_assignment_count,
  mme_active_grant_count,
  case
    when person_identity_id is null then 'missing_person_identity'
    when mme_employee_relationship_id is null then 'missing_mme_employee_relationship'
    when security_status = 'locked' then 'whole_login_locked_manual_review'
    when employment_status = 'terminated' and mme_employee_status <> 'terminated'
      then 'legacy_terminated_mme_not_terminated'
    when employment_status = 'suspended' and mme_employee_status not in ('temporarily_suspended','frozen','terminated','archived')
      then 'legacy_suspended_mme_active_or_pending'
    when employment_status = 'active' and mme_employee_status <> 'active'
      then 'legacy_active_mme_not_active'
    else 'identity_linked_status_review_required'
  end as reconciliation_state
from legacy
order by reconciliation_state, user_id;

-- 3. Identity Matrix employee relationships without a legacy employee row.
select
  me.id as mme_employee_relationship_id,
  me.employee_number as mme_employee_number,
  me.status as mme_employee_status,
  p.id as person_identity_id,
  p.security_status
from public.mme_employee_relationships me
join public.mme_person_identities p on p.id = me.person_identity_id
left join public.employee_relationships er on er.user_id = p.auth_user_id
where er.user_id is null
order by me.employee_number;

rollback;
