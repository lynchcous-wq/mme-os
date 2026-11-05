begin;
select plan(12);

select has_table('public','mme_workflow_cancellation_reconciliation_decisions',
  'cancelled-workflow reconciliation decision ledger exists');

select has_function('public','mme_record_cancelled_workflow_reconciliation_decision',
  array['uuid','bigint','text','text','jsonb'],
  'supervisor reconciliation RPC exists');

select ok((select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_record_cancelled_workflow_reconciliation_decision'),
  'reconciliation RPC is SECURITY DEFINER');

select ok((select proconfig @> array['search_path=""'] from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_record_cancelled_workflow_reconciliation_decision'),
  'reconciliation RPC pins an empty search_path');

select ok(not has_function_privilege('anon',
  'public.mme_record_cancelled_workflow_reconciliation_decision(uuid,bigint,text,text,jsonb)','execute'),
  'anonymous role cannot record a decision');

select ok(not has_function_privilege('authenticated',
  'public.mme_record_cancelled_workflow_reconciliation_decision(uuid,bigint,text,text,jsonb)','execute'),
  'browser role cannot directly record a decision');

select ok(has_function_privilege('service_role',
  'public.mme_record_cancelled_workflow_reconciliation_decision(uuid,bigint,text,text,jsonb)','execute'),
  'server service role can record a decision');

select ok(exists (
  select 1 from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname='mme_workflow_cancellation_reconciliation_decisions'
    and t.tgname='mme_workflow_cancel_recon_decision_immutable'
    and not t.tgisinternal
), 'decision ledger has an UPDATE/DELETE rejection trigger');

select ok(not has_table_privilege('service_role',
  'public.mme_workflow_cancellation_reconciliation_decisions','select')
  and not has_table_privilege('service_role',
  'public.mme_workflow_cancellation_reconciliation_decisions','insert')
  and not has_table_privilege('service_role',
  'public.mme_workflow_cancellation_reconciliation_decisions','update')
  and not has_table_privilege('service_role',
  'public.mme_workflow_cancellation_reconciliation_decisions','delete'),
  'service role cannot bypass the decision RPC or mutate the ledger directly');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname='mme_record_cancelled_workflow_reconciliation_decision'
     and pg_get_functiondef(p.oid) like '%execution_status<>''cancelled''%'
     and pg_get_functiondef(p.oid) like '%step_status<>''manual_review''%'
     and pg_get_functiondef(p.oid) like '%workflow_cancelled_during_step_execution%'
), 'decision is restricted to manual-review steps of cancelled executions');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname='mme_record_cancelled_workflow_reconciliation_decision'
     and pg_get_functiondef(p.oid) like '%tasks.workflow.review%'
     and pg_get_functiondef(p.oid) like '%created_by_user_id%'
), 'decision requires department-scoped supervisor permission and independent review');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname='mme_record_cancelled_workflow_reconciliation_decision'
     and pg_get_functiondef(p.oid) like '%step.cancellation_reconciliation_decided%'
     and pg_get_functiondef(p.oid) like '%workflow_remains_cancelled%'
     and pg_get_functiondef(p.oid) like '%retry_or_resume_authorized%'
     and pg_get_functiondef(p.oid) not like '%mme_review_workflow_step%'
), 'decision writes audit metadata and cannot invoke the workflow-resume recovery RPC');

select * from finish();
rollback;
