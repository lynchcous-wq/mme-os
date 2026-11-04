begin;
select plan(6);

select has_function('public','mme_review_workflow_step',
  array['uuid','bigint','text','text','jsonb'],
  'recovery review RPC exists after evidence gate');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%p_evidence=''{}''::jsonb%'
),'confirmation and retry reject empty evidence');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%tasks.workflow.review%'
),'review still enforces dedicated permission');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_review_workflow_step'
     and pg_get_functiondef(p.oid) like '%attempt_count>=v_step.max_attempts%'
),'retry ceiling remains enforced');

select ok(not has_function_privilege('anon',
  'public.mme_review_workflow_step(uuid,bigint,text,text,jsonb)','execute'),
  'anonymous cannot invoke recovery decision');

select ok(has_function_privilege('service_role',
  'public.mme_review_workflow_step(uuid,bigint,text,text,jsonb)','execute'),
  'server service role can invoke recovery decision');

select * from finish();
rollback;
