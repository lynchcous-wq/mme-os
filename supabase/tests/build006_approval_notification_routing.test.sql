begin;
select plan(13);

select has_column('public','mme_employee_notifications','approval_request_id','approval request link is stored');
select has_column('public','mme_employee_notifications','approval_event_id','approval event link is stored');

select ok((select relrowsecurity from pg_class where oid='public.mme_employee_notifications'::regclass),'notification inbox RLS remains enabled');
select ok((select relforcerowsecurity from pg_class where oid='public.mme_employee_notifications'::regclass),'notification inbox RLS remains forced');

select has_function('public','mme_emit_approval_notification',array['uuid','uuid','bigint','text','text','text','text'],'approval notification emitter exists');
select has_trigger('public','mme_task_approval_events','mme_task_approval_event_notifications_after_insert','approval event fan-out trigger exists');

select ok(not has_function_privilege('anon','public.mme_emit_approval_notification(uuid,uuid,bigint,text,text,text,text)','execute'),'anonymous role cannot emit approval notifications');
select ok(not has_function_privilege('authenticated','public.mme_emit_approval_notification(uuid,uuid,bigint,text,text,text,text)','execute'),'browser role cannot emit approval notifications');

select ok(exists (
  select 1 from pg_constraint
   where conrelid='public.mme_employee_notifications'::regclass
     and conname='mme_employee_notifications_notification_type_check'
     and pg_get_constraintdef(oid) like '%approval_requested%'
),'notification type constraint includes approval lifecycle types');

select ok(exists (
  select 1 from pg_indexes
   where schemaname='public' and tablename='mme_employee_notifications'
     and indexname='mme_employee_notifications_approval_request_idx'
),'approval notification lookup index exists');

select has_trigger('public','mme_task_approval_requests','mme_task_approval_proposal_immutable','approval proposal immutability remains installed');
select has_trigger('public','mme_task_approval_events','mme_task_approval_events_no_update_delete','approval event history remains append-only');

select * from finish();
rollback;
