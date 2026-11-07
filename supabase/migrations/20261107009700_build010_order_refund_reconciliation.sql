-- Build 010.97: online order refund request and provider reconciliation ledger.
-- This is deliberately separate from POS tender refunds and does not issue provider refunds.

create table if not exists public.mme_order_refund_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.mme_orders(id) on delete restrict,
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null check (currency = 'USD'),
  reason_code text not null check (length(reason_code) between 2 and 80),
  requested_by uuid not null,
  idempotency_key text not null unique check (length(idempotency_key) between 16 and 180),
  status text not null default 'requested'
    check (status in ('requested','approved','rejected','processing','pending_provider','succeeded','failed','manual_review')),
  stripe_refund_id text unique,
  failure_code text,
  provider_status text,
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists mme_order_refund_requests_order_idx
  on public.mme_order_refund_requests(order_id, requested_at desc);

create table if not exists public.mme_order_refund_events (
  id uuid primary key default gen_random_uuid(),
  provider_event_id text not null unique,
  refund_request_id uuid references public.mme_order_refund_requests(id) on delete restrict,
  order_id uuid references public.mme_orders(id) on delete restrict,
  provider_refund_id text not null,
  event_type text not null check (event_type in ('refund.created','refund.updated','charge.refunded')),
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  provider_status text not null,
  processing_status text not null default 'received'
    check (processing_status in ('received','applied','ignored','manual_review')),
  detail_code text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists mme_order_refund_events_order_idx
  on public.mme_order_refund_events(order_id, received_at desc);

alter table public.mme_order_refund_requests enable row level security;
alter table public.mme_order_refund_events enable row level security;
revoke all on public.mme_order_refund_requests from public,anon,authenticated;
revoke all on public.mme_order_refund_events from public,anon,authenticated;
grant all on public.mme_order_refund_requests to service_role;
grant all on public.mme_order_refund_events to service_role;

create or replace function public.mme_request_order_refund(
  p_order_id uuid,
  p_amount_cents bigint,
  p_reason_code text,
  p_requested_by uuid,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_order public.mme_orders%rowtype;
  v_existing uuid;
  v_reserved bigint;
  v_refunded bigint;
  v_id uuid;
begin
  if p_order_id is null or p_amount_cents is null or p_amount_cents <= 0
     or p_reason_code is null or length(p_reason_code) not between 2 and 80
     or p_requested_by is null or p_idempotency_key is null
     or length(p_idempotency_key) not between 16 and 180 then
    raise exception 'Invalid order refund request' using errcode='22023';
  end if;

  select id into v_existing from public.mme_order_refund_requests
  where idempotency_key=p_idempotency_key;
  if found then return v_existing; end if;

  select * into v_order from public.mme_orders where id=p_order_id for update;
  if not found or v_order.status not in ('paid','partially_refunded') then
    raise exception 'Only paid orders can be refunded' using errcode='23514';
  end if;
  if v_order.stripe_payment_intent_id is null then
    raise exception 'Order has no reconciled Stripe payment' using errcode='23514';
  end if;

  select coalesce(sum(amount_cents),0) into v_reserved
  from public.mme_order_refund_requests
  where order_id=p_order_id and status in ('requested','approved','processing','pending_provider','succeeded');

  if v_reserved + p_amount_cents > v_order.total_cents then
    raise exception 'Refund amount exceeds remaining captured order balance' using errcode='23514';
  end if;

  insert into public.mme_order_refund_requests(
    order_id,amount_cents,currency,reason_code,requested_by,idempotency_key
  ) values(p_order_id,p_amount_cents,'USD',p_reason_code,p_requested_by,p_idempotency_key)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.mme_decide_order_refund(
  p_refund_request_id uuid,
  p_approver_id uuid,
  p_approve boolean,
  p_reason text
) returns text
language plpgsql security definer set search_path=''
as $$
declare v_request public.mme_order_refund_requests%rowtype;
begin
  select * into v_request from public.mme_order_refund_requests
  where id=p_refund_request_id for update;
  if not found then raise exception 'Refund request not found' using errcode='P0002'; end if;
  if p_approver_id is null or p_approver_id=v_request.requested_by then
    raise exception 'Independent refund approver required' using errcode='42501';
  end if;
  if v_request.status<>'requested' then raise exception 'Refund request already decided' using errcode='23514'; end if;
  update public.mme_order_refund_requests set
    status=case when p_approve then 'approved' else 'rejected' end,
    failure_code=case when p_approve then null else left(coalesce(p_reason,'rejected'),120) end,
    updated_at=now()
  where id=p_refund_request_id;
  return case when p_approve then 'approved' else 'rejected' end;
end;
$$;

create or replace function public.mme_bind_order_stripe_refund(
  p_refund_request_id uuid,
  p_stripe_refund_id text
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_request public.mme_order_refund_requests%rowtype;
begin
  if p_stripe_refund_id is null or p_stripe_refund_id not like 're\_%' then
    raise exception 'Invalid Stripe refund reference' using errcode='22023';
  end if;
  select * into v_request from public.mme_order_refund_requests
  where id=p_refund_request_id for update;
  if not found or v_request.status not in ('approved','processing') then return false; end if;
  if v_request.stripe_refund_id is not null and v_request.stripe_refund_id<>p_stripe_refund_id then
    raise exception 'Refund request already bound to a different Stripe refund' using errcode='23505';
  end if;
  update public.mme_order_refund_requests set stripe_refund_id=p_stripe_refund_id,
    status='pending_provider',updated_at=now() where id=p_refund_request_id;
  return true;
end;
$$;

create or replace function public.mme_reconcile_order_stripe_refund(
  p_provider_event_id text,
  p_event_type text,
  p_payload_sha256 text,
  p_refund_request_id uuid,
  p_order_id uuid,
  p_provider_refund_id text,
  p_payment_intent_id text,
  p_amount_cents bigint,
  p_currency text,
  p_provider_status text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_request public.mme_order_refund_requests%rowtype;
  v_order public.mme_orders%rowtype;
  v_existing public.mme_order_refund_events%rowtype;
  v_event_id uuid;
  v_new_total bigint;
  v_result text;
  v_detail text;
  v_request_found boolean;
begin
  if p_provider_event_id is null or length(p_provider_event_id) not between 8 and 255
     or p_event_type not in ('refund.created','refund.updated','charge.refunded')
     or p_payload_sha256 !~ '^[0-9a-f]{64}$'
     or p_provider_refund_id is null or p_provider_refund_id not like 're\_%'
     or p_payment_intent_id is null or p_payment_intent_id not like 'pi\_%'
     or p_amount_cents is null or p_amount_cents<=0
     or p_currency<>'usd'
     or p_provider_status not in ('pending','requires_action','succeeded','failed','canceled') then
    raise exception 'Invalid verified Stripe refund event' using errcode='22023';
  end if;

  select * into v_existing from public.mme_order_refund_events
  where provider_event_id=p_provider_event_id for update;
  if found then
    if v_existing.payload_sha256<>p_payload_sha256 or v_existing.provider_refund_id<>p_provider_refund_id then
      raise exception 'Stripe refund event replayed with different payload' using errcode='23505';
    end if;
    return jsonb_build_object('result','duplicate','status',v_existing.processing_status);
  end if;

  select * into v_request from public.mme_order_refund_requests
  where id=p_refund_request_id for update;
  v_request_found := found;
  select * into v_order from public.mme_orders where id=p_order_id for update;

  if not found or not coalesce(v_request_found,false) or v_request.order_id is distinct from p_order_id or
     v_order.stripe_payment_intent_id is distinct from p_payment_intent_id or
     v_request.amount_cents<>p_amount_cents or v_request.currency<>'USD' or
     v_request.stripe_refund_id is distinct from p_provider_refund_id then
    v_result:='manual_review'; v_detail:='refund_request_order_payment_or_amount_mismatch';
  elsif v_request.status not in ('pending_provider','succeeded','failed','manual_review') then
    v_result:='manual_review'; v_detail:='refund_request_not_dispatched';
  elsif p_provider_status='succeeded' then
    update public.mme_order_refund_requests set status='succeeded',provider_status=p_provider_status,
      completed_at=coalesce(completed_at,now()),updated_at=now()
    where id=p_refund_request_id;
    select coalesce(sum(amount_cents),0) into v_new_total
    from public.mme_order_refund_requests where order_id=p_order_id and status='succeeded';
    update public.mme_orders set
      status=case when v_new_total>=total_cents then 'refunded' else 'partially_refunded' end,
      updated_at=now()
    where id=p_order_id;
    v_result:='applied'; v_detail:='provider_refund_succeeded';
  elsif p_provider_status in ('failed','canceled') then
    update public.mme_order_refund_requests set status='failed',provider_status=p_provider_status,
      failure_code='stripe_refund_'||p_provider_status,updated_at=now()
    where id=p_refund_request_id;
    v_result:='applied'; v_detail:='provider_refund_not_completed';
  else
    update public.mme_order_refund_requests set status='pending_provider',provider_status=p_provider_status,updated_at=now()
    where id=p_refund_request_id;
    v_result:='applied'; v_detail:='provider_refund_pending';
  end if;

  insert into public.mme_order_refund_events(
    provider_event_id,refund_request_id,order_id,provider_refund_id,event_type,
    payload_sha256,provider_status,processing_status,detail_code,processed_at
  ) values(p_provider_event_id,p_refund_request_id,p_order_id,p_provider_refund_id,
    p_event_type,p_payload_sha256,p_provider_status,v_result,v_detail,now());
  return jsonb_build_object('result',v_result,'detail',v_detail);
end;
$$;

revoke all on function public.mme_request_order_refund(uuid,bigint,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_decide_order_refund(uuid,uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.mme_bind_order_stripe_refund(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_reconcile_order_stripe_refund(text,text,text,uuid,uuid,text,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_request_order_refund(uuid,bigint,text,uuid,text) to service_role;
grant execute on function public.mme_decide_order_refund(uuid,uuid,boolean,text) to service_role;
grant execute on function public.mme_bind_order_stripe_refund(uuid,text) to service_role;
grant execute on function public.mme_reconcile_order_stripe_refund(text,text,text,uuid,uuid,text,text,bigint,text,text) to service_role;


-- Dispatch leases make retries safe across overlapping worker invocations.
alter table public.mme_order_refund_requests
  add column if not exists dispatch_attempts integer not null default 0,
  add column if not exists next_attempt_at timestamptz not null default now(),
  add column if not exists dispatch_lease_token uuid,
  add column if not exists dispatch_lease_expires_at timestamptz;

create or replace function public.mme_claim_order_refund_dispatch(
  p_limit integer default 10,
  p_lease_seconds integer default 120
) returns table (
  refund_request_id uuid,
  order_id uuid,
  amount_cents bigint,
  reason_code text,
  idempotency_key text,
  payment_intent_id text,
  dispatch_attempt integer,
  lease_token uuid
)
language plpgsql security definer set search_path=''
as $$
begin
  if p_limit is null or p_limit<1 or p_limit>50 or p_lease_seconds is null or p_lease_seconds<30 or p_lease_seconds>600 then
    raise exception 'Invalid refund dispatch claim parameters' using errcode='22023';
  end if;
  return query
  with candidates as (
    select r.id
    from public.mme_order_refund_requests r
    where (r.status='approved' and r.next_attempt_at<=now())
       or (r.status='processing' and r.dispatch_lease_expires_at<=now())
    order by r.requested_at
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.mme_order_refund_requests r
    set status='processing',
        dispatch_attempts=r.dispatch_attempts+1,
        dispatch_lease_token=gen_random_uuid(),
        dispatch_lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
        updated_at=now()
    from candidates c
    where r.id=c.id
    returning r.*
  )
  select c.id,c.order_id,c.amount_cents,c.reason_code,c.idempotency_key,
         o.stripe_payment_intent_id,c.dispatch_attempts,c.dispatch_lease_token
  from claimed c
  join public.mme_orders o on o.id=c.order_id
  where o.stripe_payment_intent_id is not null
  order by c.requested_at;
end;
$$;

create or replace function public.mme_finish_order_refund_dispatch(
  p_refund_request_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_stripe_refund_id text default null,
  p_safe_error_code text default null
) returns text
language plpgsql security definer set search_path=''
as $$
declare v_request public.mme_order_refund_requests%rowtype;
begin
  select * into v_request from public.mme_order_refund_requests
  where id=p_refund_request_id for update;
  if not found or v_request.status<>'processing' or v_request.dispatch_lease_token is distinct from p_lease_token then
    return 'lease_lost';
  end if;

  if p_outcome='submitted' and p_stripe_refund_id like 're\_%' then
    update public.mme_order_refund_requests set
      stripe_refund_id=p_stripe_refund_id,status='pending_provider',provider_status='pending',
      dispatch_lease_token=null,dispatch_lease_expires_at=null,
      failure_code=null,updated_at=now()
    where id=p_refund_request_id;
    return 'pending_provider';
  elsif p_outcome='retry' and v_request.dispatch_attempts<8 then
    update public.mme_order_refund_requests set
      status='approved',
      next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(dispatch_attempts,6))::integer)),
      dispatch_lease_token=null,dispatch_lease_expires_at=null,
      failure_code=left(coalesce(p_safe_error_code,'PROVIDER_TEMPORARY_FAILURE'),120),
      updated_at=now()
    where id=p_refund_request_id;
    return 'retry_scheduled';
  else
    update public.mme_order_refund_requests set
      status='manual_review',
      dispatch_lease_token=null,dispatch_lease_expires_at=null,
      failure_code=left(coalesce(p_safe_error_code,'PROVIDER_REQUIRES_REVIEW'),120),
      updated_at=now()
    where id=p_refund_request_id;
    return 'manual_review';
  end if;
end;
$$;

revoke all on function public.mme_claim_order_refund_dispatch(integer,integer) from public,anon,authenticated;
revoke all on function public.mme_finish_order_refund_dispatch(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_claim_order_refund_dispatch(integer,integer) to service_role;
grant execute on function public.mme_finish_order_refund_dispatch(uuid,uuid,text,text,text) to service_role;


-- Refund approval uses the existing employee security settings and permission grants.
create or replace function public.mme_employee_authorize_order_refund_action(
  p_actor_user_id uuid,
  p_permission_key text,
  p_submitter_user_id uuid default null
) returns boolean
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_ceo uuid; v_frozen boolean; v_status text;
begin
  if p_actor_user_id is null or p_permission_key not in ('orders.refunds.view','orders.refunds.approve') then return false; end if;
  select ceo_user_id,employee_access_frozen into v_ceo,v_frozen
  from public.employee_security_settings where singleton=true;
  if not found or v_frozen is distinct from false or v_ceo is null then return false; end if;
  select employment_status into v_status from public.employee_relationships where user_id=p_actor_user_id;
  if v_status is distinct from 'active' then return false; end if;
  if p_permission_key='orders.refunds.approve' and p_submitter_user_id=p_actor_user_id then return false; end if;
  if p_actor_user_id=v_ceo then return true; end if;
  return exists (
    select 1 from public.employee_permission_grants g
    where g.employee_user_id=p_actor_user_id and g.permission_key=p_permission_key
      and g.revoked_at is null and (g.expires_at is null or g.expires_at>now())
      and g.scope='{}'::jsonb
  );
end;
$$;

create or replace function public.mme_decide_order_refund_authorized(
  p_refund_request_id uuid,
  p_approver_user_id uuid,
  p_approve boolean,
  p_reason text
) returns text
language plpgsql security definer set search_path=''
as $$
declare v_request public.mme_order_refund_requests%rowtype;
begin
  select * into v_request from public.mme_order_refund_requests where id=p_refund_request_id for update;
  if not found then raise exception 'Refund request not found' using errcode='P0002'; end if;
  if not public.mme_employee_authorize_order_refund_action(p_approver_user_id,'orders.refunds.approve',v_request.requested_by) then
    raise exception 'Employee is not authorized to approve this refund' using errcode='42501';
  end if;
  return public.mme_decide_order_refund(p_refund_request_id,p_approver_user_id,p_approve,p_reason);
end;
$$;

revoke all on function public.mme_employee_authorize_order_refund_action(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_decide_order_refund_authorized(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.mme_employee_authorize_order_refund_action(uuid,text,uuid) to service_role;
grant execute on function public.mme_decide_order_refund_authorized(uuid,uuid,boolean,text) to service_role;
