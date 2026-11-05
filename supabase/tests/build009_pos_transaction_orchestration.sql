-- Build 009 schema contract checks on disposable local Supabase CI.
begin;
select plan(12);

select has_table('public', 'mme_pos_transactions', 'POS transaction envelope exists');
select has_table('public', 'mme_pos_transaction_events', 'POS append-only event history exists');
select has_table('public', 'mme_pos_outbox', 'POS transactional outbox exists');

select has_function(
  'public', 'mme_person_authorize_pos_action',
  array['uuid','text'],
  'Person-keyed POS permission gate exists'
);
select ok(has_function_privilege('service_role',
  'public.mme_person_authorize_pos_action(uuid,text)', 'EXECUTE'),
  'service_role can evaluate POS person authorization');

select has_function(
  'public', 'mme_pos_create_transaction',
  array['uuid','text','uuid'],
  'Idempotent POS transaction creation function exists'
);
select has_function(
  'public', 'mme_pos_append_transaction_event',
  array['uuid','bigint','text','text','uuid','text','jsonb'],
  'Revision-guarded POS event append function exists'
);

select ok(has_function_privilege('service_role',
  'public.mme_pos_create_transaction(uuid,text,uuid)', 'EXECUTE'),
  'service_role can create POS transaction envelopes');
select ok(not has_function_privilege('anon',
  'public.mme_pos_create_transaction(uuid,text,uuid)', 'EXECUTE'),
  'anon cannot create POS transactions');

select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_transactions'::regclass),
  'POS transaction table has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_transaction_events'::regclass),
  'POS event table has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_outbox'::regclass),
  'POS outbox table has RLS enabled');

select * from finish();
rollback;
