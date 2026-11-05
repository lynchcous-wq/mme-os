begin;
select plan(14);

select has_column('public','mme_workflow_step_runs','recovery_resolution','human recovery outcome is stored');
select has_column('public','mme_workflow_step_runs','recovery_review_evidence','review evidence is stored');

select has_function('public','mme_review_workflow_step',array['uuid','bigint','text','text','jsonb'],
  'authorized workflow recovery review RPC exists');

select ok(not has_function_privilege('anon','public.mme_review_workflow_step(uuid,bigint,text,text,jsonb)','execute'),
  'anonymous role cannot review workflow recovery');
select ok(not has_function_privilege('authenticated','public.mme_review_workflow_step(uuid,bigint,text,text,jsonb)','execute'),
  'browser role cannot review workflow recovery');
select ok(has_function_privilege('service_role','public.mme_review_workflow_step(uuid,bigint,text,text,jsonb)','execute'),
  'service role can invoke the server-side review RPC');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%tasks.workflow.review%'
),'review requires the dedicated workflow review permission');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%created_by_user_id%'
),'workflow author is excluded from recovery review');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%attempt_count>=v_step.max_attempts%'
),'review cannot bypass exhausted retry ceiling');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%recovery_review_evidence%'
),'review evidence is persisted with the decision');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%step_abandoned_after_review%'
),'abandonment fails the parent execution with an audit reason');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and lower(pg_get_functiondef(p.oid)) like '%for update%'
),'review locks the step before changing its recovery state');

select ok(exists (
  select 1 from pg_indexes where schemaname='public'
    and tablename='mme_workflow_execution_events'
),'review decisions have a durable execution event ledger');

select ok(exists (
  select 1 from pg_constraint
   where conrelid='public.mme_workflow_step_runs'::regclass
     and conname='mme_workflow_step_runs_recovery_resolution_check'
),'recovery resolution values are constrained');

select * from finish();
rollback;
