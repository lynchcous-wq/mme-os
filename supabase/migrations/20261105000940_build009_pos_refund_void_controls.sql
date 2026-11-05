-- Build 009.12: controlled refund and void requests with second-person approval.
-- This stores requests and trusted outcomes only; no provider calls are made here.
begin;

create table public.mme_pos_refund_requests (
  id uuid primary key default gen_random_uuid(),
  tender_attempt_id uuid not null references public.mme_pos_tender_attempts(id) on delete restrict,
  transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
  request_type text not null check (request_type in ('refund','void')),
  amount_minor bigint not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  reason_code text not null,
  reason_detail text,
  idempotency_key text not null,
  request_fingerprint text not null,
  requested_by_person_id uuid not null,
  approved_by_person_id uuid,
  status text not null default 'requested'
    check (status in ('requested','approved','rejected','processing','completed','failed','unknown_reconciliation')),
  provider_operation_reference text,
  provider_refund_reference text,
  failure_code text,
  lease_token uuid,
  lease_expires_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tender_attempt_id,idempotency_key),
  check ((request_type = 'refund' and amount_minor > 0) or (request_type = 'void' and amount_minor = 0)),
  check (approved_by_person_id is null or approved_by_person_id <> requested_by_person_id)
);

create index mme_pos_refund_queue_idx
  on public.mme_pos_refund_requests(status,created_at,lease_expires_at);

alter table public.mme_pos_refund_requests enable row level security;
revoke all on public.mme_pos_refund_requests from public,anon,authenticated;
grant all on public.mme_pos_refund_requests to service_role;

