-- Build 009.44 — Stripe refund settlement matching and financial reporting bridge.
-- Matches confirmed Stripe refunds to normalized payout balance lines; never moves funds.
begin;

create table public.mme_pos_stripe_refund_settlement_matches (
 id uuid primary key default gen_random_uuid(),
 refund_request_id uuid not null references public.mme_pos_refund_requests(id) on delete restrict,
 settlement_line_id uuid not null references public.mme_pos_settlement_lines(id) on delete restrict,
 settlement_batch_id uuid not null references public.mme_pos_settlement_batches(id) on delete restrict,
 provider_refund_reference text not null,
 settlement_refund_reference text,
 provider_account_reference text,
 requested_amount_minor bigint not null check(requested_amount_minor>0),
 settlement_amount_minor bigint not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 match_status text not null check(match_status in ('matched','mismatch','manual_review')),
 discrepancy_code text,
 financial_fact_status text not null default 'pending'
  check(financial_fact_status in ('pending','posted','period_closed','conflict','not_applicable')),
 matched_by_person_id uuid not null,
 matched_at timestamptz not null default now(),
 unique(refund_request_id,settlement_line_id)
);
create unique index mme_pos_stripe_refund_settlement_one_match_idx
 on public.mme_pos_stripe_refund_settlement_matches(refund_request_id)
 where match_status='matched';
create index mme_pos_stripe_refund_settlement_batch_idx
 on public.mme_pos_stripe_refund_settlement_matches(settlement_batch_id,match_status,matched_at desc);

