-- Build 009.11: provider settlement import and deterministic reconciliation.
-- Provider files are imported as normalized records. No provider network calls
-- or payment movement are performed by these database functions.
begin;

create table public.mme_pos_provider_settlement_records (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_account_reference text not null,
  provider_record_reference text not null,
  provider_payment_reference text,
  provider_operation_reference text,
  record_type text not null check (record_type in ('capture','refund','fee','adjustment')),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  occurred_at timestamptz,
  imported_at timestamptz not null default now(),
  reconciliation_status text not null default 'pending'
    check (reconciliation_status in ('pending','matched','mismatch','unmatched','duplicate','manual_review')),
  matched_tender_attempt_id uuid references public.mme_pos_tender_attempts(id) on delete restrict,
  discrepancy_code text,
  raw_record_digest text not null,
  unique(provider, provider_account_reference, provider_record_reference)
);

create index mme_pos_settlement_reconcile_idx
  on public.mme_pos_provider_settlement_records(reconciliation_status, imported_at);
create index mme_pos_settlement_provider_refs_idx
  on public.mme_pos_provider_settlement_records(provider, provider_account_reference, provider_operation_reference, provider_payment_reference);

create table public.mme_pos_reconciliation_events (
  id uuid primary key default gen_random_uuid(),
  settlement_record_id uuid not null references public.mme_pos_provider_settlement_records(id) on delete restrict,
  tender_attempt_id uuid references public.mme_pos_tender_attempts(id) on delete restrict,
  event_type text not null check (event_type in ('imported','matched','mismatch','unmatched','duplicate','manual_review','reopened')),
  detail_code text,
  created_at timestamptz not null default now(),
  created_by text not null default 'system'
);

alter table public.mme_pos_provider_settlement_records enable row level security;
alter table public.mme_pos_reconciliation_events enable row level security;
revoke all on public.mme_pos_provider_settlement_records, public.mme_pos_reconciliation_events from public, anon, authenticated;
grant all on public.mme_pos_provider_settlement_records, public.mme_pos_reconciliation_events to service_role;

