-- Build 009.41 — serialized return refund orchestration and provider outcome reconciliation.
-- Reuses Build 009.12 refund requests, approval, dispatch leases and provider outcome ledger.
-- No payment provider API is called from PostgreSQL.
begin;

create table public.mme_serialized_return_refund_links (
 id uuid primary key default gen_random_uuid(),
 return_request_id uuid not null unique references public.mme_serialized_return_requests(id) on delete restrict,
 refund_request_id uuid not null unique references public.mme_pos_refund_requests(id) on delete restrict,
 tender_attempt_id uuid not null references public.mme_pos_tender_attempts(id) on delete restrict,
 amount_minor bigint not null check(amount_minor>0),
 currency text not null check(currency ~ '^[A-Z]{3}$'),
 settlement_status text not null default 'pending'
  check(settlement_status in ('pending','matched','mismatch','unmatched','manual_review')),
 linked_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_serialized_return_refund_tender_idx
 on public.mme_serialized_return_refund_links(tender_attempt_id,linked_at desc);

create table public.mme_serialized_return_refund_events (
 id uuid primary key default gen_random_uuid(),
 return_request_id uuid not null references public.mme_serialized_return_requests(id) on delete restrict,
 refund_request_id uuid references public.mme_pos_refund_requests(id) on delete restrict,
 event_type text not null check(event_type in (
  'refund_requested','refund_approved','refund_rejected','refund_processing',
  'provider_confirmed','provider_failed','provider_outcome_unknown',
  'settlement_matched','settlement_mismatch','manual_review'
 )),
 actor_person_id uuid,
 detail_code text,
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_serialized_return_refund_events_idx
 on public.mme_serialized_return_refund_events(return_request_id,occurred_at);

alter table public.mme_serialized_return_refund_links enable row level security;
alter table public.mme_serialized_return_refund_events enable row level security;
revoke all on public.mme_serialized_return_refund_links,public.mme_serialized_return_refund_events
 from public,anon,authenticated;
grant all on public.mme_serialized_return_refund_links,public.mme_serialized_return_refund_events
 to service_role;

-- An employee with POS refund-request permission may prepare the refund only
-- after the serialized return inspection has been resolved. The existing
-- Build 009.12 RPC remains the authority for request authorization and amount
-- limits; its separate approver and dispatch worker remain mandatory.
create or replace function public.mme_pos_prepare_serialized_return_refund(
 p_return_request_id uuid,p_actor_person_id uuid,p_amount_minor bigint,
 p_reason_code text,p_reason_detail text,p_idempotency_key text
) returns table(refund_request_id uuid,request_status text,manual_review_required boolean,replayed boolean)
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_return public.mme_serialized_return_requests%rowtype;
 v_line public.mme_order_lines%rowtype;
 v_tx public.mme_pos_transactions%rowtype;
 v_attempt public.mme_pos_tender_attempts%rowtype;
 v_count integer; v_refund_id uuid; v_status text; v_replayed boolean;
 v_existing public.mme_serialized_return_refund_links%rowtype;
begin
 if p_return_request_id is null or p_actor_person_id is null
  or p_amount_minor is null or p_amount_minor<=0
  or p_reason_code is null or length(btrim(p_reason_code))=0
  or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 or length(p_idempotency_key)>128 then
  raise exception 'Invalid serialized return refund request' using errcode='22023';
 end if;
 select * into v_return from public.mme_serialized_return_requests
  where id=p_return_request_id for update;
 if not found then raise exception 'Serialized return request not found' using errcode='P0002'; end if;

 select * into v_existing from public.mme_serialized_return_refund_links
  where return_request_id=v_return.id for update;
 if found then
  if v_existing.amount_minor<>p_amount_minor then
   raise exception 'A refund is already linked to this return with a different amount' using errcode='23505';
  end if;
  select status into v_status from public.mme_pos_refund_requests where id=v_existing.refund_request_id;
  return query select v_existing.refund_request_id,v_status,false,true;
  return;
 end if;

 if v_return.status<>'inspection_resolved' or v_return.refund_status not in ('not_started','failed') then
  raise exception 'Return must have a resolved inspection and no active refund' using errcode='23514';
 end if;
 select * into v_line from public.mme_order_lines where id=v_return.order_line_id;
 if not found or v_line.quantity<>1 or p_amount_minor>v_line.line_total_cents then
  raise exception 'Refund amount must be positive and no greater than the serialized order-line value' using errcode='23514';
 end if;
 select * into v_tx from public.mme_pos_transactions where order_id=v_return.order_id;
 if not found then
  update public.mme_serialized_return_requests set status='manual_review',
   refund_status='manual_review',updated_at=now() where id=v_return.id;
  insert into public.mme_serialized_return_refund_events(return_request_id,event_type,detail_code)
   values(v_return.id,'manual_review','pos_transaction_missing');
  return query select null::uuid,'manual_review'::text,true,false;
  return;
 end if;

 select count(*) into v_count from public.mme_pos_tender_attempts a
  where a.transaction_id=v_tx.id and a.status in ('captured','partially_refunded')
   and a.captured_amount_minor>a.refunded_amount_minor;
 if v_count<>1 then
  update public.mme_serialized_return_requests set status='manual_review',
   refund_status='manual_review',updated_at=now() where id=v_return.id;
  insert into public.mme_serialized_return_refund_events(return_request_id,event_type,detail_code,event_data)
   values(v_return.id,'manual_review','split_or_missing_captured_tender',
    jsonb_build_object('eligible_tender_count',v_count));
  return query select null::uuid,'manual_review'::text,true,false;
  return;
 end if;
 select * into v_attempt from public.mme_pos_tender_attempts a
  where a.transaction_id=v_tx.id and a.status in ('captured','partially_refunded')
   and a.captured_amount_minor>a.refunded_amount_minor for update;
 if p_amount_minor>v_attempt.captured_amount_minor-v_attempt.refunded_amount_minor then
  update public.mme_serialized_return_requests set status='manual_review',
   refund_status='manual_review',updated_at=now() where id=v_return.id;
  insert into public.mme_serialized_return_refund_events(return_request_id,event_type,detail_code,event_data)
   values(v_return.id,'manual_review','refund_exceeds_single_tender_balance',
    jsonb_build_object('requested_amount_minor',p_amount_minor,
     'remaining_tender_balance_minor',v_attempt.captured_amount_minor-v_attempt.refunded_amount_minor));
  return query select null::uuid,'manual_review'::text,true,false;
  return;
 end if;

 select r.refund_request_id,r.request_status,r.replayed
  into v_refund_id,v_status,v_replayed
  from public.mme_pos_request_refund_or_void(
   v_attempt.id,p_actor_person_id,'refund',p_amount_minor,p_reason_code,
   left(coalesce(p_reason_detail,'Serialized customer return'),500),p_idempotency_key
  ) r;
 insert into public.mme_serialized_return_refund_links(
  return_request_id,refund_request_id,tender_attempt_id,amount_minor,currency
 ) values(v_return.id,v_refund_id,v_attempt.id,p_amount_minor,v_attempt.currency);
 update public.mme_serialized_return_requests set status='refund_pending',
  refund_status='pending_provider',refund_amount_cents=p_amount_minor,updated_at=now()
  where id=v_return.id;
 insert into public.mme_serialized_return_refund_events(
  return_request_id,refund_request_id,event_type,actor_person_id,detail_code,event_data
 ) values(v_return.id,v_refund_id,'refund_requested',p_actor_person_id,p_reason_code,
  jsonb_build_object('amount_minor',p_amount_minor,'currency',v_attempt.currency,
   'tender_attempt_id',v_attempt.id,'request_replayed',v_replayed));
 return query select v_refund_id,v_status,false,v_replayed;
end;
$$;

-- Mirror the existing refund approval/dispatch lifecycle into the serialized
-- return record only after the refund request receives a trusted state update.
create or replace function public.mme_pos_sync_serialized_return_refund_outcome()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_link public.mme_serialized_return_refund_links%rowtype;
begin
 if new.status is not distinct from old.status then return new; end if;
 select * into v_link from public.mme_serialized_return_refund_links
  where refund_request_id=new.id for update;
 if not found then return new; end if;

 if new.status='approved' then
  insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code)
   values(v_link.return_request_id,new.id,'refund_approved','independent_approval_recorded');
 elsif new.status='rejected' then
  update public.mme_serialized_return_requests set status='manual_review',
   refund_status='failed',updated_at=now() where id=v_link.return_request_id;
  insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code)
   values(v_link.return_request_id,new.id,'refund_rejected',coalesce(new.failure_code,'rejected'));
 elsif new.status='processing' then
  insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code)
   values(v_link.return_request_id,new.id,'refund_processing','dispatch_lease_claimed');
 elsif new.status='completed' then
  if new.request_type<>'refund' or new.provider_operation_reference is null
   or new.provider_refund_reference is null or new.amount_minor<>v_link.amount_minor
   or new.currency<>v_link.currency then
   update public.mme_serialized_return_requests set status='manual_review',
    refund_status='manual_review',updated_at=now() where id=v_link.return_request_id;
   insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code)
    values(v_link.return_request_id,new.id,'manual_review','provider_success_reference_or_amount_mismatch');
  else
   update public.mme_serialized_return_requests set status='refunded',
    refund_status='confirmed',resolved_at=now(),updated_at=now()
    where id=v_link.return_request_id and status='refund_pending';
   insert into public.mme_serialized_return_refund_events(
    return_request_id,refund_request_id,event_type,detail_code,event_data
   ) values(v_link.return_request_id,new.id,'provider_confirmed','trusted_provider_refund_confirmed',
    jsonb_build_object('provider_operation_reference',new.provider_operation_reference,
     'provider_refund_reference',new.provider_refund_reference,
     'amount_minor',new.amount_minor,'currency',new.currency));
  end if;
 elsif new.status='failed' then
  update public.mme_serialized_return_requests set status='manual_review',
   refund_status='failed',updated_at=now() where id=v_link.return_request_id;
  insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code)
   values(v_link.return_request_id,new.id,'provider_failed',coalesce(new.failure_code,'provider_refund_failed'));
 elsif new.status='unknown_reconciliation' then
  update public.mme_serialized_return_requests set status='manual_review',
   refund_status='manual_review',updated_at=now() where id=v_link.return_request_id;
  insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code)
   values(v_link.return_request_id,new.id,'provider_outcome_unknown','provider_outcome_requires_reconciliation');
 end if;
 return new;
