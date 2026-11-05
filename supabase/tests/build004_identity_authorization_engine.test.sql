begin;

select plan(34);

select has_function(
  'public',
  'mme_authorize_employee_action',
  array['uuid','text','text','jsonb'],
  'centralized employee authorization function exists'
);
select ok(
  has_function_privilege('service_role',
    'public.mme_authorize_employee_action(uuid,text,text,jsonb)', 'execute'),
  'service_role can execute authorization decision'
);
select ok(
  not has_function_privilege('anon',
    'public.mme_authorize_employee_action(uuid,text,text,jsonb)', 'execute'),
  'anon cannot execute authorization decision'
);
select ok(
  not has_function_privilege('authenticated',
    'public.mme_authorize_employee_action(uuid,text,text,jsonb)', 'execute'),
  'authenticated cannot execute authorization decision'
);

insert into auth.users (id, email)
values ('b0040000-0000-4000-8000-000000000002', 'build004-authz-test@example.invalid')
on conflict (id) do nothing;

insert into public.mme_employee_relationships
  (person_identity_id, employee_number, status)
select id, 'B004-AUTHZ-TEST', 'active'
from public.mme_person_identities
where auth_user_id = 'b0040000-0000-4000-8000-000000000002'
on conflict (employee_number) do nothing;

insert into public.employee_relationships
  (user_id, employment_status, employee_number, department)
values
  ('b0040000-0000-4000-8000-000000000002', 'active', 'B004-AUTHZ-TEST', 'sales')
on conflict (user_id) do update
  set employment_status = 'active', department = 'sales',
      terminated_at = null;

insert into auth.users (id, email)
values ('b0040000-0000-4000-8000-000000000003', 'build004-authz-ceo@example.invalid')
on conflict (id) do nothing;

insert into public.employee_relationships
  (user_id, employment_status, employee_number)
values
  ('b0040000-0000-4000-8000-000000000003', 'active', 'B004-AUTHZ-CEO')
on conflict (user_id) do nothing;

insert into public.mme_employee_relationships
  (person_identity_id, employee_number, status)
select id, 'B004-AUTHZ-CEO', 'active'
from public.mme_person_identities
where auth_user_id = 'b0040000-0000-4000-8000-000000000003'
on conflict (employee_number) do nothing;

update public.employee_security_settings
set ceo_user_id = 'b0040000-0000-4000-8000-000000000003',
    employee_access_frozen = false,
    freeze_reason = null
where singleton = true;

insert into public.mme_roles (role_key, display_name, active)
values ('build004_authz_test', 'Build 004 Authorization Test', true)
on conflict (role_key) do update set active = true;

insert into public.mme_role_assignments
  (employee_relationship_id, role_id, scope, status, effective_from)
select e.id, r.id, '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb, 'active', now() - interval '1 hour'
from public.mme_employee_relationships e
join public.mme_person_identities p on p.id = e.person_identity_id
cross join public.mme_roles r
where p.auth_user_id = 'b0040000-0000-4000-8000-000000000002'
  and r.role_key = 'build004_authz_test'
on conflict do nothing;

insert into public.mme_permission_grants
  (role_assignment_id, resource_key, action_key, scope, status)
select ra.id, 'inventory.inspection', 'submit',
       '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb, 'active'
from public.mme_role_assignments ra
join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
join public.mme_person_identities p on p.id = e.person_identity_id
join public.mme_roles r on r.id = ra.role_id
where p.auth_user_id = 'b0040000-0000-4000-8000-000000000002'
  and r.role_key = 'build004_authz_test'
  and not exists (
    select 1 from public.mme_permission_grants g
    where g.role_assignment_id = ra.id
      and g.resource_key = 'inventory.inspection'
      and g.action_key = 'submit'
  );

insert into public.mme_role_assignments
  (employee_relationship_id, role_id, scope, status, effective_from)
select e.id, r.id, '{}'::jsonb, 'active', now() - interval '1 hour'
from public.mme_employee_relationships e
join public.mme_person_identities p on p.id = e.person_identity_id
join public.mme_roles r on r.role_key = 'build004_authz_test'
where p.auth_user_id = 'b0040000-0000-4000-8000-000000000002';

insert into public.mme_permission_grants
  (role_assignment_id, resource_key, action_key, scope, status)
select ra.id, 'inventory.inspection', 'view', '{}'::jsonb, 'active'
from public.mme_role_assignments ra
join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
join public.mme_person_identities p on p.id = e.person_identity_id
where p.auth_user_id = 'b0040000-0000-4000-8000-000000000002'
  and ra.scope = '{}'::jsonb;

insert into public.products
  (id, category_id, sku, slug, name, created_by, catalog_status)
