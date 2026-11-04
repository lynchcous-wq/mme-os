begin;
select plan(20);

select has_table('public','mme_workflow_activation_requests','activation request inbox exists');
select has_table('public','mme_workflow_activation_events','activation audit history exists');

select has_column('public','mme_workflow_activation_requests','definition_sha256','request binds exact definition digest');
select has_column('public','mme_workflow_activation_requests','requested_by_user_id','requester identity recorded');
select has_column('public','mme_workflow_activation_requests','decided_by_user_id','independent approver identity recorded');

select ok((select relrowsecurity from pg_class where oid='public.mme_workflow_activation_requests'::regclass),'activation request RLS enabled');
select ok((select relforcerowsecurity from pg_class where oid='public.mme_workflow_activation_requests'::regclass),'activation request RLS forced');
select ok((select relrowsecurity from pg_class where oid='public.mme_workflow_activation_events'::regclass),'activation event RLS enabled');

select ok(not has_table_privilege('anon','public.mme_workflow_activation_requests','select'),'anon cannot read activation requests');
select ok(not has_table_privilege('authenticated','public.mme_workflow_activation_events','select'),'authenticated cannot read activation audit directly');

select has_function('public','mme_request_workflow_activation',array['uuid','uuid','text'],'workflow activation request RPC exists');
select has_function('public','mme_decide_workflow_activation',array['uuid','uuid','boolean','text'],'workflow activation decision RPC exists');
select has_function('public','mme_activate_approved_workflow',array['uuid','uuid'],'approved activation RPC exists');
select has_function('public','mme_set_workflow_lifecycle',array['uuid','uuid','text','text'],'pause and retire RPC exists');

select ok(not has_function_privilege('authenticated','public.mme_request_workflow_activation(uuid,uuid,text)','execute'),'browser cannot request activation directly');
select ok(not has_function_privilege('authenticated','public.mme_decide_workflow_activation(uuid,uuid,boolean,text)','execute'),'browser cannot decide activation directly');

select has_trigger('public','mme_workflow_activation_events','mme_workflow_activation_events_no_update_delete','activation history is append-only');
select has_trigger('public','mme_workflow_definitions','mme_workflow_definition_immutable_after_activation','active and retired definitions are protected');

select ok(exists (
  select 1 from pg_indexes where schemaname='public'
   and indexname='mme_workflow_one_pending_activation_idx'
),'only one pending activation request per version is enforced');

select ok((select is_nullable='YES' from information_schema.columns
  where table_schema='public' and table_name='mme_workflow_activation_events'
    and column_name='activation_request_id'),
  'lifecycle events can be recorded without an activation request');

select * from finish();
rollback;