end;
$$;
drop trigger if exists mme_pos_sync_serialized_return_refund_outcome on public.mme_pos_refund_requests;
create trigger mme_pos_sync_serialized_return_refund_outcome
after update of status on public.mme_pos_refund_requests
for each row execute function public.mme_pos_sync_serialized_return_refund_outcome();

-- Keep provider settlement matching separate from the provider's immediate
-- refund response. A settlement mismatch is visible without rewriting a
-- successfully issued customer refund.
create or replace function public.mme_pos_sync_serialized_return_refund_settlement()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_link public.mme_serialized_return_refund_links%rowtype;
begin
 if new.provider_reconciliation_status is not distinct from old.provider_reconciliation_status then return new; end if;
 select * into v_link from public.mme_serialized_return_refund_links
  where refund_request_id=new.id for update;
 if not found then return new; end if;
 update public.mme_serialized_return_refund_links set
  settlement_status=new.provider_reconciliation_status,updated_at=now()
  where id=v_link.id;
 if new.provider_reconciliation_status='matched' then
  insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code)
   values(v_link.return_request_id,new.id,'settlement_matched','provider_settlement_matched');
 elsif new.provider_reconciliation_status in ('mismatch','unmatched','manual_review') then
  insert into public.mme_serialized_return_refund_events(return_request_id,refund_request_id,event_type,detail_code,event_data)
   values(v_link.return_request_id,new.id,'settlement_mismatch',new.provider_reconciliation_status,
    jsonb_build_object('provider_reconciliation_status',new.provider_reconciliation_status));
 end if;
 return new;
