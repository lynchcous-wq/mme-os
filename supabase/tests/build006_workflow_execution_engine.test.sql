begin;
select plan(20);

select has_table('public','mme_workflow_definitions','versioned workflow registry exists');
select has_table('public','mme_workflow_events','durable workflow event inbox exists');
select has_table('public','mme_workflow_executions','durable execution queue exists');
select has_table('public','mme_workflow_step_runs','step execution history exists');
select has_table('public','mme_workflow_execution_events','execution audit history exists');

select has_column('public','mme_workflow_definitions','definition_sha256','workflow definition digest is stored');
select has_column('public','mme_workflow_executions','lease_expires_at','worker lease expiry is stored');
select has_column('public','mme_workflow_executions','max_attempts','bounded retry policy is stored');
select has_column('public','mme_workflow_events','idempotency_key','event deduplication key is stored');

select ok((select relrowsecurity from pg_class where oid='public.mme_workflow_definitions'::regclass),'workflow definitions RLS enabled');
select ok((select relforcerowsecurity from pg_class where oid='public.mme_workflow_definitions'::regclass),'workflow definitions RLS forced');
select ok((select relrowsecurity from pg_class where oid='public.mme_workflow_events'::regclass),'workflow event RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.mme_workflow_executions'::regclass),'execution RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.mme_workflow_step_runs'::regclass),'step run RLS enabled');

select ok(not has_table_privilege('anon','public.mme_workflow_events','select'),'anonymous role cannot read workflow events');
select ok(not has_table_privilege('authenticated','public.mme_workflow_executions','select'),'browser role cannot read executions directly');

select has_function('public','mme_register_workflow_event',array['text','integer','text','text','text','text','timestamp with time zone','text','jsonb','text','text'],'event registration RPC exists');
select has_function('public','mme_match_workflow_event',array['uuid','text'],'event matcher exists');
select has_function('public','mme_claim_workflow_executions',array['text','integer','integer'],'leased worker claim RPC exists');
select has_function('public','mme_finish_workflow_execution',array['uuid','text','boolean','text','text','integer'],'bounded execution completion RPC exists');

select * from finish();
rollback;
