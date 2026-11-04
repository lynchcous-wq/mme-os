begin;
select plan(10);

select has_function('public','mme_list_workflow_recovery_reviews',array['uuid','integer'],
  'workflow recovery inbox RPC exists');

select ok(not has_function_privilege('anon',
  'public.mme_list_workflow_recovery_reviews(uuid,integer)','execute'),
  'anonymous role cannot read recovery inbox');
select ok(not has_function_privilege('authenticated',
  'public.mme_list_workflow_recovery_reviews(uuid,integer)','execute'),
  'browser role cannot read recovery inbox');
select ok(has_function_privilege('service_role',
  'public.mme_list_workflow_recovery_reviews(uuid,integer)','execute'),
  'service role can invoke the recovery inbox');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_list_workflow_recovery_reviews'
     and pg_get_functiondef(p.oid) like '%tasks.workflow.review%'
),'inbox filters by the dedicated workflow review permission');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_list_workflow_recovery_reviews'
     and pg_get_functiondef(p.oid) like '%step_status=''manual_review''%'
),'inbox contains only steps awaiting manual review');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_list_workflow_recovery_reviews'
     and pg_get_functiondef(p.oid) like '%execution_status=''paused''%'
),'inbox contains only paused parent executions');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_list_workflow_recovery_reviews'
     and pg_get_functiondef(p.oid) like '%between 1 and 100%'
),'inbox result limit is bounded');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_list_workflow_recovery_reviews'
     and pg_get_functiondef(p.oid) like '%audit_history%'
),'inbox includes relevant workflow audit history');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_list_workflow_recovery_reviews'
     and pg_get_functiondef(p.oid) like '%owner_department%'
),'inbox applies workflow department authorization');

select * from finish();
rollback;