create table public.mme_pos_stripe_refund_settlement_events (
 id uuid primary key default gen_random_uuid(),
 refund_request_id uuid not null references public.mme_pos_refund_requests(id) on delete restrict,
 settlement_line_id uuid references public.mme_pos_settlement_lines(id) on delete restrict,
 settlement_batch_id uuid references public.mme_pos_settlement_batches(id) on delete restrict,
 event_type text not null check(event_type in ('matched','mismatch','manual_review','financial_fact_posted','financial_period_closed','financial_fact_conflict')),
 detail_code text not null,
 actor_person_id uuid not null,
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_stripe_refund_settlement_events_idx
 on public.mme_pos_stripe_refund_settlement_events(refund_request_id,occurred_at desc);

alter table public.mme_pos_stripe_refund_settlement_matches enable row level security;
alter table public.mme_pos_stripe_refund_settlement_events enable row level security;
revoke all on public.mme_pos_stripe_refund_settlement_matches,public.mme_pos_stripe_refund_settlement_events
 from public,anon,authenticated;
grant all on public.mme_pos_stripe_refund_settlement_matches,public.mme_pos_stripe_refund_settlement_events
 to service_role;

create or replace function public.mme_pos_match_stripe_refund_settlement_line(
 p_refund_request_id uuid,p_settlement_line_id uuid,p_actor_person_id uuid,
 p_business_date date,p_business_timezone text
) returns table(match_id uuid,match_status text,discrepancy_code text,financial_fact_status text)
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_request public.mme_pos_refund_requests%rowtype;
 v_attempt public.mme_pos_tender_attempts%rowtype;
 v_line public.mme_pos_settlement_lines%rowtype;
 v_batch public.mme_pos_settlement_batches%rowtype;
 v_existing public.mme_pos_stripe_refund_settlement_matches%rowtype;
 v_match_id uuid;
 v_status text;
 v_code text;
 v_fact_status text:='not_applicable';
 v_occurred_at timestamptz;
 v_fact_id uuid;
 v_existing_fact public.mme_pos_financial_reporting_facts%rowtype;
begin
 if p_refund_request_id is null or p_settlement_line_id is null or p_actor_person_id is null
  or p_business_date is null or p_business_timezone is null
  or not exists(select 1 from pg_timezone_names where name=p_business_timezone) then
  raise exception 'Invalid Stripe refund settlement match request' using errcode='22023';
 end if;

 select * into v_request from public.mme_pos_refund_requests
  where id=p_refund_request_id for update;
 if not found then raise exception 'Refund request not found' using errcode='P0002'; end if;
 select * into v_attempt from public.mme_pos_tender_attempts
  where id=v_request.tender_attempt_id for update;
 if not found then raise exception 'Tender attempt not found' using errcode='P0002'; end if;
 select * into v_line from public.mme_pos_settlement_lines
  where id=p_settlement_line_id for update;
 if not found then raise exception 'Settlement line not found' using errcode='P0002'; end if;
 select * into v_batch from public.mme_pos_settlement_batches
  where id=v_line.batch_id for update;

 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_batch.location_id,'pos.settlement.reconcile') then
  raise exception 'Stripe refund settlement reconciliation permission denied' using errcode='42501';
 end if;
 if v_request.request_type<>'refund' or v_request.status<>'completed'
  or v_request.provider_refund_reference is null or v_request.provider_operation_reference is null then
  raise exception 'Only provider-confirmed completed refunds can be settlement matched' using errcode='23514';
 end if;
 if v_attempt.provider<>'stripe' or v_batch.provider<>'stripe' or v_line.provider<>'stripe' then
  raise exception 'Refund, tender and settlement line must all belong to Stripe' using errcode='23514';
 end if;
 if v_batch.location_id is null then
  raise exception 'Settlement batch has no store location' using errcode='23514';
 end if;

 select * into v_existing from public.mme_pos_stripe_refund_settlement_matches
  where refund_request_id=v_request.id and settlement_line_id=v_line.id;
 if found then
  return query select v_existing.id,v_existing.match_status,v_existing.discrepancy_code,v_existing.financial_fact_status;
  return;
 end if;
 if exists(select 1 from public.mme_pos_stripe_refund_settlement_matches
  where refund_request_id=v_request.id and match_status='matched') then
  v_status:='manual_review'; v_code:='refund_already_matched_to_another_settlement_line';
 elsif exists(select 1 from public.mme_pos_stripe_refund_settlement_matches
  where settlement_line_id=v_line.id and match_status='matched') then
  v_status:='manual_review'; v_code:='settlement_line_already_matched_to_another_refund';
 elsif v_batch.provider_account_reference is distinct from v_attempt.provider_account_reference then
  v_status:='mismatch'; v_code:='connected_account_mismatch';
 elsif v_line.line_type<>'refund' then
  v_status:='mismatch'; v_code:='settlement_line_is_not_refund';
 elsif v_line.refund_reference is distinct from v_request.provider_refund_reference then
  v_status:='mismatch'; v_code:='provider_refund_reference_mismatch';
 elsif v_line.currency<>v_request.currency or v_batch.currency<>v_request.currency then
  v_status:='mismatch'; v_code:='refund_currency_mismatch';
 elsif abs(v_line.amount_minor)<>v_request.amount_minor then
  v_status:='mismatch'; v_code:='refund_amount_mismatch';
 else
  v_status:='matched'; v_code:=null;
 end if;

 insert into public.mme_pos_stripe_refund_settlement_matches(
  refund_request_id,settlement_line_id,settlement_batch_id,provider_refund_reference,
  settlement_refund_reference,provider_account_reference,requested_amount_minor,
  settlement_amount_minor,currency,match_status,discrepancy_code,matched_by_person_id
 ) values(v_request.id,v_line.id,v_batch.id,v_request.provider_refund_reference,
  v_line.refund_reference,v_batch.provider_account_reference,v_request.amount_minor,
  v_line.amount_minor,v_request.currency,v_status,v_code,p_actor_person_id)
 returning id into v_match_id;

 update public.mme_pos_refund_requests set
  provider_reconciliation_status=case when v_status='matched' then 'matched'
   when v_status='mismatch' then 'mismatch' else 'manual_review' end,
  provider_reconciled_at=now(),updated_at=now()
 where id=v_request.id;

 if v_status='matched' then
  v_occurred_at:=coalesce(v_request.provider_reconciled_at,v_request.updated_at);
  if (v_occurred_at at time zone p_business_timezone)::date<>p_business_date then
   v_fact_status:='conflict'; v_code:='financial_business_date_does_not_match_refund_timestamp';
  elsif exists(select 1 from public.mme_pos_financial_closes c
   where c.location_id=v_batch.location_id and c.currency=v_request.currency
    and v_occurred_at>=c.business_period_start and v_occurred_at<c.business_period_end
    and c.status='closed') then
   v_fact_status:='period_closed'; v_code:='financial_period_closed_adjustment_required';
  else
   select * into v_existing_fact from public.mme_pos_financial_reporting_facts
    where location_id=v_batch.location_id and source_system='payments'
     and source_line_reference='stripe-refund:'||v_request.provider_refund_reference and fact_type='refund';
   if found then
    if v_existing_fact.amount_minor<>-v_request.amount_minor or v_existing_fact.currency<>v_request.currency
     or v_existing_fact.source_transaction_reference is distinct from v_attempt.provider_payment_reference then
     v_fact_status:='conflict'; v_code:='existing_financial_refund_fact_conflicts';
    else
     v_fact_status:='posted';
    end if;
   else
    select public.mme_pos_import_financial_fact(
     v_batch.location_id,p_actor_person_id,'payments',
     'stripe-refund:'||v_request.provider_refund_reference,'refund',p_business_date,
     v_occurred_at,p_business_timezone,v_request.currency,-v_request.amount_minor,
     null,null,null,null,null,v_attempt.provider_payment_reference,
     coalesce(v_line.source_digest_sha256,v_batch.source_digest_sha256)
    ) into v_fact_id;
    v_fact_status:='posted';
   end if;
  end if;
 end if;

 update public.mme_pos_stripe_refund_settlement_matches set
  financial_fact_status=v_fact_status,discrepancy_code=v_code
  where id=v_match_id;

 insert into public.mme_pos_stripe_refund_settlement_events(
  refund_request_id,settlement_line_id,settlement_batch_id,event_type,detail_code,actor_person_id,metadata
 ) values(v_request.id,v_line.id,v_batch.id,
  case when v_status='matched' and v_fact_status='posted' then 'financial_fact_posted'
   when v_status='matched' and v_fact_status='period_closed' then 'financial_period_closed'
   when v_status='matched' and v_fact_status='conflict' then 'financial_fact_conflict'
   when v_status='matched' then 'matched'
   when v_status='mismatch' then 'mismatch' else 'manual_review' end,
  coalesce(v_code,'exact_provider_refund_match'),p_actor_person_id,
  jsonb_build_object('match_id',v_match_id,'requested_amount_minor',v_request.amount_minor,
   'settlement_amount_minor',v_line.amount_minor,'currency',v_request.currency,
   'financial_fact_status',v_fact_status));
 return query select v_match_id,v_status,v_code,v_fact_status;
