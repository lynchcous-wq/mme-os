-- Build 011.15 — least-privilege read-only identity RLS.
-- Target verified against MME Supabase project cyatezcfjvewdnibthox.
-- No client INSERT/UPDATE/DELETE privileges are granted by this migration.
-- Audit events remain private to trusted server-side operations.

-- Grant only the SELECT privilege required for narrowly scoped RLS reads.
grant select on table
  public.mme_person_identities,
  public.mme_customer_relationships,
  public.mme_employee_relationships,
  public.mme_roles,
  public.mme_role_assignments,
  public.mme_permission_grants,
  public.mme_integration_entitlements,
  public.mme_profile_appearance_preferences,
  public.mme_role_color_registry
to authenticated;

-- Identity: a signed-in user may see only their own person row.
create policy mme_person_identity_select_self
on public.mme_person_identities
for select to authenticated
using ((select auth.uid()) is not null and auth_user_id = (select auth.uid()));

-- Customer relationship: only the user's own active customer relationship,
-- and only while the underlying person identity is not security-locked.
create policy mme_customer_relationship_select_self_active
on public.mme_customer_relationships
for select to authenticated
using (
  status = 'active'
  and exists (
    select 1
    from public.mme_person_identities p
    where p.id = person_identity_id
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Employee relationship: active employee relationship only; terminated,
-- suspended, frozen, pending and archived relationships are not exposed.
create policy mme_employee_relationship_select_self_active
on public.mme_employee_relationships
for select to authenticated
using (
  status = 'active'
  and exists (
    select 1
    from public.mme_person_identities p
    where p.id = person_identity_id
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Active role assignments for the signed-in active employee only.
create policy mme_role_assignment_select_self_active
on public.mme_role_assignments
for select to authenticated
using (
  status = 'active'
  and effective_from <= now()
  and (effective_until is null or effective_until > now())
  and exists (
    select 1
    from public.mme_employee_relationships e
    join public.mme_person_identities p on p.id = e.person_identity_id
    where e.id = employee_relationship_id
      and e.status = 'active'
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Role definitions are readable only where the employee has a current,
-- active assignment to that role.
create policy mme_roles_select_assigned_active
on public.mme_roles
for select to authenticated
using (
  active = true
  and exists (
    select 1
    from public.mme_role_assignments ra
    join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
    join public.mme_person_identities p on p.id = e.person_identity_id
    where ra.role_id = id
      and ra.status = 'active'
      and ra.effective_from <= now()
      and (ra.effective_until is null or ra.effective_until > now())
      and e.status = 'active'
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Permission grants are visible only for the user's own current active role.
create policy mme_permission_grant_select_self_active
on public.mme_permission_grants
for select to authenticated
using (
  status = 'active'
  and exists (
    select 1
    from public.mme_role_assignments ra
    join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
    join public.mme_person_identities p on p.id = e.person_identity_id
    where ra.id = role_assignment_id
      and ra.status = 'active'
      and ra.effective_from <= now()
      and (ra.effective_until is null or ra.effective_until > now())
      and e.status = 'active'
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Integration entitlements are readable only by the employee to whom they belong.
create policy mme_integration_entitlement_select_self_active
on public.mme_integration_entitlements
for select to authenticated
using (
  status = 'active'
  and exists (
    select 1
    from public.mme_employee_relationships e
    join public.mme_person_identities p on p.id = e.person_identity_id
    where e.id = employee_relationship_id
      and e.status = 'active'
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Employees can read only their own appearance preferences.
create policy mme_profile_appearance_select_self
on public.mme_profile_appearance_preferences
for select to authenticated
using (
  exists (
    select 1
    from public.mme_employee_relationships e
    join public.mme_person_identities p on p.id = e.person_identity_id
    where e.id = employee_relationship_id
      and e.status = 'active'
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Employee can see the approved color for a role they currently hold.
create policy mme_role_color_select_assigned_active
on public.mme_role_color_registry
for select to authenticated
using (
  exists (
    select 1
    from public.mme_role_assignments ra
    join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
    join public.mme_person_identities p on p.id = e.person_identity_id
    where ra.role_id = mme_role_color_registry.role_id
      and ra.status = 'active'
      and ra.effective_from <= now()
      and (ra.effective_until is null or ra.effective_until > now())
      and e.status = 'active'
      and p.auth_user_id = (select auth.uid())
      and p.security_status = 'active'
  )
);

-- Intentionally no client grants or policies for mme_identity_audit_events.
-- Intentionally no INSERT, UPDATE or DELETE policies on any table above.
