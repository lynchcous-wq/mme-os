begin;

select plan(18);

select has_function(
  'public',
  'mme_employee_permission_scope_allows',
  array['text','jsonb','jsonb'],
  'legacy-compatible scope evaluator exists'
);
select ok(
  has_function_privilege('service_role',
    'public.mme_employee_permission_scope_allows(text,jsonb,jsonb)', 'execute'),
  'service_role can execute scope evaluator'
);
select ok(
  not has_function_privilege('anon',
    'public.mme_employee_permission_scope_allows(text,jsonb,jsonb)', 'execute'),
  'anon cannot execute scope evaluator'
);
select ok(
  not has_function_privilege('authenticated',
    'public.mme_employee_permission_scope_allows(text,jsonb,jsonb)', 'execute'),
  'authenticated cannot execute scope evaluator'
);

select ok(
  public.mme_employee_permission_scope_allows(
    'inventory.inspection', '{}'::jsonb,
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'global inventory scope allows any requested target'
);
select ok(
  public.mme_employee_permission_scope_allows(
    'inventory.inspection',
    '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb,
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'inventory product-only grant matches even when request also has location'
);
select ok(
  public.mme_employee_permission_scope_allows(
    'inventory.inspection',
    '{"location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'inventory location-only grant matches even when request also has product'
);
select ok(
  not public.mme_employee_permission_scope_allows(
    'inventory.inspection',
    '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb,
    '{"product_id":"33333333-3333-4333-8333-333333333333","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'inventory product mismatch is denied'
);
select ok(
  not public.mme_employee_permission_scope_allows(
    'inventory.inspection',
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'inventory combined scope is rejected because legacy grants are product-only or location-only'
);
select ok(
  public.mme_employee_permission_scope_allows(
    'catalog',
    '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb,
    '{"product_id":"11111111-1111-4111-8111-111111111111"}'::jsonb
  ),
  'catalog product scope matches'
);
select ok(
  not public.mme_employee_permission_scope_allows(
    'catalog',
    '{"location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
    '{"product_id":"11111111-1111-4111-8111-111111111111","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'catalog does not accept location-only scope'
);
select ok(
  public.mme_employee_permission_scope_allows(
    'tasks',
    '{"department":"sales"}'::jsonb,
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'department-only task grant applies across locations in that department'
);
select ok(
  public.mme_employee_permission_scope_allows(
    'tasks',
    '{"location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'location-only task grant matches within a supplied department context'
);
select ok(
  public.mme_employee_permission_scope_allows(
    'tasks',
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'combined task scope requires both dimensions to match'
);
select ok(
  not public.mme_employee_permission_scope_allows(
    'tasks',
    '{"department":"sales"}'::jsonb,
    '{"department":"warehouse","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'task department mismatch is denied'
);
select ok(
  not public.mme_employee_permission_scope_allows(
    'tasks',
    '{"department":"sales","unexpected":"widen"}'::jsonb,
    '{"department":"sales","location_id":"22222222-2222-4222-8222-222222222222"}'::jsonb
  ),
  'unknown task scope keys are denied'
);
select ok(
  public.mme_employee_permission_scope_allows(
    'new.resource',
    '{"store_id":"mableton"}'::jsonb,
    '{"store_id":"mableton"}'::jsonb
  ),
  'unmapped resource retains strict JSON containment semantics'
);
select ok(
  not public.mme_employee_permission_scope_allows(
    'new.resource',
    '{"store_id":"mableton"}'::jsonb,
    '{"store_id":"other"}'::jsonb
  ),
  'unmapped resource containment mismatch is denied'
);

select * from finish();
rollback;
