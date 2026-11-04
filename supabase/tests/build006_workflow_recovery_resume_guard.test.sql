begin;
select plan(8);

select has_column('public','mme_workflow_executions','manual_review_resume_authorized',
  'workflow execution has one-time manual resume authorization');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_claim_workflow_executions'
     and pg_get_functiondef(p.oid) like '%manual_review_resume_authorized=true%'
),'execution claimant recognizes approved manual resume');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_claim_workflow_executions'
     and pg_get_functiondef(p.oid) like '%manual_review_resume_authorized=false%'
),'execution claimant consumes resume authorization atomically');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_claim_workflow_executions'
     and pg_get_functiondef(p.oid) like '%attempt_count<max_attempts%'
),'normal execution attempt ceiling remains in force');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%manual_review_resume_authorized=%'
),'only human recovery review sets resume authorization');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%v_next_execution_status:=''dead_letter''%'
),'abandoned workflow is placed in terminal dead-letter state');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%tasks.workflow.review%'
),'review permission remains mandatory');

select ok(not has_function_privilege('authenticated',
  'public.mme_claim_workflow_executions(text,integer,integer)','execute'),
  'browser role cannot claim workflow executions');

select * from finish();
rollback;