end;
$$;

create or replace view public.mme_pos_stripe_refund_settlement_dashboard
with (security_invoker=true) as
select b.location_id,b.provider_account_reference,b.currency,
 count(*) filter(where m.match_status='matched')::integer matched_refund_count,
 count(*) filter(where m.match_status='mismatch')::integer mismatched_refund_count,
 count(*) filter(where m.match_status='manual_review')::integer manual_review_count,
 count(*) filter(where m.financial_fact_status='period_closed')::integer closed_period_fact_count,
 coalesce(sum(m.requested_amount_minor) filter(where m.match_status='matched'),0)::bigint matched_refund_amount_minor,
 coalesce(sum(abs(m.settlement_amount_minor)) filter(where m.match_status='matched'),0)::bigint processor_refund_amount_minor,
 count(distinct m.settlement_batch_id)::integer settlement_batch_count,
 max(m.matched_at) last_reconciled_at
from public.mme_pos_stripe_refund_settlement_matches m
join public.mme_pos_settlement_batches b on b.id=m.settlement_batch_id
group by b.location_id,b.provider_account_reference,b.currency;

revoke all on function public.mme_pos_match_stripe_refund_settlement_line(uuid,uuid,uuid,date,text)
 from public,anon,authenticated;
grant execute on function public.mme_pos_match_stripe_refund_settlement_line(uuid,uuid,uuid,date,text)
 to service_role;
revoke all on public.mme_pos_stripe_refund_settlement_dashboard from public,anon,authenticated;
grant select on public.mme_pos_stripe_refund_settlement_dashboard to service_role;

comment on table public.mme_pos_stripe_refund_settlement_matches is
 'Exact Stripe refund-to-payout-line match ledger. Provider refund confirmation and bank deposit settlement remain distinct.';
comment on view public.mme_pos_stripe_refund_settlement_dashboard is
 'Store/account/currency-scoped Stripe refund settlement metrics for authorized CEO and Finance reporting; no bank deposit is implied.';

commit;