create or replace function public.mme_pos_import_settlement_record(
  p_provider text,
  p_provider_account_reference text,
  p_provider_record_reference text,
  p_provider_payment_reference text,
  p_provider_operation_reference text,
  p_record_type text,
  p_amount_minor bigint,
  p_currency text,
  p_occurred_at timestamptz,
  p_raw_record_digest text
)
returns table(settlement_record_id uuid, replayed boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_id uuid;
begin
  if p_provider is null or length(btrim(p_provider)) = 0
     or p_provider_account_reference is null or length(btrim(p_provider_account_reference)) = 0
     or p_provider_record_reference is null or length(btrim(p_provider_record_reference)) = 0
     or p_record_type is null or p_record_type not in ('capture','refund','fee','adjustment')
     or p_amount_minor is null or p_amount_minor <= 0
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_raw_record_digest is null or p_raw_record_digest !~ '^[a-fA-F0-9]{64}$'
     or (p_provider_payment_reference is null and p_provider_operation_reference is null) then
    raise exception 'Invalid provider settlement record' using errcode = '22023';
  end if;

  select id into v_id
    from public.mme_pos_provider_settlement_records
   where provider = p_provider
     and provider_account_reference = p_provider_account_reference
     and provider_record_reference = p_provider_record_reference;
  if found then
    return query select v_id, true;
    return;
  end if;

  insert into public.mme_pos_provider_settlement_records(
    provider, provider_account_reference, provider_record_reference,
    provider_payment_reference, provider_operation_reference, record_type,
    amount_minor, currency, occurred_at, raw_record_digest
  ) values (
    p_provider, p_provider_account_reference, p_provider_record_reference,
    p_provider_payment_reference, p_provider_operation_reference, p_record_type,
    p_amount_minor, p_currency, p_occurred_at, p_raw_record_digest
  ) returning id into v_id;

  insert into public.mme_pos_reconciliation_events(settlement_record_id,event_type)
  values (v_id,'imported');

  return query select v_id, false;
end;
$$;

create or replace function public.mme_pos_reconcile_settlement_record(p_settlement_record_id uuid)
returns table(settlement_record_id uuid, reconciliation_status text, tender_attempt_id uuid, discrepancy_code text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_record public.mme_pos_provider_settlement_records%rowtype;
  v_attempt public.mme_pos_tender_attempts%rowtype;
  v_match_count integer;
  v_status text;
  v_code text;
begin
  select * into v_record from public.mme_pos_provider_settlement_records
   where id = p_settlement_record_id for update;
  if not found then
    raise exception 'Settlement record not found' using errcode = 'P0002';
  end if;

  if v_record.reconciliation_status <> 'pending' then
    return query select v_record.id, v_record.reconciliation_status,
      v_record.matched_tender_attempt_id, v_record.discrepancy_code;
    return;
  end if;

  select count(*) into v_match_count
    from public.mme_pos_tender_attempts a
   where a.provider = v_record.provider
     and a.provider_account_reference = v_record.provider_account_reference
     and (
       (v_record.provider_operation_reference is not null and a.provider_operation_reference = v_record.provider_operation_reference)
       or (v_record.provider_payment_reference is not null and a.provider_payment_reference = v_record.provider_payment_reference)
     );

  if v_match_count = 0 then
    v_status := 'unmatched'; v_code := 'no_tender_reference_match';
  elsif v_match_count > 1 then
    v_status := 'manual_review'; v_code := 'ambiguous_tender_reference';
  else
    select * into v_attempt
      from public.mme_pos_tender_attempts a
     where a.provider = v_record.provider
       and a.provider_account_reference = v_record.provider_account_reference
       and (
         (v_record.provider_operation_reference is not null and a.provider_operation_reference = v_record.provider_operation_reference)
         or (v_record.provider_payment_reference is not null and a.provider_payment_reference = v_record.provider_payment_reference)
       )
     limit 1;

    if exists (
      select 1 from public.mme_pos_provider_settlement_records x
       where x.id <> v_record.id
         and x.provider = v_record.provider
         and x.provider_account_reference = v_record.provider_account_reference
         and x.provider_operation_reference is not distinct from v_record.provider_operation_reference
         and x.record_type = v_record.record_type
         and x.reconciliation_status in ('matched','pending')
         and v_record.provider_operation_reference is not null
    ) then
      v_status := 'duplicate'; v_code := 'duplicate_provider_operation_record';
    elsif v_attempt.currency <> v_record.currency then
      v_status := 'mismatch'; v_code := 'currency_mismatch';
    elsif v_record.record_type = 'capture'
      and v_attempt.captured_amount_minor <> v_record.amount_minor then
      v_status := 'mismatch'; v_code := 'capture_amount_mismatch';
    elsif v_record.record_type = 'refund'
      and v_attempt.refunded_amount_minor <> v_record.amount_minor then
      v_status := 'mismatch'; v_code := 'refund_amount_mismatch';
    elsif v_record.record_type in ('fee','adjustment') then
      v_status := 'manual_review'; v_code := 'record_type_requires_policy_review';
    elsif (v_record.record_type = 'capture' and v_attempt.status not in ('captured','partially_captured'))
       or (v_record.record_type = 'refund' and v_attempt.status not in ('partially_refunded','refunded')) then
      v_status := 'mismatch'; v_code := 'tender_state_mismatch';
    else
      v_status := 'matched'; v_code := null;
    end if;
  end if;

  update public.mme_pos_provider_settlement_records
     set reconciliation_status = v_status,
         matched_tender_attempt_id = case when v_match_count = 1 then v_attempt.id else null end,
         discrepancy_code = v_code
   where id = v_record.id;

  if v_match_count = 1 and v_status in ('matched','mismatch','duplicate','manual_review') then
    update public.mme_pos_tender_attempts
       set reconciliation_status = case when v_status = 'matched' then 'matched'
         when v_status = 'mismatch' then 'mismatch' else 'manual_review' end,
         updated_at = now()
     where id = v_attempt.id;
  end if;

  insert into public.mme_pos_reconciliation_events(
    settlement_record_id,tender_attempt_id,event_type,detail_code
  ) values (
    v_record.id, case when v_match_count = 1 then v_attempt.id else null end,
    v_status, v_code
  );

  return query select v_record.id, v_status,
    case when v_match_count = 1 then v_attempt.id else null end, v_code;
end;
$$;

create or replace view public.mme_pos_reconciliation_summary
with (security_invoker = true)
as
select provider, provider_account_reference,
       reconciliation_status, count(*) as record_count,
       coalesce(sum(amount_minor),0) as total_amount_minor,
       currency
  from public.mme_pos_provider_settlement_records
 group by provider, provider_account_reference, reconciliation_status, currency;

revoke all on function public.mme_pos_import_settlement_record(text,text,text,text,text,text,bigint,text,timestamptz,text)
  from public, anon, authenticated;
revoke all on function public.mme_pos_reconcile_settlement_record(uuid)
  from public, anon, authenticated;
grant execute on function public.mme_pos_import_settlement_record(text,text,text,text,text,text,bigint,text,timestamptz,text)
  to service_role;
grant execute on function public.mme_pos_reconcile_settlement_record(uuid)
  to service_role;
revoke all on public.mme_pos_reconciliation_summary from public, anon, authenticated;
grant select on public.mme_pos_reconciliation_summary to service_role;

comment on table public.mme_pos_provider_settlement_records is
  'Normalized provider settlement records. Imported data is evidence for reconciliation, not a payment command.';
comment on table public.mme_pos_reconciliation_events is
  'Append-only reconciliation decision history with discrepancy codes and linked tender attempts.';
comment on view public.mme_pos_reconciliation_summary is
  'Service-role reconciliation totals grouped by provider, account, status and currency.';

commit;
