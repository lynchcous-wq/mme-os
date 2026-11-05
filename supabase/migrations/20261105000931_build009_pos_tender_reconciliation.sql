-- Build 009.11: normalized provider reconciliation ledger.
-- Provider feeds are normalized by a trusted adapter before ingestion. Raw provider
-- payloads, cardholder data and provider secrets are never stored here.
begin;

create table public.mme_pos_tender_reconciliation_records (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_account_reference text not null,
  provider_record_reference text not null,
  provider_payment_reference text,
  provider_operation_reference text,
  record_type text not null check (record_type in ('authorization','capture','refund','void','decline')),
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  occurred_at timestamptz not null,
  tender_attempt_id uuid references public.mme_pos_tender_attempts(id) on delete restrict,
  match_status text not null default 'unmatched'
    check (match_status in ('matched','unmatched','mismatch','duplicate_reference','manual_review')),
  mismatch_reason text,
  fingerprint text not null,
  ingested_at timestamptz not null default now(),
  unique(provider, provider_account_reference, provider_record_reference)
);

create index mme_pos_recon_unmatched_idx
  on public.mme_pos_tender_reconciliation_records(match_status, occurred_at);
create index mme_pos_recon_attempt_idx
  on public.mme_pos_tender_reconciliation_records(tender_attempt_id, occurred_at);

create table public.mme_pos_tender_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),
  reconciliation_record_id uuid not null unique
    references public.mme_pos_tender_reconciliation_records(id) on delete restrict,
  tender_attempt_id uuid references public.mme_pos_tender_attempts(id) on delete restrict,
  case_status text not null default 'open' check (case_status in ('open','investigating','resolved','dismissed')),
  reason text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_person_id uuid,
  resolution_reference text
);

alter table public.mme_pos_tender_reconciliation_records enable row level security;
alter table public.mme_pos_tender_reconciliation_cases enable row level security;
revoke all on public.mme_pos_tender_reconciliation_records, public.mme_pos_tender_reconciliation_cases
  from public, anon, authenticated;
grant all on public.mme_pos_tender_reconciliation_records, public.mme_pos_tender_reconciliation_cases
  to service_role;

