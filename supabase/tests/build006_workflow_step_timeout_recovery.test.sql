begin;
select plan(16);

select has_column('public','mme_workflow_step_runs','recovery_policy','step recovery policy is stored');
select has_column('public','mme_workflow_step_runs','recovery_reason','timeout reason is retained');
select has_column('public','mme_workflow_step_runs','compensation_status','compensation state is tracked');
select has_column('public','mme_workflow_step_runs','recovery_reviewed_at','human recovery review timestamp is available');
select has_column('public','mme_workflow_step_runs','recovery_reviewed_by','human recovery reviewer is available');

select has_function('public','mme_reap_expired_workflow_steps',array['text','integer'],
  'expired step recovery RPC exists');

select ok(not has_function_privilege('anon','public.mme_reap_expired_workflow_steps(text,integer)','execute'),
  'anonymous role cannot run step recovery');
select ok(not has_function_privilege('authenticated','public.mme_reap_expired_workflow_steps(text,integer)','execute'),
  'browser role cannot run step recovery');
select ok(has_function_privilege('service_role','public.mme_reap_expired_workflow_steps(text,integer)','execute'),
  'service role can run step recovery');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_reap_expired_workflow_steps'
     and pg_get_functiondef(p.oid) like '%worker_lease_expired%'
),'expired step reason is recorded');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_reap_expired_workflow_steps'
     and pg_get_functiondef(p.oid) like '%manual_review%'
),'uncertain side-effect steps require manual review');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_reap_expired_workflow_steps'
     and pg_get_functiondef(p.oid) like '%execution_status=''paused''%'
),'ambiguous timed-out step pauses its parent workflow');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_reap_expired_workflow_steps'
     and pg_get_functiondef(p.oid) like '%FOR UPDATE SKIP LOCKED%'
),'recovery sweep safely skips rows claimed by another transaction');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_claim_workflow_step'
     and pg_get_functiondef(p.oid) like '%attempt_count<s.max_attempts%'
),'step claim enforces the configured attempt ceiling');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_reap_expired_workflow_steps'
     and pg_get_functiondef(p.oid) like '%compensation_status%'
),'compensation status is surfaced in recovery audit');

select ok(exists (
  select 1 from pg_trigger
   where tgname='mme_workflow_step_recovery_policy_default'
     and not tgisinternal
),'step recovery defaults are applied by a database trigger');

select * from finish();
rollback;
