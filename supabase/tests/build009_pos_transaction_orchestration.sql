-- Build 009 schema contract checks on disposable local Supabase CI.
begin;
select plan(139);

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

select has_table('public','mme_pos_refund_requests','Refund and void request ledger exists');
select has_function('public','mme_pos_request_refund_or_void',array['uuid','uuid','text','bigint','text','text','text'],'Refund and void request function exists');
select has_function('public','mme_pos_decide_refund_request',array['uuid','uuid','text','text'],'Second-person refund approval function exists');
select has_function('public','mme_pos_claim_refund_dispatch',array['integer','integer'],'Leased refund dispatch claim function exists');
select has_function('public','mme_pos_finish_refund_dispatch',array['uuid','uuid','text','text','text','text'],'Trusted refund outcome function exists');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_refund_requests'::regclass),'Refund request ledger has RLS enabled');
select ok(has_function_privilege('service_role','public.mme_pos_request_refund_or_void(uuid,uuid,text,bigint,text,text,text)','EXECUTE'),'service_role can request refunds and voids');
select ok(not has_function_privilege('authenticated','public.mme_pos_request_refund_or_void(uuid,uuid,text,bigint,text,text,text)','EXECUTE'),'authenticated cannot directly request refunds and voids');
select ok(has_function_privilege('service_role','public.mme_pos_decide_refund_request(uuid,uuid,text,text)','EXECUTE'),'service_role can record refund approval decisions');
select ok(not has_function_privilege('authenticated','public.mme_pos_decide_refund_request(uuid,uuid,text,text)','EXECUTE'),'authenticated cannot directly approve refunds');
select ok(has_function_privilege('service_role','public.mme_pos_claim_refund_dispatch(integer,integer)','EXECUTE'),'service_role can claim refund dispatch work');
select ok(not has_function_privilege('authenticated','public.mme_pos_claim_refund_dispatch(integer,integer)','EXECUTE'),'authenticated cannot claim refund dispatch work');
select ok(has_function_privilege('service_role','public.mme_pos_finish_refund_dispatch(uuid,uuid,text,text,text,text)','EXECUTE'),'service_role can record trusted refund outcomes');
select ok(not has_function_privilege('authenticated','public.mme_pos_finish_refund_dispatch(uuid,uuid,text,text,text,text)','EXECUTE'),'authenticated cannot record refund outcomes');

select has_table('public','mme_pos_provider_disputes','Provider dispute case ledger exists');
select has_table('public','mme_pos_provider_dispute_events','Provider dispute event ledger exists');
select has_function('public','mme_pos_reconcile_refund_settlement',array['uuid'],'Exact refund settlement reconciliation function exists');
select has_function('public','mme_pos_import_dispute_event',array['text','text','text','text','text','text','bigint','text','text','timestamp with time zone','timestamp with time zone','text'],'Idempotent provider dispute event import function exists');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_provider_disputes'::regclass),'Provider dispute cases have RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_provider_dispute_events'::regclass),'Provider dispute events have RLS enabled');
select ok(has_function_privilege('service_role','public.mme_pos_reconcile_refund_settlement(uuid)','EXECUTE'),'service_role can reconcile refund settlements');
select ok(not has_function_privilege('authenticated','public.mme_pos_reconcile_refund_settlement(uuid)','EXECUTE'),'authenticated cannot reconcile refund settlements');
select ok(has_function_privilege('service_role','public.mme_pos_import_dispute_event(text,text,text,text,text,text,bigint,text,text,timestamp with time zone,timestamp with time zone,text)','EXECUTE'),'service_role can import dispute events');
select ok(not has_function_privilege('authenticated','public.mme_pos_import_dispute_event(text,text,text,text,text,text,bigint,text,text,timestamp with time zone,timestamp with time zone,text)','EXECUTE'),'authenticated cannot import dispute events');

