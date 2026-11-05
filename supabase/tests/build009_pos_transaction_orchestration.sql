-- Build 009 schema contract checks on disposable local Supabase CI.
begin;
select plan(19);

select has_table('public', 'mme_pos_transactions', 'POS transaction envelope exists');
select has_table('public', 'mme_pos_transaction_events', 'POS append-only event history exists');
select has_table('public', 'mme_pos_outbox', 'POS transactional outbox exists');
select has_table('public', 'mme_pos_tender_attempts', 'Provider-neutral tender attempt ledger exists');
select has_table('public', 'mme_pos_tender_outbox', 'Tender dispatch outbox exists');
select has_function('public', 'mme_pos_create_tender_attempt', array['uuid','uuid','text','text','bigint','text','text','text','text','text','text','text'], 'Idempotent tender intent function exists');

select has_function(
  'public', 'mme_person_authorize_pos_action',
  array['uuid','text','uuid'],
  'Person-keyed POS permission gate exists'
);
select ok(has_function_privilege('service_role',
  'public.mme_person_authorize_pos_action(uuid,text,uuid)', 'EXECUTE'),
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

select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_tender_attempts'::regclass), 'Tender attempt ledger has RLS enabled');
select ok(has_function_privilege('service_role', 'public.mme_pos_create_tender_attempt(uuid,uuid,text,text,bigint,text,text,text,text,text,text,text)', 'EXECUTE'), 'service_role can create tender intents');
select ok(not has_function_privilege('authenticated', 'public.mme_pos_create_tender_attempt(uuid,uuid,text,text,bigint,text,text,text,text,text,text,text)', 'EXECUTE'), 'authenticated cannot create tender intents');
select ok((select obj_description('public.mme_pos_tender_attempts'::regclass) like '%not proof%'), 'Tender intent is explicitly not payment confirmation');

select * from finish();
rollback;
