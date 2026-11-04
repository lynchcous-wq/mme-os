begin;
select plan(7);

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_finish_workflow_execution'
     and pg_get_functiondef(p.oid) like '%v_total_steps=0 or v_incomplete_steps>0%'
),'success requires a nonempty, fully completed step set');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_finish_workflow_execution'
     and pg_get_functiondef(p.oid) like '%step_status not in (''succeeded'',''skipped'')%'
),'pending, running, failed and manual-review steps block success');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_finish_workflow_execution'
     and pg_get_functiondef(p.oid) like '%execution_status=''running''%'
),'completion still requires running execution');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_finish_workflow_execution'
     and pg_get_functiondef(p.oid) like '%locked_by<>btrim(p_worker_identity)%'
),'completion still verifies worker ownership');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_finish_workflow_execution'
     and pg_get_functiondef(p.oid) like '%v_execution.attempt_count>=v_execution.max_attempts%'
),'execution attempt ceiling remains enforced');

select ok(not has_function_privilege('authenticated',
  'public.mme_finish_workflow_execution(uuid,text,boolean,text,text,integer)','execute'),
  'authenticated users cannot directly finish workflows');

select ok(has_function_privilege('service_role',
  'public.mme_finish_workflow_execution(uuid,text,boolean,text,text,integer)','execute'),
  'service role retains execution completion permission');

select * from finish();
rollback;
