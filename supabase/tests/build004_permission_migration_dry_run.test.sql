begin;

select plan(15);

select has_function(
  'public',
  'mme_employee_permission_migration_dry_run',
  array[]::text[],
  'permission migration dry-run function exists'
);
select ok(
  has_function_privilege('service_role',
    'public.mme_employee_permission_migration_dry_run()', 'execute'),
  'service_role can execute permission dry run'
);
select ok(
  not has_function_privilege('anon',
    'public.mme_employee_permission_migration_dry_run()', 'execute'),
  'anon cannot execute permission dry run'
);
select ok(
  not has_function_privilege('authenticated',
    'public.mme_employee_permission_migration_dry_run()', 'execute'),
  'authenticated cannot execute permission dry run'
);

insert into auth.users (id, email)
values ('b0040000-0000-4000-8000-000000000005', 'build004-permission-dryrun@example.invalid')
on conflict (id) do nothing;

insert into public.employee_relationships
  (user_id, employment_status, employee_number)
values
  ('b0040000-0000-4000-8000-000000000005', 'active', 'B004-DRYRUN')
on conflict (user_id) do nothing;

insert into public.employee_permission_grants
  (employee_user_id, permission_key, scope, granted_by_user_id, reason)
values
  ('b0040000-0000-4000-8000-000000000005', 'inventory.inspection.submit',
   '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb,
   'b0040000-0000-4000-8000-000000000005', 'Build 004 dry-run fixture'),
  ('b0040000-0000-4000-8000-000000000005', 'catalog.approve',
   '{"product_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
   'b0040000-0000-4000-8000-000000000005', 'Build 004 dry-run fixture'),
  ('b0040000-0000-4000-8000-000000000005', 'catalog.publish',
   '{"product_id":"not-a-uuid"}'::jsonb,
   'b0040000-0000-4000-8000-000000000005', 'Build 004 dry-run fixture'),
  ('b0040000-0000-4000-8000-000000000005', 'tasks.assign',
   '{"department":"sales","location_id":"33333333-3333-4333-8333-333333333333"}'::jsonb,
   'b0040000-0000-4000-8000-000000000005', 'Build 004 dry-run fixture'),
  ('b0040000-0000-4000-8000-000000000005', 'tasks.assign',
   '{"department":"sales","unexpected":"widen"}'::jsonb,
   'b0040000-0000-4000-8000-000000000005', 'Build 004 dry-run fixture'),
  ('b0040000-0000-4000-8000-000000000005', 'finance.override',
   '{}'::jsonb,
   'b0040000-0000-4000-8000-000000000005', 'Build 004 dry-run fixture');

select is(
  (select mapping_status from public.mme_employee_permission_migration_dry_run()
   where source_permission_key = 'inventory.inspection.submit'
     and proposed_resource_key = 'inventory.inspection'
   order by source_grant_id limit 1),
  'review_required',
  'legacy grant with Auth identity but no Build 004 employee relationship requires review'
);

select is(
  (select proposed_action_key from public.mme_employee_permission_migration_dry_run()
   where source_permission_key = 'catalog.approve'
   order by source_grant_id limit 1),
  'approve',
  'catalog permission key maps to the proposed approve action'
);

select is(
  (select mapping_status from public.mme_employee_permission_migration_dry_run()
   where source_permission_key = 'catalog.publish'
   order by source_grant_id limit 1),
  'review_required',
  'malformed product UUID scope requires review'
);

select ok(
  (select review_reasons @> array[
     'legacy CEO provisioning/linkage is incomplete, CEO is not active, or global employee access is frozen; parity review required'
   ]::text[]
   from public.mme_employee_permission_migration_dry_run()
   where source_permission_key = 'catalog.approve'
   order by source_grant_id limit 1),
  'unconfigured CEO or global freeze prevents migration candidacy'
);

select is(
  (select mapping_status from public.mme_employee_permission_migration_dry_run()
   where source_permission_key = 'tasks.assign'
     and proposed_scope ? 'location_id'
   order by source_grant_id limit 1),
  'review_required',
  'task mapping remains review-required until identity linkage exists'
);

select is(
  (select review_reasons[1] from public.mme_employee_permission_migration_dry_run()
   where source_permission_key = 'tasks.assign'
     and proposed_scope ? 'unexpected'
   order by source_grant_id limit 1),
  'scope is not canonical for the proposed resource',
  'unknown task scope key is flagged'
);

select is(
  (select mapping_status from public.mme_employee_permission_migration_dry_run()
   where source_permission_key = 'finance.override'
   order by source_grant_id limit 1),
  'unsupported',
  'unknown permission key is not mapped'
);

select is(
  (select count(*)::integer
   from public.mme_employee_permission_migration_dry_run()
   where legacy_user_id = 'b0040000-0000-4000-8000-000000000005'),
  6,
  'all source grants are represented in dry-run output'
);

select ok(
  (select count(*) = 0
   from public.mme_role_assignments ra
   join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
   join public.mme_person_identities p on p.id = e.person_identity_id
   where p.auth_user_id = 'b0040000-0000-4000-8000-000000000005'),
  'dry run does not create role assignments'
);

select ok(
  (select count(*) = 6
   from public.employee_permission_grants
   where employee_user_id = 'b0040000-0000-4000-8000-000000000005'),
  'dry run leaves all legacy grants unchanged'
);

insert into auth.users (id, email)
values
  ('b0040000-0000-4000-8000-000000000006', 'build004-dryrun-ceo@example.invalid'),
  ('b0040000-0000-4000-8000-000000000007', 'build004-dryrun-candidate@example.invalid')
on conflict (id) do nothing;

insert into public.employee_relationships
  (user_id, employment_status, employee_number)
values
  ('b0040000-0000-4000-8000-000000000006', 'active', 'B004-DRYRUN-CEO'),
  ('b0040000-0000-4000-8000-000000000007', 'active', 'B004-DRYRUN-CANDIDATE')
on conflict (user_id) do nothing;

insert into public.mme_employee_relationships
  (person_identity_id, employee_number, status)
select p.id,
       case p.auth_user_id
         when 'b0040000-0000-4000-8000-000000000006'::uuid then 'B004-DRYRUN-CEO'
         else 'B004-DRYRUN-CANDIDATE'
       end,
       'active'
from public.mme_person_identities p
where p.auth_user_id in (
  'b0040000-0000-4000-8000-000000000006',
  'b0040000-0000-4000-8000-000000000007'
)
on conflict (person_identity_id) do nothing;

update public.employee_security_settings
set ceo_user_id = 'b0040000-0000-4000-8000-000000000006',
    employee_access_frozen = false,
    freeze_reason = null
where singleton = true;

insert into public.employee_permission_grants
  (employee_user_id, permission_key, scope, granted_by_user_id, reason)
values
  ('b0040000-0000-4000-8000-000000000007', 'catalog.publish', '{}'::jsonb,
   'b0040000-0000-4000-8000-000000000006', 'Build 004 dry-run positive fixture');

select is(
  (select mapping_status from public.mme_employee_permission_migration_dry_run()
   where legacy_user_id = 'b0040000-0000-4000-8000-000000000007'
     and source_permission_key = 'catalog.publish'),
  'mapping_candidate',
  'fully linked employee grant with canonical scope and active CEO controls is a mapping candidate'
);

select * from finish();
rollback;
