-- Build 009.42 — Stripe refund dispatch and verified webhook reconciliation.
-- Provider I/O is performed only by the authenticated server route; this migration
-- records outcomes after signature verification and exact request matching.
begin;

create table public.mme_pos_stripe_refund_webhook_events (
 id uuid primary key default gen_random_uuid(),
 provider_event_id text not null unique,
 refund_request_id uuid references public.mme_pos_refund_requests(id) on delete restrict,
 provider_refund_reference text not null,
 event_type text not null,
 payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
 processing_status text not null default 'received'
  check(processing_status in ('received','applied','ignored','manual_review')),
 detail_code text,
 received_at timestamptz not null default now(),
 processed_at timestamptz
);
create index mme_pos_stripe_refund_webhook_request_idx
 on public.mme_pos_stripe_refund_webhook_events(refund_request_id,received_at desc);
alter table public.mme_pos_stripe_refund_webhook_events enable row level security;
revoke all on public.mme_pos_stripe_refund_webhook_events from public,anon,authenticated;
grant all on public.mme_pos_stripe_refund_webhook_events to service_role;

create or replace function public.mme_pos_reconcile_stripe_refund_webhook(
 p_provider_event_id text,p_event_type text,p_payload_sha256 text,
 p_refund_request_id uuid,p_provider_account_reference text,
 p_provider_refund_reference text,p_provider_payment_reference text,
 p_amount_minor bigint,p_currency text,p_provider_status text
) returns table(processing_status text,detail_code text,replayed boolean)
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_request public.mme_pos_refund_requests%rowtype;
 v_attempt public.mme_pos_tender_attempts%rowtype;
 v_event public.mme_pos_stripe_refund_webhook_events%rowtype;
 v_new_refunded bigint;
 v_detail text;
 v_result text;
begin
 if p_provider_event_id is null or length(p_provider_event_id)>255
  or p_event_type not in ('refund.created','refund.updated')
  or p_payload_sha256 is null or p_payload_sha256 !~ '^[a-f0-9]{64}$'
  or p_refund_request_id is null or p_provider_account_reference is null
  or p_provider_refund_reference is null or p_provider_payment_reference is null
  or p_amount_minor is null or p_amount_minor<=0
  or p_currency is null or p_currency !~ '^[A-Z]{3}$'
  or p_provider_status not in ('pending','requires_action','succeeded','failed') then
  raise exception 'Invalid verified Stripe refund event' using errcode='22023';
 end if;

 select * into v_event from public.mme_pos_stripe_refund_webhook_events
  where provider_event_id=p_provider_event_id for update;
 if found then
  if v_event.payload_sha256<>p_payload_sha256 or v_event.provider_refund_reference<>p_provider_refund_reference then
   raise exception 'Stripe event ID reused with different payload' using errcode='23505';
  end if;
  return query select v_event.processing_status,v_event.detail_code,true;
  return;
 end if;

 select * into v_request from public.mme_pos_refund_requests
  where id=p_refund_request_id for update;
 if not found then
  insert into public.mme_pos_stripe_refund_webhook_events(
   provider_event_id,event_type,payload_sha256,provider_refund_reference,processing_status,detail_code,processed_at
  ) values(p_provider_event_id,p_event_type,p_payload_sha256,p_provider_refund_reference,'manual_review','refund_request_not_found',now());
  return query select 'manual_review'::text,'refund_request_not_found'::text,false;
  return;
 end if;
 select * into v_attempt from public.mme_pos_tender_attempts
  where id=v_request.tender_attempt_id for update;

 v_detail:=case
  when v_request.request_type<>'refund' then 'request_is_not_refund'
  when v_attempt.provider<>'stripe' then 'provider_mismatch'
  when v_attempt.provider_account_reference<>p_provider_account_reference then 'connected_account_mismatch'
  when v_attempt.provider_payment_reference<>p_provider_payment_reference then 'payment_intent_mismatch'
  when v_request.amount_minor<>p_amount_minor or v_request.currency<>p_currency then 'refund_amount_or_currency_mismatch'
  else null end;

 if v_detail is not null then
  v_result:='manual_review';
 elsif v_request.status='completed' then
  if v_request.provider_refund_reference=p_provider_refund_reference then
   v_result:='applied'; v_detail:='already_confirmed';
  else
   v_result:='manual_review'; v_detail:='conflicting_completed_refund_reference';
  end if;
 elsif v_request.status not in ('processing','unknown_reconciliation') then
  v_result:='manual_review'; v_detail:='refund_request_not_in_dispatch_or_reconciliation_state';
 else
  if p_provider_status='succeeded' then
   v_new_refunded:=v_attempt.refunded_amount_minor+v_request.amount_minor;
   if v_new_refunded>v_attempt.captured_amount_minor then
    v_result:='manual_review'; v_detail:='confirmed_refund_exceeds_captured_balance';
   else
    update public.mme_pos_tender_attempts set
     refunded_amount_minor=v_new_refunded,
     status=case when v_new_refunded=v_attempt.captured_amount_minor then 'refunded' else 'partially_refunded' end,
     updated_at=now() where id=v_attempt.id;
    update public.mme_pos_refund_requests set status='completed',
     provider_operation_reference=p_provider_refund_reference,
     provider_refund_reference=p_provider_refund_reference,
     failure_code=null,lease_token=null,lease_expires_at=null,updated_at=now()
     where id=v_request.id;
    v_result:='applied'; v_detail:='provider_refund_succeeded';
   end if;
  elsif p_provider_status='failed' then
   update public.mme_pos_refund_requests set status='failed',
    failure_code='stripe_refund_failed',lease_token=null,lease_expires_at=null,updated_at=now()
    where id=v_request.id;
   v_result:='applied'; v_detail:='provider_refund_failed';
  else
   update public.mme_pos_refund_requests set status='unknown_reconciliation',
    lease_token=null,lease_expires_at=null,updated_at=now()
    where id=v_request.id;
   v_result:='applied'; v_detail:='provider_refund_pending';
  end if;
 end if;

 insert into public.mme_pos_stripe_refund_webhook_events(
  provider_event_id,refund_request_id,provider_refund_reference,event_type,payload_sha256,
  processing_status,detail_code,processed_at
 ) values(p_provider_event_id,p_refund_request_id,p_provider_refund_reference,p_event_type,
  p_payload_sha256,v_result,v_detail,now());
 return query select v_result,v_detail,false;
end;
$$;

revoke all on function public.mme_pos_reconcile_stripe_refund_webhook(text,text,text,uuid,text,text,text,bigint,text,text)
 from public,anon,authenticated;
grant execute on function public.mme_pos_reconcile_stripe_refund_webhook(text,text,text,uuid,text,text,text,bigint,text,text)
 to service_role;

comment on table public.mme_pos_stripe_refund_webhook_events is
 'Deduplicated, signature-verified Stripe refund webhook evidence. Raw webhook bodies and card data are not stored.';
commit;
