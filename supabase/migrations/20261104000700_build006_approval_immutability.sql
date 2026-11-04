-- Build 006: protect submitted approval proposals and append-only decision history.
begin;

create function public.mme_guard_task_approval_request_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.task_id is distinct from old.task_id
     or new.requested_by_user_id is distinct from old.requested_by_user_id
     or new.approval_type is distinct from old.approval_type
     or new.proposal is distinct from old.proposal
     or new.proposal_sha256 is distinct from old.proposal_sha256
     or new.request_reason is distinct from old.request_reason
     or new.requested_at is distinct from old.requested_at
     or new.expires_at is distinct from old.expires_at then
    raise exception 'Submitted approval proposal is immutable';
  end if;
  return new;
end;
$$;

create trigger mme_task_approval_proposal_immutable
before update on public.mme_task_approval_requests
for each row execute function public.mme_guard_task_approval_request_update();

create function public.mme_task_approval_events_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Approval decision events are append-only';
end;
$$;

create trigger mme_task_approval_events_no_update_delete
before update or delete on public.mme_task_approval_events
for each row execute function public.mme_task_approval_events_immutable();

revoke all on function public.mme_guard_task_approval_request_update() from public,anon,authenticated;
revoke all on function public.mme_task_approval_events_immutable() from public,anon,authenticated;

comment on trigger mme_task_approval_proposal_immutable on public.mme_task_approval_requests is
  'Prevents alteration of the submitted proposal, digest, requester, task, type, reason, or expiry after creation.';
comment on trigger mme_task_approval_events_no_update_delete on public.mme_task_approval_events is
  'Prevents modification or deletion of approval decision history.';

commit;