select has_table('public','mme_pos_cash_drawer_sessions','Associate cash drawer sessions exist');
select has_table('public','mme_pos_cash_drawer_movements','Cash drawer movement ledger exists');
select has_table('public','mme_pos_cash_adjustment_requests','Dual-control cash adjustment requests exist');
select has_function('public','mme_pos_authorize_drawer_action',array['uuid','text','uuid'],'Person-keyed drawer authorization exists');
select has_function('public','mme_pos_open_cash_drawer',array['text','uuid','uuid','uuid','text','bigint','text'],'Associate cash drawer opening function exists');
select has_function('public','mme_pos_record_drawer_cash_movement',array['uuid','uuid','text','bigint','text','text','text'],'Cash in/out movement function exists');
select has_function('public','mme_pos_request_cash_adjustment',array['uuid','uuid','text','bigint','text','text','text'],'Cash adjustment request function exists');
select has_function('public','mme_pos_decide_cash_adjustment',array['uuid','uuid','text','text'],'Second-person cash adjustment decision function exists');
select has_function('public','mme_pos_close_cash_drawer',array['uuid','uuid','bigint','text'],'Cash drawer closeout function exists');
select has_function('public','mme_pos_record_drawer_cash_sale',array['uuid','uuid','uuid','text'],'Captured cash tender linkage function exists');
select has_function('public','mme_pos_record_drawer_cash_refund',array['uuid','uuid','uuid','text'],'Completed cash refund linkage function exists');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_cash_drawer_sessions'::regclass),'Cash drawer sessions have RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_cash_drawer_movements'::regclass),'Cash drawer movements have RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_cash_adjustment_requests'::regclass),'Cash adjustment requests have RLS enabled');
select ok(to_regclass('public.mme_pos_one_open_drawer_per_register') is not null,'Only one open till per register is enforced');
select ok(to_regclass('public.mme_pos_one_open_drawer_per_associate') is not null,'Only one open till per associate is enforced');
select ok(has_function_privilege('service_role','public.mme_pos_authorize_drawer_action(uuid,text,uuid)','EXECUTE'),'service_role can evaluate drawer permissions');
select ok(not has_function_privilege('authenticated','public.mme_pos_authorize_drawer_action(uuid,text,uuid)','EXECUTE'),'authenticated cannot evaluate drawer permissions directly');
select ok(has_function_privilege('service_role','public.mme_pos_open_cash_drawer(text,uuid,uuid,uuid,text,bigint,text)','EXECUTE'),'service_role can open assigned cash drawers');
select ok(not has_function_privilege('authenticated','public.mme_pos_open_cash_drawer(text,uuid,uuid,uuid,text,bigint,text)','EXECUTE'),'authenticated cannot open cash drawers directly');
select ok(has_function_privilege('service_role','public.mme_pos_record_drawer_cash_movement(uuid,uuid,text,bigint,text,text,text)','EXECUTE'),'service_role can record cash movements');
select ok(not has_function_privilege('authenticated','public.mme_pos_record_drawer_cash_movement(uuid,uuid,text,bigint,text,text,text)','EXECUTE'),'authenticated cannot record cash movements directly');
select ok(has_function_privilege('service_role','public.mme_pos_request_cash_adjustment(uuid,uuid,text,bigint,text,text,text)','EXECUTE'),'service_role can request cash adjustments');
select ok(not has_function_privilege('authenticated','public.mme_pos_request_cash_adjustment(uuid,uuid,text,bigint,text,text,text)','EXECUTE'),'authenticated cannot request cash adjustments directly');
select ok(has_function_privilege('service_role','public.mme_pos_decide_cash_adjustment(uuid,uuid,text,text)','EXECUTE'),'service_role can decide cash adjustments');
select ok(not has_function_privilege('authenticated','public.mme_pos_decide_cash_adjustment(uuid,uuid,text,text)','EXECUTE'),'authenticated cannot decide cash adjustments directly');
select ok(has_function_privilege('service_role','public.mme_pos_close_cash_drawer(uuid,uuid,bigint,text)','EXECUTE'),'service_role can close cash drawers');
select ok(not has_function_privilege('authenticated','public.mme_pos_close_cash_drawer(uuid,uuid,bigint,text)','EXECUTE'),'authenticated cannot close cash drawers directly');
select ok(has_function_privilege('service_role','public.mme_pos_record_drawer_cash_sale(uuid,uuid,uuid,text)','EXECUTE'),'service_role can link captured cash sales');
select ok(not has_function_privilege('authenticated','public.mme_pos_record_drawer_cash_sale(uuid,uuid,uuid,text)','EXECUTE'),'authenticated cannot link cash sales directly');
select ok(has_function_privilege('service_role','public.mme_pos_record_drawer_cash_refund(uuid,uuid,uuid,text)','EXECUTE'),'service_role can link completed cash refunds');
select ok(not has_function_privilege('authenticated','public.mme_pos_record_drawer_cash_refund(uuid,uuid,uuid,text)','EXECUTE'),'authenticated cannot link cash refunds directly');

