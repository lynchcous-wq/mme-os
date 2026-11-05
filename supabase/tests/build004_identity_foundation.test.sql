begin;

select plan(29);

select has_table('public', 'mme_person_identities', 'person identity table exists');
select has_table('public', 'mme_customer_relationships', 'customer relationship table exists');
select has_table('public', 'mme_employee_relationships', 'employee relationship table exists');
select has_table('public', 'mme_roles', 'role registry exists');
select has_table('public', 'mme_role_assignments', 'role assignments exist');
select has_table('public', 'mme_permission_grants', 'permission grants exist');
select has_table('public', 'mme_integration_entitlements', 'integration entitlements exist');
select has_table('public', 'mme_identity_audit_events', 'identity audit table exists');

select ok((select relrowsecurity from pg_class where oid = 'public.mme_person_identities'::regclass), 'person identities have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.mme_customer_relationships'::regclass), 'customer relationships have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.mme_employee_relationships'::regclass), 'employee relationships have RLS enabled');
select ok(not has_table_privilege('anon', 'public.mme_person_identities', 'select'), 'anon cannot read person identities');
select ok(not has_table_privilege('authenticated', 'public.mme_person_identities', 'select'), 'authenticated cannot read person identities');
select ok(not has_table_privilege('authenticated', 'public.mme_customer_relationships', 'insert'), 'authenticated cannot create customer relationships');
select ok(not has_table_privilege('authenticated', 'public.mme_employee_relationships', 'update'), 'authenticated cannot update employee relationships');
select ok(not has_function_privilege('anon', 'public.mme_create_person_identity()', 'execute'), 'anon cannot directly execute auth identity trigger function');
select ok(not has_function_privilege('authenticated', 'public.mme_create_person_identity()', 'execute'), 'authenticated cannot directly execute auth identity trigger function');

select has_trigger('auth', 'users', 'mme_auth_user_identity_created', 'auth user insert trigger is installed');
select has_trigger('public', 'mme_identity_audit_events', 'mme_identity_audit_no_update_delete', 'identity audit updates and deletes are blocked');
select has_trigger('public', 'mme_identity_audit_events', 'mme_identity_audit_no_truncate', 'identity audit truncation is blocked');

-- The Auth trigger creates one opaque identity and no business relationship.
insert into auth.users (id, email)
values ('b0040000-0000-4000-8000-000000000001', 'build004-test-identity@example.invalid');

select is(
  (select count(*)::integer from public.mme_person_identities
   where auth_user_id = 'b0040000-0000-4000-8000-000000000001'),
  1,
  'one auth user creates exactly one person identity'
);
select is(
  (select count(*)::integer from public.mme_customer_relationships c
   join public.mme_person_identities p on p.id = c.person_identity_id
   where p.auth_user_id = 'b0040000-0000-4000-8000-000000000001'),
  0,
  'auth trigger does not automatically create customer relationship'
);
select is(
  (select count(*)::integer from public.mme_employee_relationships e
   join public.mme_person_identities p on p.id = e.person_identity_id
   where p.auth_user_id = 'b0040000-0000-4000-8000-000000000001'),
  0,
  'auth trigger does not automatically create employee relationship'
);

-- A person may hold both relationship types; their states remain independent.
insert into public.mme_customer_relationships (person_identity_id, status)
select id, 'active' from public.mme_person_identities
where auth_user_id = 'b0040000-0000-4000-8000-000000000001';

insert into public.mme_employee_relationships (person_identity_id, employee_number, status)
select id, 'B004-TEST-001', 'active' from public.mme_person_identities
where auth_user_id = 'b0040000-0000-4000-8000-000000000001';

update public.mme_employee_relationships
set status = 'terminated'
where employee_number = 'B004-TEST-001';

select is(
  (select status from public.mme_customer_relationships c
   join public.mme_person_identities p on p.id = c.person_identity_id
   where p.auth_user_id = 'b0040000-0000-4000-8000-000000000001'),
  'active',
  'employee termination does not change customer relationship status'
);

-- Whole-login lock state requires complete metadata and is independent of
-- customer/employee lifecycle. A valid lock can be represented at schema level.
update public.mme_person_identities
set security_status = 'locked',
    security_locked_at = now(),
    security_lock_reason = 'pgTAP security-lock test'
where auth_user_id = 'b0040000-0000-4000-8000-000000000001';

select is(
  (select security_status from public.mme_person_identities
   where auth_user_id = 'b0040000-0000-4000-8000-000000000001'),
  'locked',
  'whole-login security lock is stored independently'
);

select throws_ok(
  $$update public.mme_person_identities
    set security_status = 'locked', security_locked_at = null,
        security_lock_reason = null
    where auth_user_id = 'b0040000-0000-4000-8000-000000000001'$$,
  '23514',
  null,
  'locked identity cannot omit required lock metadata'
);

-- Audit events reject mutation and truncation.
insert into public.mme_identity_audit_events
  (actor_service_key, action_key, outcome, reason)
values
  ('pgTAP-build004', 'test.identity.created', 'success', 'append-only test');

select throws_ok(
  $$update public.mme_identity_audit_events
    set reason = 'tampered'
    where actor_service_key = 'pgTAP-build004'$$,
  '42501',
  'MME identity audit events are append-only',
  'identity audit updates are rejected'
);

select throws_ok(
  $$delete from public.mme_identity_audit_events
    where actor_service_key = 'pgTAP-build004'$$,
  '42501',
  'MME identity audit events are append-only',
  'identity audit deletes are rejected'
);

select throws_ok(
  $$truncate table public.mme_identity_audit_events$$,
  '42501',
  'MME identity audit events are append-only',
  'identity audit truncation is rejected'
);

select * from finish();
rollback;
