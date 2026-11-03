-- Build 004 integration checks. Run against a disposable local Supabase database
-- after applying migrations 001-004 and the dependent append-only migration 003.
-- The test runs inside the pgTAP transaction and rolls back its fixtures.

begin;

select plan(13);

select has_table('public', 'mme_person_identities', 'person identity table exists');
select has_column('public', 'mme_person_identities', 'security_status', 'whole-login security status exists');

-- Supabase Auth insert trigger must create exactly one opaque MME identity.
insert into auth.users (
  id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1000000-0000-4000-8000-000000000004',
  'authenticated', 'authenticated',
  'build004-pgtap@example.test', '',
  '{}'::jsonb, '{}'::jsonb, now(), now()
)
on conflict (id) do nothing;

select is(
  (select count(*)::integer from public.mme_person_identities
   where auth_user_id = 'a1000000-0000-4000-8000-000000000004'),
  1,
  'Auth subject maps to exactly one MME identity'
);

select is(
  (select security_status from public.mme_person_identities
   where auth_user_id = 'a1000000-0000-4000-8000-000000000004'),
  'active',
  'new MME identity starts with active whole-login status'
);

insert into public.mme_customer_relationships (person_identity_id, status)
select id, 'active'
from public.mme_person_identities
where auth_user_id = 'a1000000-0000-4000-8000-000000000004'
on conflict (person_identity_id) do nothing;

insert into public.mme_employee_relationships (
  person_identity_id, employee_number, status
)
select id, 'Pgtap-B004-Employee', 'active'
from public.mme_person_identities
where auth_user_id = 'a1000000-0000-4000-8000-000000000004'
on conflict (person_identity_id) do nothing;

select is(
  (select count(*)::integer from public.mme_customer_relationships cr
   join public.mme_person_identities pi on pi.id = cr.person_identity_id
   where pi.auth_user_id = 'a1000000-0000-4000-8000-000000000004'),
  1,
  'customer relationship can coexist with employee relationship'
);

select is(
  (select count(*)::integer from public.mme_employee_relationships er
   join public.mme_person_identities pi on pi.id = er.person_identity_id
   where pi.auth_user_id = 'a1000000-0000-4000-8000-000000000004'),
  1,
  'employee relationship can coexist with customer relationship'
);

update public.mme_employee_relationships
set status = 'terminated'
where employee_number = 'Pgtap-B004-Employee';

select is(
  (select status from public.mme_employee_relationships
   where employee_number = 'Pgtap-B004-Employee'),
  'terminated',
  'employee relationship can be terminated independently'
);

select is(
  (select cr.status
   from public.mme_customer_relationships cr
   join public.mme_person_identities pi on pi.id = cr.person_identity_id
   where pi.auth_user_id = 'a1000000-0000-4000-8000-000000000004'),
  'active',
  'employee termination does not deactivate customer relationship'
);

insert into public.mme_identity_audit_events (actor_service_key, action_key, outcome)
values ('pgtap-test', 'pgtap_test_append_only', 'success');

select throws_ok(
  $$update public.mme_identity_audit_events
    set reason = 'tamper attempt'
    where action_key = 'pgtap_test_append_only'$$,
  '42501',
  'MME identity audit events are append-only',
  'audit event updates are rejected'
);

select throws_ok(
  $$delete from public.mme_identity_audit_events
    where action_key = 'pgtap_test_append_only'$$,
  '42501',
  'MME identity audit events are append-only',
  'audit event deletes are rejected'
);

select throws_ok(
  'truncate table public.mme_identity_audit_events',
  '42501',
  'MME identity audit events are append-only',
  'audit table truncation is rejected'
);

select hasnt_privilege(
  'anon', 'public.mme_person_identities', 'SELECT',
  'anonymous browser role cannot read identity rows directly'
);

select hasnt_privilege(
  'authenticated', 'public.mme_person_identities', 'SELECT',
  'authenticated browser role cannot read identity rows directly'
);

select * from finish();

rollback;
