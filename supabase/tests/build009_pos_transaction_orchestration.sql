-- Build 009 schema contract checks on disposable local Supabase CI.
begin;
select plan(39);

select has_table('public', 'mme_pos_transactions', 'POS transaction envelope exists');
select has_table('public', 'mme_pos_transaction_events', 'POS append-only event history exists');
select has_table('public', 'mme_pos_outbox', 'POS transactional outbox exists');
select has_table('public', 'mme_pos_tender_attempts', 'Provider-neutral tender attempt ledger exists');
select has_table('public', 'mme_pos_tender_outbox', 'Tender dispatch outbox exists');
select has_table('public', 'mme_pos_provider_settlement_records', 'Provider settlement records exist');
select has_table('public', 'mme_pos_reconciliation_events', 'Reconciliation audit events exist');
select has_view('public', 'mme_pos_reconciliation_summary', 'Reconciliation summary view exists');
select has_function('public', 'mme_pos_import_settlement_record', array['text','text','text','text','text','text','bigint','text','timestamp with time zone','text'], 'Idempotent settlement import function exists');
select has_function('public', 'mme_pos_reconcile_settlement_record', array['uuid'], 'Tender reconciliation function exists');
select has_function('public', 'mme_pos_create_tender_attempt', array['uuid','uuid','text','text','bigint','text','text','text','text','text','text','text'], 'Idempotent tender intent function exists');
select has_function('public', 'mme_pos_claim_tender_dispatch', array['integer','integer'], 'Leased tender dispatch claim function exists');
select has_function('public', 'mme_pos_finish_tender_dispatch', array['uuid','uuid','text','bigint','bigint','text','text','text'], 'Trusted tender outcome function exists');
select has_function('public', 'mme_pos_retry_tender_dispatch', array['uuid','uuid','text'], 'Tender retry and dead-letter function exists');

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
select ok(has_function_privilege('service_role', 'public.mme_pos_claim_tender_dispatch(integer,integer)', 'EXECUTE'), 'service_role can claim tender dispatch work');
select ok(not has_function_privilege('authenticated', 'public.mme_pos_claim_tender_dispatch(integer,integer)', 'EXECUTE'), 'authenticated cannot claim tender dispatch work');
select ok(has_function_privilege('service_role', 'public.mme_pos_finish_tender_dispatch(uuid,uuid,text,bigint,bigint,text,text,text)', 'EXECUTE'), 'service_role can record trusted tender outcomes');
select ok(not has_function_privilege('authenticated', 'public.mme_pos_finish_tender_dispatch(uuid,uuid,text,bigint,bigint,text,text,text)', 'EXECUTE'), 'authenticated cannot record trusted tender outcomes');
select ok(has_function_privilege('service_role', 'public.mme_pos_retry_tender_dispatch(uuid,uuid,text)', 'EXECUTE'), 'service_role can schedule tender retries');
select ok(not has_function_privilege('authenticated', 'public.mme_pos_retry_tender_dispatch(uuid,uuid,text)', 'EXECUTE'), 'authenticated cannot schedule tender retries');

select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_provider_settlement_records'::regclass), 'Provider settlement records have RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_reconciliation_events'::regclass), 'Reconciliation audit events have RLS enabled');
select ok(has_function_privilege('service_role', 'public.mme_pos_import_settlement_record(text,text,text,text,text,text,bigint,text,timestamp with time zone,text)', 'EXECUTE'), 'service_role can import settlement records');
select ok(not has_function_privilege('authenticated', 'public.mme_pos_import_settlement_record(text,text,text,text,text,text,bigint,text,timestamp with time zone,text)', 'EXECUTE'), 'authenticated cannot import settlement records');
select ok(has_function_privilege('service_role', 'public.mme_pos_reconcile_settlement_record(uuid)', 'EXECUTE'), 'service_role can reconcile settlement records');
select ok(not has_function_privilege('authenticated', 'public.mme_pos_reconcile_settlement_record(uuid)', 'EXECUTE'), 'authenticated cannot reconcile settlement records');

select * from finish();
rollback;
