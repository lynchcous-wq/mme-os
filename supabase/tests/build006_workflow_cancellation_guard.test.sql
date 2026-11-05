begin;
select plan(20);

select has_function('public','mme_cancel_workflow_execution',
  array['uuid','uuid','text'],'workflow cancellation RPC exists');

select ok((select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'),
  'cancellation RPC is SECURITY DEFINER');

select ok((select proconfig @> array['search_path=""'] from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'),
  'cancellation RPC pins an empty search_path');

select ok(not has_function_privilege('anon',
  'public.mme_cancel_workflow_execution(uuid,uuid,text)','execute'),
  'anonymous role cannot execute cancellation RPC');
select ok(not has_function_privilege('authenticated',
  'public.mme_cancel_workflow_execution(uuid,uuid,text)','execute'),
  'authenticated browser role cannot execute cancellation RPC');
select ok(has_function_privilege('service_role',
  'public.mme_cancel_workflow_execution(uuid,uuid,text)','execute'),
  'server service role can execute cancellation RPC');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%tasks.workflow.review%'),
  'cancellation requires workflow review permission');
select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%Not authorized to cancel this workflow execution%'),
  'unauthorized cancellation is rejected');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%when step_status=''running'' then ''manual_review''%'),
  'in-flight steps are routed to manual review');
select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%then ''cancelled''%'),
  'not-started and retrying steps are cancelled');
select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%locked_at=null,locked_by=null,lease_expires_at=null%'),
  'step execution leases are invalidated');
select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%manual_review_resume_authorized=false%'),
  'cancelled execution cannot be resumed through manual-review authorization');
select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%execution.cancelled%'
    and pg_get_functiondef(p.oid) like '%running_steps_requiring_review%'),
  'cancellation writes an audit event with reconciliation counts');
select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%length(btrim(p_reason)) not between 3 and 1000%'
    and pg_get_functiondef(p.oid) like '%already terminal and cannot be cancelled%'),
  'reason length and terminal-state guards are enforced');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%where id=p_execution_id for update%'),
  'execution row is locked to serialize concurrent cancellation attempts');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%execution_status not in (''queued'',''running'',''paused'',''failed'')%'),
  'only nonterminal execution states may be cancelled');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%v_definition.owner_department,null%'),
  'authorization is evaluated against the workflow owner department');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%step_type in (''module_command'',''create_task'',''request_approval'',''notify'')%'
    and pg_get_functiondef(p.oid) like '%then ''manual_review''%'),
  'steps with possible external side effects are flagged for manual compensation review');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%active_execution_lease_invalidated%'
    and pg_get_functiondef(p.oid) like '%not_started_steps_cancelled%'),
  'audit event records lease invalidation and cancelled queued-step counts');

select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_cancel_workflow_execution'
    and pg_get_functiondef(p.oid) like '%execution_status=''cancelled''%'
    and pg_get_functiondef(p.oid) like '%finished_at=now()%'),
  'execution is marked terminal with a completion timestamp');

select * from finish();
rollback;
