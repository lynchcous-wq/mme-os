begin;
select plan(7);

select has_table(
  'public',
  'mme_serialized_unit_dispositions',
  'serialized disposition ledger exists'
);

select has_function(
  'public',
  'mme_resolve_serialized_inspection',
  array['uuid','text','text','text','uuid','uuid'],
  'serialized inspection resolver exists'
);

select ok(
  has_column('public','mme_serialized_units','unit_status','serialized unit status remains recorded in the unit ledger'),
  'serialized unit status remains recorded in the unit ledger'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)',
    'execute'
  ),
  'anon cannot resolve serialized inspections'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)',
    'execute'
  ),
  'browser authenticated role cannot resolve serialized inspections directly'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)',
    'execute'
  ),
  'trusted server role can call the resolver after authorization'
);

select ok(
  exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='mme_serialized_unit_dispositions'
      and t.tgname='mme_serialized_unit_dispositions_immutable'
      and not t.tgisinternal
  ),
  'serialized disposition history has an immutable update/delete guard'
);

select * from finish();
rollback;