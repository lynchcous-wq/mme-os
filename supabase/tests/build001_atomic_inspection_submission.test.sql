begin;
select plan(7);

select has_function(
  'public',
  'mme_submit_serialized_inspection',
  array['text','uuid','text','text','jsonb','integer','text','text','text','text','text','text','text','text','text','uuid','uuid'],
  'atomic serialized inspection submission RPC exists'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.mme_submit_serialized_inspection(text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid)',
    'execute'
  ),
  'anon cannot submit inspections'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.mme_submit_serialized_inspection(text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid)',
    'execute'
  ),
  'authenticated browser role cannot submit directly'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.mme_submit_serialized_inspection(text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid)',
    'execute'
  ),
  'trusted server role can submit after session validation'
);

select ok(
  (select prosecdef from pg_proc where oid =
    'public.mme_submit_serialized_inspection(text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid)'::regprocedure),
  'submission RPC runs with controlled definer privileges'
);

select ok(
  position('inventory.inspection.submit' in pg_get_functiondef(
    'public.mme_submit_serialized_inspection(text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid)'::regprocedure
  )) > 0,
  'submission checks the dedicated employee permission'
);

select ok(
  position('quarantine' in pg_get_functiondef(
    'public.mme_submit_serialized_inspection(text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid)'::regprocedure
  )) > 0,
  'submitted devices remain quarantined pending manager review'
);

select * from finish();
rollback;