select has_table('public','mme_pos_register_devices','POS hardware registry exists');
select has_table('public','mme_pos_drawer_hardware_events','POS hardware event ledger exists');
select has_table('public','mme_pos_drawer_hardware_commands','POS hardware command intent history exists');
select has_table('public','mme_pos_drawer_it_incidents','POS drawer IT incident queue exists');
select has_function('public','mme_pos_authorize_hardware_action',array['uuid','text','uuid'],'Person-keyed hardware authorization exists');
select has_function('public','mme_pos_register_drawer_hardware_device',array['text','text','text','text','uuid','uuid'],'POS hardware registration function exists');
select has_function('public','mme_pos_record_drawer_hardware_command_intent',array['uuid','uuid','uuid','text','text'],'Drawer hardware command intent function exists');
select has_function('public','mme_pos_ingest_drawer_hardware_event',array['uuid','text','text','timestamp with time zone','uuid','text'],'Hardware event ingestion function exists');
select has_function('public','mme_pos_update_drawer_it_incident',array['uuid','uuid','text','text'],'IT incident workflow function exists');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_register_devices'::regclass),'POS device registry has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_drawer_hardware_events'::regclass),'POS hardware event ledger has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_drawer_hardware_commands'::regclass),'POS hardware command history has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid='public.mme_pos_drawer_it_incidents'::regclass),'POS IT incident queue has RLS enabled');
select ok(to_regclass('public.mme_pos_drawer_it_incident_event_once') is not null,'Hardware event incident creation is idempotent');
select ok(has_function_privilege('service_role','public.mme_pos_register_drawer_hardware_device(text,text,text,text,uuid,uuid)','EXECUTE'),'service_role can register POS hardware');
select ok(not has_function_privilege('authenticated','public.mme_pos_register_drawer_hardware_device(text,text,text,text,uuid,uuid)','EXECUTE'),'authenticated cannot register POS hardware directly');
select ok(has_function_privilege('service_role','public.mme_pos_record_drawer_hardware_command_intent(uuid,uuid,uuid,text,text)','EXECUTE'),'service_role can record drawer command intent');
select ok(not has_function_privilege('authenticated','public.mme_pos_record_drawer_hardware_command_intent(uuid,uuid,uuid,text,text)','EXECUTE'),'authenticated cannot record hardware command intent directly');
select ok(has_function_privilege('service_role','public.mme_pos_ingest_drawer_hardware_event(uuid,text,text,timestamp with time zone,uuid,text)','EXECUTE'),'service_role can ingest device events');
select ok(not has_function_privilege('authenticated','public.mme_pos_ingest_drawer_hardware_event(uuid,text,text,timestamp with time zone,uuid,text)','EXECUTE'),'authenticated cannot ingest device events directly');
select ok(has_function_privilege('service_role','public.mme_pos_update_drawer_it_incident(uuid,uuid,text,text)','EXECUTE'),'service_role can update IT incidents');
select ok(not has_function_privilege('authenticated','public.mme_pos_update_drawer_it_incident(uuid,uuid,text,text)','EXECUTE'),'authenticated cannot update IT incidents directly');