end;
$$;
drop trigger if exists mme_pos_sync_serialized_return_refund_settlement on public.mme_pos_refund_requests;
create trigger mme_pos_sync_serialized_return_refund_settlement
after update of provider_reconciliation_status on public.mme_pos_refund_requests
for each row execute function public.mme_pos_sync_serialized_return_refund_settlement();

revoke all on function public.mme_pos_prepare_serialized_return_refund(uuid,uuid,bigint,text,text,text)
 from public,anon,authenticated;
revoke all on function public.mme_pos_sync_serialized_return_refund_outcome() from public,anon,authenticated;
revoke all on function public.mme_pos_sync_serialized_return_refund_settlement() from public,anon,authenticated;
grant execute on function public.mme_pos_prepare_serialized_return_refund(uuid,uuid,bigint,text,text,text)
 to service_role;

comment on table public.mme_serialized_return_refund_links is
 'One-to-one link from an inspected serialized return to the existing POS refund request and tender. Split-tender or ambiguous cases require manual review.';
comment on table public.mme_serialized_return_refund_events is
 'Append-only audit history for serialized return refund approval, dispatch, provider outcome and settlement reconciliation.';
comment on function public.mme_pos_prepare_serialized_return_refund(uuid,uuid,bigint,text,text,text) is
 'Creates an existing Build 009.12 refund request only after return inspection resolution. Requires one unambiguous captured tender; all approval and dispatch controls remain in force.';

commit;
