-- Build 009.13: exact refund settlement matching and provider dispute event ledger.
-- Imports are evidence only; no payment or dispute action is sent to a provider.
begin;

alter table public.mme_pos_refund_requests
  add column if not exists settlement_record_id uuid
    references public.mme_pos_provider_settlement_records(id) on delete restrict,
  add column if not exists provider_reconciled_at timestamptz,
  add column if not exists provider_reconciliation_status text not null default 'pending'
    check (provider_reconciliation_status in ('pending','matched','mismatch','manual_review'));

create unique index if not exists mme_pos_refund_settlement_record_unique
  on public.mme_pos_refund_requests(settlement_record_id)
  where settlement_record_id is not null;

create index if not exists mme_pos_refund_provider_ref_idx
  on public.mme_pos_refund_requests(provider_refund_reference,provider_operation_reference);

create or replace function public.mme_pos_reconcile_refund_settlement(
  p_settlement_record_id uuid
)
returns table(settlement_record_id uuid,reconciliation_status text,
  refund_request_id uuid,discrepancy_code text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_record public.mme_pos_provider_settlement_records%rowtype;
  v_request public.mme_pos_refund_requests%rowtype;
  v_count integer;
  v_status text;
  v_code text;
begin
  select * into v_record
    from public.mme_pos_provider_settlement_records
   where id=p_settlement_record_id for update;
  if not found then raise exception 'Settlement record not found' using errcode='P0002'; end if;
  if v_record.record_type <> 'refund' then
    raise exception 'Settlement record is not a refund' using errcode='22023';
  end if;
  if v_record.reconciliation_status not in ('pending','unmatched','mismatch','manual_review') then
    return query select v_record.id,v_record.reconciliation_status,null::uuid,v_record.discrepancy_code;
    return;
  end if;

  select count(*) into v_count
    from public.mme_pos_refund_requests r
    join public.mme_pos_tender_attempts a on a.id=r.tender_attempt_id
   where r.request_type='refund'
     and r.status='completed'
     and r.provider_refund_reference is not null
     and a.provider=v_record.provider
     and a.provider_account_reference=v_record.provider_account_reference
     and r.provider_refund_reference=v_record.provider_operation_reference
     and r.amount_minor=v_record.amount_minor
     and r.currency=v_record.currency;

  if v_count=0 then
    v_status:='unmatched'; v_code:='no_exact_completed_refund_match';
  elsif v_count>1 then
    v_status:='manual_review'; v_code:='ambiguous_refund_reference_match';
  else
    select r.* into v_request
      from public.mme_pos_refund_requests r
      join public.mme_pos_tender_attempts a on a.id=r.tender_attempt_id
     where r.request_type='refund' and r.status='completed'
       and r.provider_refund_reference is not null
       and a.provider=v_record.provider
       and a.provider_account_reference=v_record.provider_account_reference
       and r.provider_refund_reference=v_record.provider_operation_reference
       and r.amount_minor=v_record.amount_minor
       and r.currency=v_record.currency
     limit 1 for update of r;
    if v_request.settlement_record_id is not null
       and v_request.settlement_record_id<>v_record.id then
      v_status:='manual_review'; v_code:='refund_already_linked_to_other_settlement';
    else
      v_status:='matched'; v_code:=null;
      update public.mme_pos_refund_requests
         set settlement_record_id=v_record.id,
             provider_reconciliation_status='matched',
             provider_reconciled_at=now(),updated_at=now()
       where id=v_request.id;
    end if;
  end if;

  update public.mme_pos_provider_settlement_records
     set reconciliation_status=v_status,
         matched_tender_attempt_id=case when v_count=1 then v_request.tender_attempt_id else null end,
         discrepancy_code=v_code
   where id=v_record.id;

  insert into public.mme_pos_reconciliation_events(
    settlement_record_id,tender_attempt_id,event_type,detail_code
  ) values (
    v_record.id,case when v_count=1 then v_request.tender_attempt_id else null end,
    v_status,v_code
  );
  return query select v_record.id,v_status,
    case when v_status='matched' then v_request.id else null end,v_code;
end;
$$;

create table public.mme_pos_provider_disputes (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_account_reference text not null,
  provider_dispute_reference text not null,
  provider_payment_reference text,
  tender_attempt_id uuid references public.mme_pos_tender_attempts(id) on delete restrict,
  amount_minor bigint not null check(amount_minor>0),
  currency text not null check(currency ~ '^[A-Z]{3}$'),
  reason_code text,
  evidence_due_at timestamptz,
  status text not null default 'open'
    check(status in ('open','evidence_due','under_review','won','lost','reversed','manual_review')),
  latest_provider_event_reference text not null,
  raw_event_digest text not null check(raw_event_digest ~ '^[a-fA-F0-9]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider,provider_account_reference,provider_dispute_reference)
);

create table public.mme_pos_provider_dispute_events (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.mme_pos_provider_disputes(id) on delete restrict,
  provider_event_reference text not null,
  event_type text not null check(event_type in (
    'opened','evidence_due','under_review','won','lost','reversed','manual_review'
  )),
  event_digest text not null check(event_digest ~ '^[a-fA-F0-9]{64}$'),
  occurred_at timestamptz,
  imported_at timestamptz not null default now(),
  unique(dispute_id,provider_event_reference)
);

create index mme_pos_provider_disputes_status_idx
  on public.mme_pos_provider_disputes(status,evidence_due_at);

alter table public.mme_pos_provider_disputes enable row level security;
alter table public.mme_pos_provider_dispute_events enable row level security;
revoke all on public.mme_pos_provider_disputes,public.mme_pos_provider_dispute_events
  from public,anon,authenticated;
grant all on public.mme_pos_provider_disputes,public.mme_pos_provider_dispute_events
  to service_role;

create or replace function public.mme_pos_import_dispute_event(
  p_provider text,
  p_provider_account_reference text,
  p_provider_dispute_reference text,
  p_provider_payment_reference text,
  p_provider_event_reference text,
  p_event_type text,
  p_amount_minor bigint,
  p_currency text,
  p_reason_code text,
  p_evidence_due_at timestamptz,
  p_occurred_at timestamptz,
  p_event_digest text
)
returns table(dispute_id uuid,event_id uuid,replayed boolean)
language plpgsql
security definer
set search_path = pg_catalog,public
as $$
declare
  v_dispute public.mme_pos_provider_disputes%rowtype;
  v_event public.mme_pos_provider_dispute_events%rowtype;
  v_attempt public.mme_pos_tender_attempts%rowtype;
  v_count integer;
  v_status text;
  v_dispute_id uuid;
  v_event_id uuid;
begin
  if p_provider is null or length(btrim(p_provider))=0
     or p_provider_account_reference is null or length(btrim(p_provider_account_reference))=0
     or p_provider_dispute_reference is null or length(btrim(p_provider_dispute_reference))=0
     or p_provider_event_reference is null or length(btrim(p_provider_event_reference))=0
     or p_event_type not in ('opened','evidence_due','under_review','won','lost','reversed','manual_review')
     or p_amount_minor is null or p_amount_minor<=0
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_event_digest is null or p_event_digest !~ '^[a-fA-F0-9]{64}$' then
    raise exception 'Invalid provider dispute event' using errcode='22023';
  end if;

  select * into v_dispute from public.mme_pos_provider_disputes
   where provider=p_provider and provider_account_reference=p_provider_account_reference
     and provider_dispute_reference=p_provider_dispute_reference
   for update;
  if found then
    if v_dispute.amount_minor<>p_amount_minor or v_dispute.currency<>p_currency
       or v_dispute.provider_payment_reference is distinct from p_provider_payment_reference then
      raise exception 'Provider dispute reference reused with different dispute details' using errcode='23505';
    end if;
    v_dispute_id:=v_dispute.id;
  else
    select count(*) into v_count from public.mme_pos_tender_attempts a
     where a.provider=p_provider and a.provider_account_reference=p_provider_account_reference
       and p_provider_payment_reference is not null
       and a.provider_payment_reference=p_provider_payment_reference;
    if v_count=1 then
      select * into v_attempt from public.mme_pos_tender_attempts a
       where a.provider=p_provider and a.provider_account_reference=p_provider_account_reference
         and a.provider_payment_reference=p_provider_payment_reference limit 1;
    end if;
    insert into public.mme_pos_provider_disputes(
      provider,provider_account_reference,provider_dispute_reference,
      provider_payment_reference,tender_attempt_id,amount_minor,currency,
      reason_code,evidence_due_at,latest_provider_event_reference,raw_event_digest,status
    ) values (
      p_provider,p_provider_account_reference,p_provider_dispute_reference,
      p_provider_payment_reference,case when v_count=1 then v_attempt.id else null end,
      p_amount_minor,p_currency,p_reason_code,p_evidence_due_at,
      p_provider_event_reference,p_event_digest,
      case when v_count=1 then 'open' else 'manual_review' end
    ) returning id into v_dispute_id;
  end if;

  select * into v_event from public.mme_pos_provider_dispute_events
   where dispute_id=v_dispute_id and provider_event_reference=p_provider_event_reference;
  if found then
    if v_event.event_digest<>p_event_digest or v_event.event_type<>p_event_type then
      raise exception 'Provider dispute event reference reused with different event data' using errcode='23505';
    end if;
    return query select v_dispute_id,v_event.id,true;
    return;
  end if;

  v_status:=case p_event_type
    when 'opened' then 'open'
    when 'evidence_due' then 'evidence_due'
    when 'under_review' then 'under_review'
    when 'won' then 'won'
    when 'lost' then 'lost'
    when 'reversed' then 'reversed'
    else 'manual_review' end;

  insert into public.mme_pos_provider_dispute_events(
    dispute_id,provider_event_reference,event_type,event_digest,occurred_at
  ) values (
    v_dispute_id,p_provider_event_reference,p_event_type,p_event_digest,p_occurred_at
  ) returning id into v_event_id;

  update public.mme_pos_provider_disputes
     set status=case when status='manual_review' then 'manual_review' else v_status end,
         latest_provider_event_reference=p_provider_event_reference,
         raw_event_digest=p_event_digest,
         evidence_due_at=coalesce(p_evidence_due_at,evidence_due_at),
         updated_at=now()
   where id=v_dispute_id;

  return query select v_dispute_id,v_event_id,false;
end;
$$;

revoke all on function public.mme_pos_reconcile_refund_settlement(uuid)
  from public,anon,authenticated;
revoke all on function public.mme_pos_import_dispute_event(text,text,text,text,text,text,bigint,text,text,timestamptz,timestamptz,text)
  from public,anon,authenticated;
grant execute on function public.mme_pos_reconcile_refund_settlement(uuid) to service_role;
grant execute on function public.mme_pos_import_dispute_event(text,text,text,text,text,text,bigint,text,text,timestamptz,timestamptz,text)
  to service_role;

comment on table public.mme_pos_provider_disputes is
  'Provider dispute cases and evidence deadlines; stores references and hashes, not sensitive evidence documents.';
comment on table public.mme_pos_provider_dispute_events is
  'Idempotent provider dispute event history.';

commit;
