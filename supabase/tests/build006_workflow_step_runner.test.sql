begin;
select plan(19);

select has_column('public','mme_workflow_step_runs','idempotency_key','each step has a deterministic idempotency key');
select has_column('public','mme_workflow_step_runs','lease_expires_at','step lease expiry is stored');
select has_column('public','mme_workflow_step_runs','max_attempts','step retry ceiling is stored');
select has_column('public','mme_workflow_step_runs','available_at','step retry scheduling is stored');

select ok(exists (
  select 1 from pg_indexes where schemaname='public'
   and indexname='mme_workflow_step_idempotency_idx'
),'step idempotency keys are unique');

select ok(exists (
  select 1 from pg_indexes where schemaname='public'
   and indexname='mme_workflow_step_claim_idx'
),'step claim index exists');

select has_function('public','mme_initialize_workflow_steps',array['uuid','text'],'workflow step initialization RPC exists');
select has_function('public','mme_claim_workflow_step',array['uuid','text','integer'],'sequential step claim RPC exists');
select has_function('public','mme_complete_workflow_step',array['bigint','text','boolean','jsonb','text','text','integer'],'step completion RPC exists');

select ok(not has_function_privilege('anon','public.mme_initialize_workflow_steps(uuid,text)','execute'),'anonymous role cannot initialize workflow steps');
select ok(not has_function_privilege('authenticated','public.mme_claim_workflow_step(uuid,text,integer)','execute'),'browser role cannot claim workflow steps');
select ok(not has_function_privilege('authenticated','public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)','execute'),'browser role cannot complete workflow steps');

select ok(has_function_privilege('service_role','public.mme_initialize_workflow_steps(uuid,text)','execute'),'service role can initialize steps');
select ok(has_function_privilege('service_role','public.mme_claim_workflow_step(uuid,text,integer)','execute'),'service role can claim steps');
select ok(has_function_privilege('service_role','public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)','execute'),'service role can complete steps');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_claim_workflow_step'
     and lower(pg_get_functiondef(p.oid)) like '%for update skip locked%'
),'step claims use non-blocking row locks');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_initialize_workflow_steps'
     and pg_get_functiondef(p.oid) like '%between 1 and 100%'
),'workflow step count is bounded');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_complete_workflow_step'
     and pg_get_functiondef(p.oid) like '%idempotency_key%'
),'step outcome audit includes stable idempotency key');

select ok(exists (
  select 1 from pg_constraint
   where conrelid='public.mme_workflow_step_runs'::regclass
     and conname='mme_workflow_step_run_lock_pair_check'
),'step lease owner and lock timestamp must be set together');

select * from finish();
rollback;
