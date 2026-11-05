begin;
select plan(9);

select has_function('public','mme_reap_expired_workflow_leases',array['text','integer'],
  'expired workflow lease recovery RPC exists');

select ok(not has_function_privilege(
  'anon','public.mme_reap_expired_workflow_leases(text,integer)','execute'
),'anonymous role cannot run lease recovery');

select ok(not has_function_privilege(
  'authenticated','public.mme_reap_expired_workflow_leases(text,integer)','execute'
),'browser role cannot run lease recovery');

select ok(has_function_privilege(
  'service_role','public.mme_reap_expired_workflow_leases(text,integer)','execute'
),'service role can run lease recovery');

select ok(exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_reap_expired_workflow_leases'
    and pg_get_function_result(p.oid)='TABLE(recovered_count integer, dead_lettered_count integer)'
),'recovery reports retry and dead-letter counts separately');

select ok(exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_reap_expired_workflow_leases'
    and pg_get_functiondef(p.oid) like '%worker_lease_expired%'
),'recovery records an explicit lease-expired reason');

select ok(exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_reap_expired_workflow_leases'
    and lower(pg_get_functiondef(p.oid)) like '%for update skip locked%'
),'recovery claims rows without blocking concurrent workers');

select ok(exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_reap_expired_workflow_leases'
    and pg_get_functiondef(p.oid) like '%dead_letter%'
),'exhausted leases are routed to dead letter');

select ok(exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mme_reap_expired_workflow_leases'
    and pg_get_functiondef(p.oid) like '%21600%'
),'retry delay has a six-hour upper bound');

select * from finish();
rollback;
