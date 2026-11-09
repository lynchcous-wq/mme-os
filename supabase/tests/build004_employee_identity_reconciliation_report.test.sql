begin;

select plan(10);

select has_function(
  'public',
  'mme_employee_identity_reconciliation_report',
  array[]::text[],
  'read-only identity reconciliation report exists'
);

select ok(
  has_function_privilege('service_role',
    'public.mme_employee_identity_reconciliation_report()', 'execute'),
  'service_role can execute reconciliation report'
);
select ok(
  not has_function_privilege('anon',
    'public.mme_employee_identity_reconciliation_report()', 'execute'),
  'anon cannot execute reconciliation report'
);
select ok(
  not has_function_privilege('authenticated',
    'public.mme_employee_identity_reconciliation_report()', 'execute'),
  'authenticated cannot execute reconciliation report'
);

-- Legacy-only employee with a current grant: report missing Build 004 linkage
-- and permission migration review; no grant or relationship is created.
insert into auth.users (id, email)
values ('b0040000-0000-4000-8000-000000000003', 'build004-recon-legacy@example.invalid')
on conflict (id) do nothing;

insert into public.employee_relationships (user_id, employment_status, employee_number)
values ('b0040000-0000-4000-8000-000000000003', 'active', 'B004-RECON-LEGACY')
on conflict (user_id) do nothing;

insert into public.employee_permission_grants
  (employee_user_id, permission_key, granted_by_user_id, reason)
values
  ('b0040000-0000-4000-8000-000000000003',
   'catalog.approve',
   'b0040000-0000-4000-8000-000000000003',
   'Build 004 reconciliation fixture');

select is(
  (select count(*)::integer
   from public.mme_employee_identity_reconciliation_report()
   where issue_key = 'missing_build004_employee'
     and legacy_user_id = 'b0040000-0000-4000-8000-000000000003'),
  1,
  'legacy employee without Build 004 employee relationship is reported'
);

select is(
  (select count(*)::integer
   from public.mme_employee_identity_reconciliation_report()
   where issue_key = 'legacy_permissions_need_migration_review'
     and legacy_user_id = 'b0040000-0000-4000-8000-000000000003'),
  1,
  'active legacy grants without active Build 004 assignment are flagged'
);

-- A Build 004 employee with no legacy relationship is reported, not linked.
insert into auth.users (id, email)
values ('b0040000-0000-4000-8000-000000000004', 'build004-recon-new@example.invalid')
on conflict (id) do nothing;

insert into public.mme_employee_relationships
  (person_identity_id, employee_number, status)
select id, 'B004-RECON-NEW', 'active'
from public.mme_person_identities
where auth_user_id = 'b0040000-0000-4000-8000-000000000004'
on conflict (employee_number) do nothing;

select is(
  (select count(*)::integer
   from public.mme_employee_identity_reconciliation_report()
   where issue_key = 'build004_employee_without_legacy_link'
     and person_identity_id = (
       select id from public.mme_person_identities
       where auth_user_id = 'b0040000-0000-4000-8000-000000000004'
     )),
  1,
  'Build 004 employee without legacy relationship is reported'
);

-- The global legacy freeze is surfaced as a finding and is not changed by report.
update public.employee_security_settings
set employee_access_frozen = true, freeze_reason = 'Build 004 reconciliation test'
where singleton = true;

select is(
  (select count(*)::integer
   from public.mme_employee_identity_reconciliation_report()
   where issue_key = 'legacy_employee_access_frozen'),
  1,
  'global employee access freeze is reported'
);

select ok(
  (select employee_access_frozen
   from public.employee_security_settings
   where singleton = true),
  'report does not clear or modify the global freeze'
);

select is(
  (select count(*)::integer
   from public.mme_employee_identity_reconciliation_report()
   where issue_key = 'missing_person_identity'
     and legacy_user_id = 'b0040000-0000-4000-8000-000000000003'),
  0,
  'Auth trigger identity is detected for the legacy employee'
);

select * from finish();
rollback;
