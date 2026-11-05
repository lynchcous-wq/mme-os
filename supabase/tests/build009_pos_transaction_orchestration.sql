-- Build 009 schema contract checks. Runs only on disposable local Supabase CI.
begin;
select plan(12);

select has_table('public', 'mme_pos_transactions', 'POS transaction envelope exists');
select has_table('public', 'mme_pos_tender_allocations', 'Tender allocation reference table exists');
select has_table('public', 'mme_pos_transaction_events', 'Append-only event history exists');
select has_table('public', 'mme_pos_outbox', 'Transactional outbox exists');

select has_function(
  'public', 'mme_pos_authorize_register_action',
  array['uuid','text','uuid'],
  'POS store permission gate exists'
);
select has_function(
  'public', 'mme_pos_create_transaction',
  array['uuid','uuid','uuid','text','text'],
  'Idempotent POS transaction creation function exists'
);

select ok(
  has_function_privilege('service_role',
    'public.mme_pos_create_transaction(uuid,uuid,uuid,text,text)', 'EXECUTE'),
  'service_role can invoke POS transaction creation'
);
select ok(
  not has_function_privilege('anon',
    'public.mme_pos_create_transaction(uuid,uuid,uuid,text,text)', 'EXECUTE'),
  'anon cannot invoke POS transaction creation'
);

select ok((select c.relrowsecurity from pg_class c
  where c.oid = 'public.mme_pos_transactions'::regclass),
  'POS transaction table has row-level security enabled');
select ok((select c.relrowsecurity from pg_class c
  where c.oid = 'public.mme_pos_tender_allocations'::regclass),
  'Tender allocation table has row-level security enabled');
select ok((select c.relrowsecurity from pg_class c
  where c.oid = 'public.mme_pos_transaction_events'::regclass),
  'Transaction event table has row-level security enabled');
select ok((select c.relrowsecurity from pg_class c
  where c.oid = 'public.mme_pos_outbox'::regclass),
  'Outbox table has row-level security enabled');

select * from finish();
rollback;
