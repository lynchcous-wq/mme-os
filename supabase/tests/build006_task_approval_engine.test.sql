begin;
select plan(16);

select has_table('public','mme_task_approval_requests','approval request table exists');
select has_table('public','mme_task_approval_events','approval event history exists');
select has_column('public','mme_task_approval_requests','proposal_sha256','proposal digest is stored');
select has_column('public','mme_task_approval_requests','decided_by_user_id','decision actor is recorded');
select has_column('public','mme_task_approval_requests','expires_at','approval expiry is supported');

select ok((select relrowsecurity from pg_class where oid='public.mme_task_approval_requests'::regclass),'approval RLS is enabled');
select ok((select relforcerowsecurity from pg_class where oid='public.mme_task_approval_requests'::regclass),'approval RLS is forced');
select ok((select relrowsecurity from pg_class where oid='public.mme_task_approval_events'::regclass),'approval event RLS is enabled');

select ok(not has_table_privilege('anon','public.mme_task_approval_requests','select'),'anonymous role cannot read approval requests');
select ok(not has_table_privilege('authenticated','public.mme_task_approval_requests','select'),'browser role cannot read approval requests directly');

select has_function('public','mme_request_task_approval',array['uuid','uuid','text','jsonb','text','text','timestamp with time zone'],'approval request RPC exists');
select has_function('public','mme_decide_task_approval',array['uuid','uuid','boolean','text'],'approval decision RPC exists');
select has_function('public','mme_cancel_task_approval',array['uuid','uuid','text'],'approval cancellation RPC exists');

select ok(not has_function_privilege('authenticated','public.mme_request_task_approval(uuid,uuid,text,jsonb,text,text,timestamptz)','execute'),'browser role cannot request approval directly');
select ok(not has_function_privilege('authenticated','public.mme_decide_task_approval(uuid,uuid,boolean,text)','execute'),'browser role cannot decide approval directly');

select has_trigger('public','mme_task_approval_requests','mme_task_approval_proposal_immutable','submitted proposal fields are immutable');
select has_trigger('public','mme_task_approval_events','mme_task_approval_events_no_update_delete','approval history is append-only');

select * from finish();
rollback;
