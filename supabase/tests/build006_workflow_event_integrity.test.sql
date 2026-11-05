begin;
select plan(7);

select ok(exists (
  select 1 from pg_constraint
   where conname='mme_workflow_execution_events_step_execution_fkey'
     and conrelid='public.mme_workflow_execution_events'::regclass
),'audit step link is constrained to the same execution');

select ok(exists (
  select 1 from pg_index
   where indexrelid='public.mme_workflow_step_runs_id_execution_uidx'::regclass
),'composite step identity index exists');

select has_function('public','mme_guard_workflow_event_envelope',array[]::text[],
  'event envelope immutability guard exists');

select ok(exists (
  select 1 from pg_trigger
   where tgname='mme_workflow_event_envelope_immutable'
     and tgrelid='public.mme_workflow_events'::regclass
     and not tgisinternal
),'event envelope update trigger is installed');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_guard_workflow_event_envelope'
     and pg_get_functiondef(p.oid) like '%old.processing_status=''accepted''%'
),'only accepted event processing state can transition');

select ok(not has_function_privilege('authenticated',
  'public.mme_guard_workflow_event_envelope()','execute'),
  'browser role cannot execute the event guard directly');

select ok(exists (
  select 1 from pg_constraint
   where conname='mme_workflow_execution_events_step_execution_fkey'
     and contype='f'
),'composite audit foreign key is a real foreign key');

select * from finish();
rollback;