create or replace function public.mme_pos_ingest_tender_reconciliation_record(
  p_provider text,
  p_provider_account_reference text,
  p_provider_record_reference text,
  p_provider_payment_reference text,
  p_provider_operation_reference text,
  p_record_type text,
  p_amount_minor bigint,
  p_currency text,
  p_occurred_at timestamptz,
  p_fingerprint text
)
returns table(record_id uuid, matched_attempt_id uuid, result_status text, replayed boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_existing public.mme_pos_tender_reconciliation_records%rowtype;
  v_matches uuid[];
  v_attempt public.mme_pos_tender_attempts%rowtype;
  v_id uuid;
  v_result text;
  v_reason text;
  v_expected bigint;
begin
  if p_provider is null or length(btrim(p_provider)) = 0
     or p_provider_account_reference is null or length(btrim(p_provider_account_reference)) = 0
     or p_provider_record_reference is null or length(btrim(p_provider_record_reference)) = 0
     or p_record_type is null or p_record_type not in ('authorization','capture','refund','void','decline')
     or p_amount_minor is null or p_amount_minor < 0
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_occurred_at is null
     or p_fingerprint is null or length(btrim(p_fingerprint)) < 16 then
    raise exception 'Invalid normalized provider reconciliation record' using errcode = '22023';
  end if;

  select * into v_existing
    from public.mme_pos_tender_reconciliation_records
   where provider = p_provider
     and provider_account_reference = p_provider_account_reference
     and provider_record_reference = p_provider_record_reference;
  if found then
    if v_existing.fingerprint <> p_fingerprint then
      raise exception 'Provider record reference reused with different content' using errcode = '23505';
    end if;
    return query select v_existing.id, v_existing.tender_attempt_id, v_existing.match_status, true;
    return;
  end if;

  select array_agg(a.id) into v_matches
    from public.mme_pos_tender_attempts a
   where a.provider = p_provider
     and a.provider_account_reference = p_provider_account_reference
     and (
       (p_provider_operation_reference is not null and a.provider_operation_reference = p_provider_operation_reference)
       or (p_provider_payment_reference is not null and a.provider_payment_reference = p_provider_payment_reference)
     );

  if coalesce(cardinality(v_matches),0) = 1 then
    select * into v_attempt from public.mme_pos_tender_attempts where id = v_matches[1] for update;
    v_reason := null;
    v_expected := case p_record_type
      when 'authorization' then v_attempt.authorized_amount_minor
      when 'capture' then v_attempt.captured_amount_minor
      when 'refund' then v_attempt.refunded_amount_minor
      else v_attempt.amount_minor
    end;
    if v_attempt.currency <> p_currency then
      v_reason := 'currency_mismatch';
    elsif p_record_type in ('authorization','capture','refund') and p_amount_minor <> v_expected then
      v_reason := 'amount_mismatch';
    elsif p_record_type = 'capture' and v_attempt.captured_amount_minor = 0 then
      v_reason := 'capture_not_recorded_in_tender_ledger';
    elsif p_record_type = 'refund' and v_attempt.refunded_amount_minor = 0 then
      v_reason := 'refund_not_recorded_in_tender_ledger';
    end if;
    v_result := case when v_reason is null then 'matched' else 'mismatch' end;
  elsif coalesce(cardinality(v_matches),0) > 1 then
    v_result := 'manual_review';
    v_reason := 'ambiguous_provider_reference';
  else
    v_result := 'unmatched';
    v_reason := 'no_matching_tender_attempt';
  end if;

  insert into public.mme_pos_tender_reconciliation_records(
    provider, provider_account_reference, provider_record_reference,
    provider_payment_reference, provider_operation_reference, record_type,
    amount_minor, currency, occurred_at, tender_attempt_id, match_status,
    mismatch_reason, fingerprint
  ) values (
    p_provider, p_provider_account_reference, p_provider_record_reference,
    p_provider_payment_reference, p_provider_operation_reference, p_record_type,
    p_amount_minor, p_currency, p_occurred_at,
    case when coalesce(cardinality(v_matches),0) = 1 then v_matches[1] else null end,
    v_result, v_reason, p_fingerprint
  ) returning id into v_id;

  if v_result in ('mismatch','unmatched','manual_review') then
    insert into public.mme_pos_tender_reconciliation_cases(
      reconciliation_record_id, tender_attempt_id, reason
    ) values (
      v_id,
      case when coalesce(cardinality(v_matches),0) = 1 then v_matches[1] else null end,
      v_reason
    );
    if coalesce(cardinality(v_matches),0) = 1 then
      update public.mme_pos_tender_attempts
         set reconciliation_status = 'mismatch',
             updated_at = now()
       where id = v_matches[1];
    end if;
  else
    update public.mme_pos_tender_attempts
       set reconciliation_status = 'matched',
           updated_at = now()
     where id = v_matches[1]
       and reconciliation_status <> 'mismatch';
  end if;

  return query select v_id,
    case when coalesce(cardinality(v_matches),0) = 1 then v_matches[1] else null end,
    v_result, false;
end;
$$;

revoke all on function public.mme_pos_ingest_tender_reconciliation_record(text,text,text,text,text,text,bigint,text,timestamptz,text)
  from public, anon, authenticated;
grant execute on function public.mme_pos_ingest_tender_reconciliation_record(text,text,text,text,text,text,bigint,text,timestamptz,text)
  to service_role;

comment on table public.mme_pos_tender_reconciliation_records is
  'Normalized provider settlement/reconciliation records. No raw provider payloads or cardholder data.';
comment on table public.mme_pos_tender_reconciliation_cases is
  'Auditable exception queue for unmatched, ambiguous or mismatched provider reconciliation records.';
comment on function public.mme_pos_ingest_tender_reconciliation_record(text,text,text,text,text,text,bigint,text,timestamptz,text) is
  'Idempotently ingests a normalized provider record, matches by provider references and opens manual review cases for exceptions. Does not alter payment amounts or transaction finalization state.';

commit;
