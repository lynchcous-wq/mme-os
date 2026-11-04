-- Build 006: immutable event envelopes and execution/step audit consistency.
begin;

-- Refuse to install a misleading integrity constraint over inconsistent historical rows.
do $$
begin
  if exists (
    select 1
      from public.mme_workflow_execution_events e
      join public.mme_workflow_step_runs s on s.id=e.step_run_id
     where e.step_run_id is not null
       and e.execution_id is distinct from s.execution_id
  ) then
    raise exception 'Workflow audit integrity check failed: step_run_id belongs to another execution';
  end if;
end;
$$;

create unique index if not exists mme_workflow_step_runs_id_execution_uidx
  on public.mme_workflow_step_runs(id,execution_id);

alter table public.mme_workflow_execution_events
  drop constraint if exists mme_workflow_execution_events_step_run_id_fkey;

alter table public.mme_workflow_execution_events
  add constraint mme_workflow_execution_events_step_execution_fkey
  foreign key(step_run_id,execution_id)
  references public.mme_workflow_step_runs(id,execution_id)
  on delete restrict;

create function public.mme_guard_workflow_event_envelope()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if new.id is distinct from old.id
     or new.event_type is distinct from old.event_type
     or new.schema_version is distinct from old.schema_version
     or new.producer is distinct from old.producer
     or new.entity_type is distinct from old.entity_type
     or new.entity_id is distinct from old.entity_id
     or new.entity_version is distinct from old.entity_version
     or new.occurred_at is distinct from old.occurred_at
     or new.received_at is distinct from old.received_at
     or new.correlation_id is distinct from old.correlation_id
     or new.payload is distinct from old.payload
     or new.idempotency_key is distinct from old.idempotency_key
     or new.created_by_service is distinct from old.created_by_service then
    raise exception 'Workflow event envelope is immutable';
  end if;

  if new.processing_status is distinct from old.processing_status
     and not (old.processing_status='accepted'
       and new.processing_status in ('matched','ignored','rejected')) then
    raise exception 'Invalid workflow event processing transition';
  end if;
  return new;
end;
$$;

create trigger mme_workflow_event_envelope_immutable
before update on public.mme_workflow_events
for each row execute function public.mme_guard_workflow_event_envelope();

revoke all on function public.mme_guard_workflow_event_envelope()
  from public,anon,authenticated;

comment on constraint mme_workflow_execution_events_step_execution_fkey
  on public.mme_workflow_execution_events is
  'Ensures every non-null step_run_id belongs to the same execution_id recorded by the audit event.';
comment on function public.mme_guard_workflow_event_envelope() is
  'Protects accepted workflow event identity, source, payload and idempotency envelope; only accepted-to-terminal processing status changes are permitted.';

commit;
