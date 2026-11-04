begin;
select plan(15);

select has_table('public','mme_tasks','central task table exists');
select has_table('public','mme_task_assignments','assignment history table exists');
select has_table('public','mme_task_events','append-only task event table exists');

select has_column('public','mme_tasks','department','tasks are department-scoped');
select has_column('public','mme_tasks','location_id','tasks can be location-scoped');
select has_column('public','mme_tasks','idempotency_key','task creation supports idempotency');
select has_column('public','mme_task_assignments','ended_at','assignment history records closure');

select ok((select relrowsecurity from pg_class where oid='public.mme_tasks'::regclass),'task RLS is enabled');
select ok((select relforcerowsecurity from pg_class where oid='public.mme_tasks'::regclass),'task RLS is forced');
select ok((select relrowsecurity from pg_class where oid='public.mme_task_assignments'::regclass),'assignment RLS is enabled');

select ok(not has_table_privilege('anon','public.mme_tasks','select'),'anonymous role cannot read tasks');
select ok(not has_table_privilege('authenticated','public.mme_tasks','select'),'browser role cannot directly read tasks');
select ok(not has_table_privilege('authenticated','public.mme_task_assignments','insert'),'browser role cannot directly assign tasks');

select has_index('public','mme_task_assignments','mme_task_assignments_one_active_idx','only one active assignee is enforced per task');
select has_trigger('public','mme_task_events','mme_task_events_no_update_delete','task history has immutable-event trigger');

select * from finish();
rollback;
