begin;
select plan(15);

select has_table('public','mme_employee_notifications','employee notification inbox exists');
select has_column('public','mme_employee_notifications','recipient_user_id','notifications are recipient-bound');
select has_column('public','mme_employee_notifications','idempotency_key','notification delivery is deduplicated');
select has_column('public','mme_employee_notifications','read_at','read state is persisted');
select has_column('public','mme_employee_notifications','dismissed_at','dismissal state is persisted');

select ok((select relrowsecurity from pg_class where oid='public.mme_employee_notifications'::regclass),'notification RLS is enabled');
select ok((select relforcerowsecurity from pg_class where oid='public.mme_employee_notifications'::regclass),'notification RLS is forced');
select ok(not has_table_privilege('anon','public.mme_employee_notifications','select'),'anonymous role cannot read employee notifications');
select ok(not has_table_privilege('authenticated','public.mme_employee_notifications','select'),'browser role cannot read inbox table directly');

select has_function('public','mme_list_employee_notifications',array['uuid','integer','timestamp with time zone'],'recipient-bound inbox listing exists');
select ok(not has_function_privilege('authenticated','public.mme_list_employee_notifications(uuid,integer,timestamptz)','execute'),'browser role cannot call inbox listing RPC');
select has_function('public','mme_emit_task_notification',array['uuid','uuid','bigint','text','text','text','text'],'notification emitter exists');
select has_function('public','mme_mark_employee_notification_read',array['uuid','uuid'],'recipient-bound read RPC exists');
select has_function('public','mme_dismiss_employee_notification',array['uuid','uuid'],'recipient-bound dismiss RPC exists');
select has_trigger('public','mme_task_events','mme_task_event_notifications_after_insert','task events trigger notification fan-out');

select * from finish();
rollback;
