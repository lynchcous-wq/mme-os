begin;
select plan(14);

select has_function('public','mme_employee_authorize_task_action',array['uuid','text','text','uuid'],'task authorization function exists');
select has_function('public','mme_create_task',array['uuid','text','text','text','uuid','text','timestamp with time zone','timestamp with time zone','integer','text','text','text'],'task creation RPC exists');
select has_function('public','mme_assign_task',array['uuid','uuid','uuid','text','jsonb'],'task assignment RPC exists');
select has_function('public','mme_transition_task',array['uuid','uuid','text','text'],'task transition RPC exists');

select ok(not has_function_privilege('anon','public.mme_employee_authorize_task_action(uuid,text,text,uuid)','execute'),'anonymous role cannot call task authorization');
select ok(not has_function_privilege('authenticated','public.mme_employee_authorize_task_action(uuid,text,text,uuid)','execute'),'browser role cannot call task authorization');
select ok(not has_function_privilege('authenticated','public.mme_create_task(uuid,text,text,text,uuid,text,timestamptz,timestamptz,integer,text,text,text)','execute'),'browser role cannot create tasks directly');
select ok(not has_function_privilege('authenticated','public.mme_assign_task(uuid,uuid,uuid,text,jsonb)','execute'),'browser role cannot assign tasks directly');
select ok(not has_function_privilege('authenticated','public.mme_transition_task(uuid,uuid,text,text)','execute'),'browser role cannot transition tasks directly');

select ok((select relrowsecurity from pg_class where oid='public.mme_tasks'::regclass),'task RLS remains enabled');
select ok((select relforcerowsecurity from pg_class where oid='public.mme_tasks'::regclass),'task RLS remains forced');
select ok((select relrowsecurity from pg_class where oid='public.mme_task_assignments'::regclass),'assignment RLS remains enabled');
select ok((select relrowsecurity from pg_class where oid='public.mme_task_events'::regclass),'task event RLS remains enabled');

select has_index('public','mme_task_assignments','mme_task_assignments_one_active_idx','one active assignment per task remains enforced');

select * from finish();
rollback;