-- Extend the existing Build 004 person-keyed POS authorization gate.
create or replace function public.mme_person_authorize_pos_action(
  p_actor_person_id uuid,
  p_permission_key text,
  p_order_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_person_status text;
  v_ceo_person_id uuid;
  v_frozen boolean;
  v_employment_status text;
begin
  if p_actor_person_id is null or p_permission_key is null or p_order_id is null
     or p_permission_key not in (
       'pos.transaction.create','pos.transaction.view','pos.transaction.price','pos.tender.create',
       'pos.tender.capture','pos.tender.reconcile','pos.transaction.finalize',
       'pos.transaction.cancel','pos.refund.request','pos.refund.approve','pos.tender.void'
     ) then
    return false;
  end if;

  select lifecycle_status into v_person_status
    from public.mme_person_identities where person_id = p_actor_person_id;
  if not found or v_person_status is distinct from 'active' then return false; end if;

  select ceo_person_id, employee_access_frozen into v_ceo_person_id, v_frozen
    from public.employee_security_settings where singleton = true;
  if not found or v_frozen is distinct from false or v_ceo_person_id is null then return false; end if;

  select employment_status into v_employment_status
    from public.employee_relationships where person_id = p_actor_person_id;
  if v_employment_status is distinct from 'active' then return false; end if;

  if p_actor_person_id = v_ceo_person_id then return true; end if;

  return exists (
    select 1 from public.employee_permission_grants g
     where g.person_id = p_actor_person_id
       and g.permission_key = p_permission_key
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and exists (
         select 1 from public.mme_inventory_reservations r
         join public.mme_inventory_reservation_lines rl on rl.reservation_id = r.id
         where r.order_id = p_order_id and r.status = 'active' and r.expires_at > now()
       )
       and not exists (
         select 1 from public.mme_inventory_reservations r
         join public.mme_inventory_reservation_lines rl on rl.reservation_id = r.id
         where r.order_id = p_order_id and r.status = 'active' and r.expires_at > now()
           and g.scope <> '{}'::jsonb
           and g.scope ->> 'location_id' is distinct from rl.location_id::text
       )
  );
end;
$$;

create or replace function public.mme_pos_request_refund_or_void(
  p_tender_attempt_id uuid,
  p_actor_person_id uuid,
  p_request_type text,
  p_amount_minor bigint,
  p_reason_code text,
  p_reason_detail text,
  p_idempotency_key text
)
returns table(refund_request_id uuid, request_status text, replayed boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_attempt public.mme_pos_tender_attempts%rowtype;
  v_existing public.mme_pos_refund_requests%rowtype;
  v_pending bigint;
  v_fingerprint text;
  v_id uuid;
begin
  if p_tender_attempt_id is null or p_actor_person_id is null
     or p_request_type is null or p_request_type not in ('refund','void')
     or p_amount_minor is null
     or (p_request_type = 'refund' and p_amount_minor <= 0)
     or (p_request_type = 'void' and p_amount_minor <> 0)
     or p_reason_code is null or length(btrim(p_reason_code)) = 0
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(p_idempotency_key) > 128 then
    raise exception 'Invalid refund or void request' using errcode = '22023';
  end if;

  select * into v_attempt from public.mme_pos_tender_attempts
   where id = p_tender_attempt_id for update;
  if not found then raise exception 'Tender attempt not found' using errcode = 'P0002'; end if;

  if not public.mme_person_authorize_pos_action(
    p_actor_person_id,'pos.refund.request',
    (select order_id from public.mme_pos_transactions where id = v_attempt.transaction_id)
  ) then
    raise exception 'Refund request permission denied' using errcode = '42501';
  end if;

  v_fingerprint := md5(jsonb_build_object(
    'tender_attempt_id',p_tender_attempt_id,'request_type',p_request_type,
    'amount_minor',p_amount_minor,'reason_code',p_reason_code,
    'reason_detail',p_reason_detail
  )::text);

  select * into v_existing from public.mme_pos_refund_requests
   where tender_attempt_id = p_tender_attempt_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception 'Refund idempotency key reused with different request' using errcode = '23505';
    end if;
    return query select v_existing.id,v_existing.status,true;
    return;
  end if;

  if p_request_type = 'void' then
    if v_attempt.status <> 'authorized' or v_attempt.captured_amount_minor <> 0 then
      raise exception 'Only an uncaptured authorization can be voided' using errcode = '23514';
    end if;
    if exists (select 1 from public.mme_pos_refund_requests
      where tender_attempt_id = v_attempt.id and request_type = 'void'
        and status not in ('rejected','failed')) then
      raise exception 'A void request already exists for this authorization' using errcode = '23505';
    end if;
  else
    if v_attempt.status not in ('captured','partially_captured','partially_refunded')
       or v_attempt.captured_amount_minor <= v_attempt.refunded_amount_minor then
      raise exception 'Tender has no refundable captured balance' using errcode = '23514';
    end if;
    select coalesce(sum(amount_minor),0) into v_pending
      from public.mme_pos_refund_requests
     where tender_attempt_id = v_attempt.id and request_type = 'refund'
       and status in ('requested','approved','processing','unknown_reconciliation');
    if v_attempt.refunded_amount_minor + v_pending + p_amount_minor > v_attempt.captured_amount_minor then
      raise exception 'Refund exceeds remaining captured balance' using errcode = '23514';
    end if;
  end if;

  insert into public.mme_pos_refund_requests(
    tender_attempt_id,transaction_id,request_type,amount_minor,currency,
    reason_code,reason_detail,idempotency_key,request_fingerprint,requested_by_person_id
  ) values (
    v_attempt.id,v_attempt.transaction_id,p_request_type,p_amount_minor,v_attempt.currency,
    p_reason_code,left(p_reason_detail,500),p_idempotency_key,v_fingerprint,p_actor_person_id
  ) returning id into v_id;

  return query select v_id,'requested'::text,false;
end;
$$;

create or replace function public.mme_pos_decide_refund_request(
  p_refund_request_id uuid,
  p_approver_person_id uuid,
  p_decision text,
  p_decision_reason text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_request public.mme_pos_refund_requests%rowtype;
  v_order_id uuid;
begin
  if p_refund_request_id is null or p_approver_person_id is null
     or p_decision is null or p_decision not in ('approve','reject') then
    raise exception 'Invalid refund decision' using errcode = '22023';
  end if;
  select * into v_request from public.mme_pos_refund_requests
   where id = p_refund_request_id for update;
  if not found then raise exception 'Refund request not found' using errcode = 'P0002'; end if;
  if v_request.status <> 'requested' then
    raise exception 'Refund request is no longer awaiting approval' using errcode = '23514';
  end if;
  if v_request.requested_by_person_id = p_approver_person_id then
    raise exception 'Refund requester cannot approve their own request' using errcode = '42501';
  end if;
  select o.order_id into v_order_id
    from public.mme_pos_transactions t join public.mme_orders o on o.id=t.order_id
   where t.id=v_request.transaction_id;
  if not public.mme_person_authorize_pos_action(p_approver_person_id,'pos.refund.approve',v_order_id) then
    raise exception 'Refund approval permission denied' using errcode = '42501';
  end if;

  update public.mme_pos_refund_requests
     set status = case when p_decision='approve' then 'approved' else 'rejected' end,
         approved_by_person_id = p_approver_person_id,
         failure_code = case when p_decision='reject' then left(coalesce(p_decision_reason,'rejected'),80) else null end,
         updated_at = now()
   where id = v_request.id
  returning status into v_request.status;
  return v_request.status;
end;
$$;

create or replace function public.mme_pos_claim_refund_dispatch(
  p_limit integer default 10,
  p_lease_seconds integer default 90
)
returns table(refund_request_id uuid,tender_attempt_id uuid,request_type text,
  amount_minor bigint,currency text,provider text,provider_account_reference text,
  provider_payment_reference text,idempotency_key text,lease_token uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 50
     or p_lease_seconds is null or p_lease_seconds < 15 or p_lease_seconds > 600 then
    raise exception 'Invalid refund worker claim limits' using errcode = '22023';
  end if;
  return query
  with candidates as (
    select r.id from public.mme_pos_refund_requests r
     where r.status='approved'
        or (r.status='processing' and r.lease_expires_at < now())
     order by r.created_at
     for update skip locked limit p_limit
  ), claimed as (
    update public.mme_pos_refund_requests r
       set status='processing',attempts=r.attempts+1,
           lease_token=gen_random_uuid(),
           lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
           updated_at=now()
      from candidates c where r.id=c.id
    returning r.*
  )
  select c.id,a.id,c.request_type,c.amount_minor,c.currency,a.provider,
         a.provider_account_reference,a.provider_payment_reference,
         c.idempotency_key,c.lease_token
    from claimed c join public.mme_pos_tender_attempts a on a.id=c.tender_attempt_id;
end;
$$;

create or replace function public.mme_pos_finish_refund_dispatch(
  p_refund_request_id uuid,p_lease_token uuid,p_outcome text,
  p_provider_operation_reference text default null,
  p_provider_refund_reference text default null,
  p_failure_code text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_request public.mme_pos_refund_requests%rowtype;
  v_attempt public.mme_pos_tender_attempts%rowtype;
  v_new_refunded bigint;
  v_new_status text;
begin
  if p_refund_request_id is null or p_lease_token is null
     or p_outcome is null or p_outcome not in ('succeeded','failed','unknown_reconciliation') then
    raise exception 'Invalid refund provider outcome' using errcode = '22023';
  end if;
  select * into v_request from public.mme_pos_refund_requests
   where id=p_refund_request_id for update;
  if not found or v_request.status <> 'processing'
     or v_request.lease_token is distinct from p_lease_token
     or v_request.lease_expires_at is null or v_request.lease_expires_at < now() then
    raise exception 'Refund dispatch lease is no longer valid' using errcode = '40001';
  end if;
  select * into v_attempt from public.mme_pos_tender_attempts
   where id=v_request.tender_attempt_id for update;

  if p_outcome='succeeded' and (
     p_provider_operation_reference is null or length(btrim(p_provider_operation_reference))=0
     or p_provider_refund_reference is null or length(btrim(p_provider_refund_reference))=0
  ) then
    raise exception 'Successful refund requires provider references' using errcode = '22023';
  end if;

  if p_outcome='succeeded' then
    if v_request.request_type='refund' then
      v_new_refunded := v_attempt.refunded_amount_minor + v_request.amount_minor;
      if v_new_refunded > v_attempt.captured_amount_minor then
        raise exception 'Refund outcome exceeds captured amount' using errcode = '23514';
      end if;
      v_new_status := case when v_new_refunded=v_attempt.captured_amount_minor
        then 'refunded' else 'partially_refunded' end;
      update public.mme_pos_tender_attempts
         set refunded_amount_minor=v_new_refunded,status=v_new_status,
             updated_at=now()
       where id=v_attempt.id;
    else
      if v_attempt.captured_amount_minor<>0 or v_attempt.status<>'authorized' then
        raise exception 'Authorization is no longer voidable' using errcode = '23514';
      end if;
      update public.mme_pos_tender_attempts
         set status='voided',updated_at=now()
       where id=v_attempt.id;
    end if;
  end if;

  update public.mme_pos_refund_requests
     set status=case p_outcome when 'succeeded' then 'completed'
       when 'failed' then 'failed' else 'unknown_reconciliation' end,
         provider_operation_reference=p_provider_operation_reference,
         provider_refund_reference=p_provider_refund_reference,
         failure_code=case when p_outcome='failed' then left(p_failure_code,80) else null end,
         lease_token=null,lease_expires_at=null,updated_at=now()
   where id=v_request.id;
  return case p_outcome when 'succeeded' then 'completed'
    when 'failed' then 'failed' else 'unknown_reconciliation' end;
end;
$$;

revoke all on function public.mme_pos_request_refund_or_void(uuid,uuid,text,bigint,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_decide_refund_request(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_claim_refund_dispatch(integer,integer) from public,anon,authenticated;
revoke all on function public.mme_pos_finish_refund_dispatch(uuid,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_request_refund_or_void(uuid,uuid,text,bigint,text,text,text) to service_role;
grant execute on function public.mme_pos_decide_refund_request(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_pos_claim_refund_dispatch(integer,integer) to service_role;
grant execute on function public.mme_pos_finish_refund_dispatch(uuid,uuid,text,text,text,text) to service_role;

comment on table public.mme_pos_refund_requests is
  'Refund and void request ledger with second-person approval, bounded dispatch leases and trusted provider outcomes.';

commit;
