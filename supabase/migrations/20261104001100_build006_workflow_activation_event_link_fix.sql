-- Build 006 correction: lifecycle events may exist without an activation request.
-- Pause/retire are authorized lifecycle actions, not approval-request decisions.
begin;
alter table public.mme_workflow_activation_events
  alter column activation_request_id drop not null;
comment on column public.mme_workflow_activation_events.activation_request_id is
  'Nullable for direct authorized pause/retirement lifecycle events; non-null for request/decision/activation events.';
commit;
