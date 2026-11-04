-- Build 006: generic task approval requests with independent approver decisions.
-- Approval decisions are recorded separately from task state; an approved request does not
-- itself execute a financial, inventory, or other business transaction.
begin;

create table public.mme_task_approval_requests (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.mme_tasks(id) on delete restrict,
  requested_by_user_id uuid not null references auth.users(id) on delete restrict,
  approval_type text not null check (approval_type ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  proposal jsonb not null default '{}'::jsonb check (jsonb_typeof(proposal) = 'object'),
  proposal_sha256 text not null check (proposal_sha256 ~ '^[0-9a-f]{64}$'),
  request_reason text not null check (length(btrim(request_reason)) between 3 and 1000),
  request_status text not null default 'pending'
    check (request_status in ('pending','approved','rejected','cancelled','expired')),
  requested_at timestamptz not null default now(),
  expires_at timestamptz,
  decided_by_user_id uuid references auth.users(id) on delete restrict,
  decided_at timestamptz,
  decision_reason text,
  check (expires_at is null or expires_at > requested_at),
  check (
    (request_status = 'pending' and decided_by_user_id is null and decided_at is null)
    or
    (request_status <> 'pending' and decided_by_user_id is not null and decided_at is not null)
  ),
  check (request_status <> 'rejected' or (decision_reason is not null and length(btrim(decision_reason)) >= 3))
);
create unique index mme_task_approval_one_pending_type_idx
  on public.mme_task_approval_requests(task_id,approval_type)
  where request_status='pending';
create index mme_task_approval_inbox_idx
  on public.mme_task_approval_requests(request_status,requested_at desc)
  where request_status='pending';
create index mme_task_approval_requester_idx
  on public.mme_task_approval_requests(requested_by_user_id,requested_at desc);

create table public.mme_task_approval_events (
  id bigint generated always as identity primary key,
  approval_request_id uuid not null references public.mme_task_approval_requests(id) on delete restrict,
  task_id uuid not null references public.mme_tasks(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('requested','approved','rejected','cancelled','expired')),
  reason text,
  proposal_sha256 text not null check (proposal_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
create index mme_task_approval_events_request_idx
  on public.mme_task_approval_events(approval_request_id,created_at);

alter table public.mme_task_approval_requests enable row level security;
alter table public.mme_task_approval_requests force row level security;
alter table public.mme_task_approval_events enable row level security;
alter table public.mme_task_approval_events force row level security;
revoke all on public.mme_task_approval_requests,public.mme_task_approval_events from public,anon,authenticated;
grant all on public.mme_task_approval_requests,public.mme_task_approval_events to service_role;

create function public.mme_request_task_approval(
  p_actor_user_id uuid,
  p_task_id uuid,
  p_approval_type text,
  p_proposal jsonb,
  p_proposal_sha256 text,
  p_reason text,
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.mme_tasks%rowtype;
  v_id uuid;
begin
  if p_actor_user_id is null or p_task_id is null
     or p_approval_type is null or p_approval_type !~ '^[a-z][a-z0-9_.-]{1,63}$'
     or p_proposal is null or jsonb_typeof(p_proposal)<>'object'
     or p_proposal_sha256 is null or p_proposal_sha256 !~ '^[0-9a-f]{64}$'
     or p_reason is null or length(btrim(p_reason)) not between 3 and 1000
     or (p_expires_at is not null and p_expires_at <= now()) then
    raise exception 'Invalid approval request' using errcode='22023';
  end if;

  select * into v_task from public.mme_tasks where id=p_task_id for update;
  if not found then raise exception 'Task not found' using errcode='P0002'; end if;

  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.approval.request',v_task.department,v_task.location_id
  ) and not exists (
    select 1 from public.mme_task_assignments a
     where a.task_id=p_task_id and a.assignee_user_id=p_actor_user_id and a.ended_at is null
  ) then
    raise exception 'Not authorized to request approval for this task' using errcode='42501';
  end if;

  insert into public.mme_task_approval_requests(
    task_id,requested_by_user_id,approval_type,proposal,proposal_sha256,request_reason,expires_at
  ) values (
    p_task_id,p_actor_user_id,p_approval_type,p_proposal,p_proposal_sha256,btrim(p_reason),p_expires_at
  ) returning id into v_id;

  insert into public.mme_task_approval_events(
    approval_request_id,task_id,actor_user_id,event_type,reason,proposal_sha256
  ) values (v_id,p_task_id,p_actor_user_id,'requested',btrim(p_reason),p_proposal_sha256);

  return v_id;
end;
$$;

create function public.mme_decide_task_approval(
  p_actor_user_id uuid,
  p_approval_request_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.mme_task_approval_requests%rowtype;
  v_task public.mme_tasks%rowtype;
  v_event_type text;
begin
  if p_actor_user_id is null or p_approval_request_id is null or p_approve is null then
    raise exception 'Invalid approval decision' using errcode='22023';
  end if;

  select * into v_request from public.mme_task_approval_requests
   where id=p_approval_request_id for update;
  if not found or v_request.request_status<>'pending' then
    raise exception 'Approval request is not pending' using errcode='55000';
  end if;

  if v_request.expires_at is not null and v_request.expires_at<=now() then
    update public.mme_task_approval_requests
       set request_status='expired',decided_by_user_id=p_actor_user_id,
           decided_at=now(),decision_reason='Expired before decision'
     where id=p_approval_request_id;
    insert into public.mme_task_approval_events(
      approval_request_id,task_id,actor_user_id,event_type,reason,proposal_sha256
    ) values (p_approval_request_id,v_request.task_id,p_actor_user_id,'expired',
              'Expired before decision',v_request.proposal_sha256);
    return false;
  end if;

  select * into v_task from public.mme_tasks where id=v_request.task_id for update;
  if not found then raise exception 'Task not found' using errcode='P0002'; end if;

  if p_actor_user_id=v_request.requested_by_user_id then
    raise exception 'Requester cannot approve or reject their own request' using errcode='42501';
  end if;

  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.approval.decide',v_task.department,v_task.location_id
  ) then
    raise exception 'Not authorized to decide approvals in this scope' using errcode='42501';
  end if;

  if not p_approve and (p_reason is null or length(btrim(p_reason))<3) then
    raise exception 'A reason is required for rejection' using errcode='22023';
  end if;

  v_event_type:=case when p_approve then 'approved' else 'rejected' end;
  update public.mme_task_approval_requests
     set request_status=case when p_approve then 'approved' else 'rejected' end,
         decided_by_user_id=p_actor_user_id,decided_at=now(),
         decision_reason=case when p_reason is null then null else left(btrim(p_reason),1000) end
   where id=p_approval_request_id;

  insert into public.mme_task_approval_events(
    approval_request_id,task_id,actor_user_id,event_type,reason,proposal_sha256
  ) values (
    p_approval_request_id,v_request.task_id,p_actor_user_id,v_event_type,
    p_reason,v_request.proposal_sha256
  );
  return true;
end;
$$;

create function public.mme_cancel_task_approval(
  p_actor_user_id uuid,
  p_approval_request_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_request public.mme_task_approval_requests%rowtype;
begin
  if p_actor_user_id is null or p_approval_request_id is null
     or p_reason is null or length(btrim(p_reason))<3 then
    raise exception 'Invalid approval cancellation' using errcode='22023';
  end if;
  select * into v_request from public.mme_task_approval_requests
   where id=p_approval_request_id for update;
  if not found or v_request.request_status<>'pending' then return false; end if;
  if p_actor_user_id<>v_request.requested_by_user_id
     and not public.mme_employee_authorize_task_action(
       p_actor_user_id,'tasks.approval.manage',
       (select department from public.mme_tasks where id=v_request.task_id),
       (select location_id from public.mme_tasks where id=v_request.task_id)
     ) then
    raise exception 'Not authorized to cancel this approval request' using errcode='42501';
  end if;

  update public.mme_task_approval_requests
     set request_status='cancelled',decided_by_user_id=p_actor_user_id,
         decided_at=now(),decision_reason=left(btrim(p_reason),1000)
   where id=p_approval_request_id;
  insert into public.mme_task_approval_events(
    approval_request_id,task_id,actor_user_id,event_type,reason,proposal_sha256
  ) values (
    p_approval_request_id,v_request.task_id,p_actor_user_id,'cancelled',
    left(btrim(p_reason),1000),v_request.proposal_sha256
  );
  return true;
end;
$$;

revoke all on function public.mme_request_task_approval(uuid,uuid,text,jsonb,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_decide_task_approval(uuid,uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.mme_cancel_task_approval(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_request_task_approval(uuid,uuid,text,jsonb,text,text,timestamptz) to service_role;
grant execute on function public.mme_decide_task_approval(uuid,uuid,boolean,text) to service_role;
grant execute on function public.mme_cancel_task_approval(uuid,uuid,text) to service_role;

comment on table public.mme_task_approval_requests is
  'Build 006 generic approval inbox. Proposal is immutable after submission by RPC contract; SHA-256 digest is supplied by trusted server and decisions are independent.';
comment on table public.mme_task_approval_events is
  'Build 006 append-only approval decision history. Approval is a recorded decision, not execution of the proposed business action.';

commit;