select
  '44444444-4444-4444-8444-444444444444',
  id,
  'B004-PARITY-CEO',
  'b004-parity-ceo',
  'Build 004 Catalog Parity Test',
  'b0040000-0000-4000-8000-000000000002',
  'pending_approval'
from public.product_categories
where slug = 'televisions'
on conflict (id) do update
set created_by = excluded.created_by,
    catalog_status = excluded.catalog_status,
    approved_by = null,
    approved_at = null,
    published_at = null;

insert into public.employee_permission_grants
  (employee_user_id, permission_key, scope, granted_by_user_id, reason)
values
  ('b0040000-0000-4000-8000-000000000002',
   'inventory.inspection.submit',
   '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb,
   'b0040000-0000-4000-8000-000000000003',
   'Build 004 parity test'),
  ('b0040000-0000-4000-8000-000000000002',
   'tasks.create',
   '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
   'b0040000-0000-4000-8000-000000000003',
   'Build 004 parity test');

insert into public.mme_role_assignments
  (employee_relationship_id, role_id, scope, status, effective_from)
select e.id, r.id,
       '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
       'active', now() - interval '1 hour'
from public.mme_employee_relationships e
join public.mme_person_identities p on p.id = e.person_identity_id
join public.mme_roles r on r.role_key = 'build004_authz_test'
where p.auth_user_id = 'b0040000-0000-4000-8000-000000000002';

insert into public.mme_permission_grants
  (role_assignment_id, resource_key, action_key, scope, status)
select ra.id, 'tasks', 'create',
       '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
       'active'
from public.mme_role_assignments ra
join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
join public.mme_person_identities p on p.id = e.person_identity_id
join public.mme_roles r on r.id = ra.role_id
where p.auth_user_id = 'b0040000-0000-4000-8000-000000000002'
  and r.role_key = 'build004_authz_test'
  and ra.scope = '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  and not exists (
    select 1 from public.mme_permission_grants g
    where g.role_assignment_id = ra.id and g.resource_key = 'tasks' and g.action_key = 'create'
  );

select is(
  public.mme_employee_authorize_inventory_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection.submit',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit',
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 inventory decisions agree for matching product scope'
);
select is(
  public.mme_employee_authorize_inventory_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection.submit',
    '33333333-3333-4333-8333-333333333333',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit',
    '{"product_id":"33333333-3333-4333-8333-333333333333","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 inventory decisions agree for mismatched product scope'
);
select is(
  public.mme_employee_authorize_task_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks.create', 'sales',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks', 'create',
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 task decisions agree for matching department and location'
);
select is(
  public.mme_employee_authorize_task_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks.create', 'warehouse',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks', 'create',
    '{"department":"warehouse","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 task decisions agree for department mismatch'
);

select ok(
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'view', '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'global role assignment and grant authorize across requested scopes'
);

select ok(
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'active employee with active role and matching grant is authorized'
);

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'delete', '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'missing permission grant is denied'
);

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '{"product_id":"33333333-3333-4333-8333-333333333333"}'::jsonb
  ),
  'out-of-scope request is denied'
);

update public.mme_person_identities
set security_status = 'locked',
    security_locked_at = now(),
    security_lock_reason = 'Build 004 authorization test'
where auth_user_id = 'b0040000-0000-4000-8000-000000000002';

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'whole-login security lock denies access'
);

update public.mme_person_identities
set security_status = 'active',
    security_locked_at = null,
    security_lock_reason = null,
    security_locked_by_identity_id = null
where auth_user_id = 'b0040000-0000-4000-8000-000000000002';

update public.mme_employee_relationships
set status = 'terminated'
where employee_number = 'B004-AUTHZ-TEST';

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'terminated employee is denied'
);

update public.mme_employee_relationships
set status = 'active'
where employee_number = 'B004-AUTHZ-TEST';

update public.mme_roles
set active = false
where role_key = 'build004_authz_test';

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'inactive role is denied'
);

update public.mme_roles
set active = true
where role_key = 'build004_authz_test';

update public.mme_role_assignments
set effective_until = now() - interval '1 minute'
where id = (
  select ra.id
  from public.mme_role_assignments ra
  join public.mme_employee_relationships e on e.id = ra.employee_relationship_id
  join public.mme_person_identities p on p.id = e.person_identity_id
  join public.mme_roles r on r.id = ra.role_id
  where p.auth_user_id = 'b0040000-0000-4000-8000-000000000002'
    and r.role_key = 'build004_authz_test'
    and ra.scope = '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
);

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'expired role assignment is denied'
);

select ok(
  not public.mme_authorize_employee_action(
    null, 'inventory.inspection', 'submit', '{}'::jsonb
  ),
  'null actor is denied'
);

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '[]'::jsonb
  ),
  'non-object requested scope is denied'
);