select has_table('public','mme_pos_hardware_provider_adapters','Hardware provider adapter metadata exists');
select has_table('public','mme_pos_hardware_pairing_challenges','Hardware pairing challenge ledger exists');
select has_function('public','mme_pos_create_hardware_pairing_challenge',array['uuid','uuid','text','timestamp with time zone'],'Hardware pairing challenge function exists');
select has_function('public','mme_pos_complete_hardware_pairing',array['uuid','text','boolean'],'Hardware pairing completion function exists');
select has_function('public','mme_pos_sweep_stale_hardware_devices',array['timestamp with time zone','integer'],'Hardware heartbeat sweep function exists');
select has_function('public','mme_pos_record_hardware_heartbeat',array['uuid','text','timestamp with time zone'],'Hardware heartbeat ingestion function exists');
select ok((select relrowsecurity from pg_class where oid='public.mme_pos_hardware_provider_adapters'::regclass),'Provider adapter metadata has RLS');
select ok((select relrowsecurity from pg_class where oid='public.mme_pos_hardware_pairing_challenges'::regclass),'Pairing challenge ledger has RLS');
select ok(has_function_privilege('service_role','public.mme_pos_create_hardware_pairing_challenge(uuid,uuid,text,timestamp with time zone)','EXECUTE'),'service_role can create pairing challenges');
select ok(not has_function_privilege('authenticated','public.mme_pos_create_hardware_pairing_challenge(uuid,uuid,text,timestamp with time zone)','EXECUTE'),'authenticated cannot create pairing challenges');
select ok(has_function_privilege('service_role','public.mme_pos_complete_hardware_pairing(uuid,text,boolean)','EXECUTE'),'service_role can complete pairing');
select ok(not has_function_privilege('authenticated','public.mme_pos_complete_hardware_pairing(uuid,text,boolean)','EXECUTE'),'authenticated cannot complete pairing');
select ok(has_function_privilege('service_role','public.mme_pos_sweep_stale_hardware_devices(timestamp with time zone,integer)','EXECUTE'),'service_role can run heartbeat sweep');
select ok(not has_function_privilege('authenticated','public.mme_pos_sweep_stale_hardware_devices(timestamp with time zone,integer)','EXECUTE'),'authenticated cannot run heartbeat sweep');
select ok(has_function_privilege('service_role','public.mme_pos_record_hardware_heartbeat(uuid,text,timestamp with time zone)','EXECUTE'),'service_role can ingest hardware heartbeat');
select ok(not has_function_privilege('authenticated','public.mme_pos_record_hardware_heartbeat(uuid,text,timestamp with time zone)','EXECUTE'),'authenticated cannot ingest hardware heartbeat');

select has_column('public','mme_pos_register_devices','paired_at','POS device pairing timestamp exists');
select has_column('public','mme_pos_register_devices','last_heartbeat_at','POS device heartbeat timestamp exists');
select has_column('public','mme_pos_register_devices','heartbeat_interval_seconds','POS heartbeat interval exists');
select ok(to_regclass('public.mme_pos_hardware_active_incident_once') is not null,'Active hardware incidents are deduplicated');
select ok(position('p_occurred_at<now()-interval ''5 minutes''' in pg_get_functiondef('public.mme_pos_record_hardware_heartbeat(uuid,text,timestamp with time zone)'::regprocedure))>0,'Heartbeat ingestion rejects stale events');
select ok(position('p_occurred_at>now()+interval ''60 seconds''' in pg_get_functiondef('public.mme_pos_record_hardware_heartbeat(uuid,text,timestamp with time zone)'::regprocedure))>0,'Heartbeat ingestion rejects future-dated events');

select * from finish();
rollback;
