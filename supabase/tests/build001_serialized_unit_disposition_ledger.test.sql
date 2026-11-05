begin;
select plan(18);

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

select has_column(
  'public',
  'mme_serialized_units',
  'unit_status',
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


select ok(
  (select a.attnotnull
   from pg_attribute a
   join pg_class c on c.oid = a.attrelid
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'mme_serialized_unit_dispositions'
     and a.attname = 'actor_identity_id'
     and not a.attisdropped),
  'disposition ledger requires a non-null acting identity'
);
select ok(
  (select a.attnotnull
   from pg_attribute a
   join pg_class c on c.oid = a.attrelid
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'mme_serialized_unit_dispositions'
     and a.attname = 'approved_by_identity_id'
     and not a.attisdropped),
  'disposition ledger requires a non-null approving identity'
);
select ok(
  (select p.prosecdef
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'mme_resolve_serialized_inspection'
     and pg_get_function_identity_arguments(p.oid) = 'p_inspection_id uuid, p_resolution text, p_condition_after text, p_reason text, p_actor_identity_id uuid, p_approved_by_identity_id uuid'),
  'serialized inspection resolver executes as a security definer'
);
select ok(
  position('p_actor_identity_id is null' in pg_get_functiondef(
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)'::regprocedure
  )) > 0,
  'resolver rejects a missing actor identity'
);
select ok(
  position('p_approved_by_identity_id is null' in pg_get_functiondef(
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)'::regprocedure
  )) > 0,
  'resolver rejects a missing approver identity'
);
select ok(
  position('p_actor_identity_id <> p_approved_by_identity_id' in pg_get_functiondef(
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)'::regprocedure
  )) > 0,
  'resolver rejects actor and approver identity mismatch'
);
select ok(
  position('for update' in lower(pg_get_functiondef(
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)'::regprocedure
  ))) > 0,
  'resolver locks inspection and serialized unit rows before changing state'
);
select ok(
  position('insert into public.mme_serialized_unit_dispositions' in lower(pg_get_functiondef(
    'public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid)'::regprocedure
  ))) > 0,
  'resolver writes the immutable disposition ledger within its transaction'
);


select throws_ok(
  $select public.mme_resolve_serialized_inspection(
    '99999999-9999-4999-8999-999999999999',
    'write_off', null, 'test reason',
    null, '22222222-2222-4222-8222-222222222222'
  )$,
  '22023',
  'Invalid serialized inspection resolution',
  'resolver rejects a null acting identity at execution time'
);
select throws_ok(
  $select public.mme_resolve_serialized_inspection(
    '99999999-9999-4999-8999-999999999999',
    'write_off', null, 'test reason',
    '11111111-1111-4111-8111-111111111111', null
  )$,
  '22023',
  'Invalid serialized inspection resolution',
  'resolver rejects a null approving identity at execution time'
);
select throws_ok(
  $select public.mme_resolve_serialized_inspection(
    '99999999-9999-4999-8999-999999999999',
    'write_off', null, 'test reason',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  )$,
  '22023',
  'Invalid serialized inspection resolution',
  'resolver rejects different actor and approver identities at execution time'
);

select * from finish();
rollback;