update public.employee_security_settings
set employee_access_frozen = true,
    freeze_reason = 'Build 004 authorization freeze test'
where singleton = true;

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit', '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'legacy global employee freeze denies non-CEO authorization'
);

update public.employee_security_settings
set employee_access_frozen = false,
    freeze_reason = null
where singleton = true;

select ok(
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'inventory.inspection', 'approve', '{}'::jsonb
  ),
  'provisioned active CEO retains legacy inventory inspection bypass'
);

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'crm', 'export', '{}'::jsonb
  ),
  'CEO bypass does not extend to new resource families without an explicit grant'
);

select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'catalog', 'approve', '{}'::jsonb
  ),
  'CEO catalog approval is denied without a valid product target'
);

select is(
  public.mme_employee_authorize_inventory_action(
    'b0040000-0000-4000-8000-000000000003',
    'inventory.inspection.approve',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'inventory.inspection', 'approve',
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 CEO inventory bypass decisions agree'
);
select is(
  public.mme_employee_authorize_task_action(
    'b0040000-0000-4000-8000-000000000003',
    'tasks.manage', 'sales',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'tasks', 'manage',
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 CEO task bypass decisions agree'
);

update public.employee_security_settings
set employee_access_frozen = true,
    freeze_reason = 'Build 004 CEO freeze parity test'
where singleton = true;

select is(
  public.mme_employee_authorize_inventory_action(
    'b0040000-0000-4000-8000-000000000003',
    'inventory.inspection.approve',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'inventory.inspection', 'approve',
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 both deny CEO inventory bypass during global freeze'
);
select is(
  public.mme_employee_authorize_task_action(
    'b0040000-0000-4000-8000-000000000003',
    'tasks.manage', 'sales',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'tasks', 'manage',
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 both deny CEO task bypass during global freeze'
);

update public.employee_security_settings
set employee_access_frozen = false,
    freeze_reason = null
where singleton = true;

select is(
  public.mme_employee_authorize_catalog_action(
    'b0040000-0000-4000-8000-000000000003',
    'catalog.approve',
    '44444444-4444-4444-8444-444444444444',
    null
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'catalog', 'approve',
    '{"product_id":"44444444-4444-4444-8444-444444444444"}'::jsonb
  ),
  'legacy and Build 004 CEO catalog approval decisions agree for valid pending product'
);

update public.products
set approved_by = 'b0040000-0000-4000-8000-000000000003',
    approved_at = now()
where id = '44444444-4444-4444-8444-444444444444';

select is(
  public.mme_employee_authorize_catalog_action(
    'b0040000-0000-4000-8000-000000000003',
    'catalog.publish',
    '44444444-4444-4444-8444-444444444444',
    null
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000003',
    'catalog', 'publish',
    '{"product_id":"44444444-4444-4444-8444-444444444444"}'::jsonb
  ),
  'legacy and Build 004 CEO publication decisions agree for approved pending product'
);

select ok(
  not public.mme_employee_authorize_catalog_action(
    'b0040000-0000-4000-8000-000000000002',
    'catalog.approve',
    '44444444-4444-4444-8444-444444444444',
    'b0040000-0000-4000-8000-000000000003'
  ),
  'legacy catalog engine rejects creator self-approval based on protected product row'
);
select ok(
  not public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'catalog', 'approve',
    '{"product_id":"44444444-4444-4444-8444-444444444444"}'::jsonb
  ),
  'Build 004 catalog engine rejects creator self-approval based on protected product row'
);

update public.employee_relationships
set employment_status = 'terminated',
    terminated_at = now()
where user_id = 'b0040000-0000-4000-8000-000000000002';

update public.mme_employee_relationships
set status = 'terminated'
where employee_number = 'B004-AUTHZ-TEST';

select is(
  public.mme_employee_authorize_inventory_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection.submit',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'submit',
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 both deny inventory access after employee termination'
);
select is(
  public.mme_employee_authorize_task_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks.create', 'sales',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks', 'create',
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 both deny task access after employee termination'
);

update public.employee_relationships
set employment_status = 'active',
    terminated_at = null
where user_id = 'b0040000-0000-4000-8000-000000000002';

update public.mme_employee_relationships
set status = 'active'
where employee_number = 'B004-AUTHZ-TEST';

select is(
  public.mme_employee_authorize_inventory_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection.resolve',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'inventory.inspection', 'resolve',
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 both deny inventory action without a matching grant'
);
select is(
  public.mme_employee_authorize_task_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks.delete', 'sales',
    '22222222-2222-4222-8222-222222222222'
  ),
  public.mme_authorize_employee_action(
    'b0040000-0000-4000-8000-000000000002',
    'tasks', 'delete',
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'legacy and Build 004 both deny task action without a matching grant'
);

select * from finish();
rollback;
