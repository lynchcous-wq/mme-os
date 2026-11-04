begin;
select plan(7);

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_complete_workflow_step'
     and pg_get_functiondef(p.oid) like '%v_status:=''manual_review''%'
),'exhausted step attempts enter manual review');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_complete_workflow_step'
     and pg_get_functiondef(p.oid) like '%step_retry_limit_exhausted%'
),'exhaustion reason is recorded');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_complete_workflow_step'
     and pg_get_functiondef(p.oid) like '%execution_status=''paused''%'
),'parent execution pauses for supervisor review');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_complete_workflow_step'
     and pg_get_functiondef(p.oid) like '%compensation_status%'
),'side-effect compensation status is retained for review');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_complete_workflow_step'
     and pg_get_functiondef(p.oid) like '%v_status:=''retrying''%'
),'attempts below ceiling retain bounded retry path');

select ok(not has_function_privilege('authenticated',
  'public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)','execute'),
  'authenticated users cannot complete workflow steps directly');

select ok(has_function_privilege('service_role',
  'public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)','execute'),
  'service role retains step completion permission');

select * from finish();
rollback;
