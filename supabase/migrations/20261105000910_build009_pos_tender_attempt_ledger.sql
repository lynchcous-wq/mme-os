-- Build 009.8: provider-neutral tender intent ledger.
-- This records authorized tender intents only. It does not call a provider,
-- capture funds, or assert that a tender succeeded.
begin;

create table public.mme_pos_tender_attempts (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
  actor_person_id uuid not null,
  method text not null check (method in (
    'card_present','card_not_present','cash','gift_card','financing','store_credit','other_approved'
  )),
  operation text not null check (operation in ('authorize','capture','sale','void','refund')),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  provider text not null,
  provider_account_reference text not null,
  payment_method_reference text,
  policy_reference text,
  calculation_reference text not null,
  idempotency_key text not null,
  request_fingerprint text not null,
  status text not null default 'created' check (status in (
    'created','pending','authorized','partially_captured','captured','declined',
    'cancelled','voided','unknown_reconciliation','partially_refunded','refunded'
  )),
  authorized_amount_minor bigint not null default 0 check (authorized_amount_minor >= 0),
  captured_amount_minor bigint not null default 0 check (captured_amount_minor >= 0),
  refunded_amount_minor bigint not null default 0 check (refunded_amount_minor >= 0),
  provider_payment_reference text,
  provider_operation_reference text,
  reconciliation_status text not null default 'pending' check (reconciliation_status in (
    'not_required','pending','matched','mismatch','manual_review'
  )),
  outcome_unknown boolean not null default false,
  failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (transaction_id, idempotency_key),
  check (captured_amount_minor <= amount_minor),
  check (refunded_amount_minor <= captured_amount_minor)
);

create unique index mme_pos_tender_provider_operation_unique
  on public.mme_pos_tender_attempts(provider, provider_account_reference, provider_operation_reference)
  where provider_operation_reference is not null;

create index mme_pos_tender_transaction_idx
  on public.mme_pos_tender_attempts(transaction_id, created_at);

create table public.mme_pos_tender_outbox (
  id uuid primary key default gen_random_uuid(),
  tender_attempt_id uuid not null unique references public.mme_pos_tender_attempts(id) on delete restrict,
  event_type text not null check (event_type = 'tender.dispatch_requested'),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending','processing','delivered','failed','dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  last_error_code text
);

alter table public.mme_pos_tender_attempts enable row level security;
alter table public.mme_pos_tender_outbox enable row level security;
revoke all on public.mme_pos_tender_attempts, public.mme_pos_tender_outbox from public, anon, authenticated;
grant all on public.mme_pos_tender_attempts, public.mme_pos_tender_outbox to service_role;

create or replace function public.mme_pos_create_tender_attempt(
  p_transaction_id uuid,
  p_actor_person_id uuid,
  p_method text,
  p_operation text,
  p_amount_minor bigint,
  p_currency text,
  p_provider text,
  p_provider_account_reference text,
  p_idempotency_key text,
  p_calculation_reference text,
  p_payment_method_reference text default null,
  p_policy_reference text default null
)
returns table(tender_attempt_id uuid, attempt_status text, replayed boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_tx public.mme_pos_transactions%rowtype;
  v_existing public.mme_pos_tender_attempts%rowtype;
  v_fingerprint text;
  v_reserved bigint;
  v_id uuid;
begin
  if p_transaction_id is null or p_actor_person_id is null
     or p_method is null or p_operation is null
     or p_method not in ('card_present','card_not_present','cash','gift_card','financing','store_credit','other_approved')
     or p_operation not in ('authorize','capture','sale')
     or p_amount_minor is null or p_amount_minor <= 0
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_provider is null or length(btrim(p_provider)) = 0
     or p_provider_account_reference is null or length(btrim(p_provider_account_reference)) = 0
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
     or p_calculation_reference is null or length(btrim(p_calculation_reference)) = 0 then
    raise exception 'Invalid POS tender attempt request' using errcode = '22023';
  end if;

  if p_method in ('card_present','card_not_present') and
     (p_payment_method_reference is null or length(btrim(p_payment_method_reference)) = 0) then
    raise exception 'A provider token reference is required for card tenders' using errcode = '22023';
  end if;
  if p_method in ('cash','gift_card','financing','store_credit','other_approved') and
     (p_policy_reference is null or length(btrim(p_policy_reference)) = 0) then
    raise exception 'An approved policy reference is required for this tender method' using errcode = '22023';
  end if;

  select * into v_tx from public.mme_pos_transactions
   where id = p_transaction_id for update;
  if not found then
    raise exception 'POS transaction not found' using errcode = 'P0002';
  end if;

  if not public.mme_person_authorize_pos_action(p_actor_person_id, 'pos.tender.create', v_tx.order_id) then
    raise exception 'POS tender permission denied' using errcode = '42501';
  end if;

  if v_tx.status not in ('pricing_confirmed','partially_tendered') then
    raise exception 'POS transaction is not accepting tenders' using errcode = '23514';
  end if;
  if v_tx.currency <> p_currency or v_tx.calculation_reference is distinct from p_calculation_reference then
    raise exception 'Tender currency or pricing calculation does not match transaction' using errcode = '22023';
  end if;

  v_fingerprint := md5(jsonb_build_object(
    'transaction_id',p_transaction_id,'method',p_method,'operation',p_operation,
    'amount_minor',p_amount_minor,'currency',p_currency,'provider',p_provider,
    'provider_account_reference',p_provider_account_reference,
    'payment_method_reference',p_payment_method_reference,'policy_reference',p_policy_reference,
    'calculation_reference',p_calculation_reference
  )::text);

  select * into v_existing from public.mme_pos_tender_attempts
   where transaction_id = p_transaction_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception 'Tender idempotency key reused with different request' using errcode = '23505';
    end if;
    return query select v_existing.id, v_existing.status, true;
    return;
  end if;

  select coalesce(sum(case
      when status in ('created','pending','authorized','unknown_reconciliation') then amount_minor
      when status in ('partially_captured','captured') then captured_amount_minor
      else 0 end),0) into v_reserved
    from public.mme_pos_tender_attempts
   where transaction_id = p_transaction_id;

  if v_reserved + p_amount_minor > v_tx.total_cents then
    raise exception 'Tender amount exceeds remaining transaction balance' using errcode = '23514';
  end if;

  insert into public.mme_pos_tender_attempts(
    transaction_id, actor_person_id, method, operation, amount_minor, currency,
    provider, provider_account_reference, payment_method_reference, policy_reference,
    calculation_reference, idempotency_key, request_fingerprint
  ) values (
    p_transaction_id, p_actor_person_id, p_method, p_operation, p_amount_minor, p_currency,
    p_provider, p_provider_account_reference, p_payment_method_reference, p_policy_reference,
    p_calculation_reference, p_idempotency_key, v_fingerprint
  ) returning id into v_id;

  insert into public.mme_pos_tender_outbox(tender_attempt_id,event_type,payload)
  values (
    v_id, 'tender.dispatch_requested',
    jsonb_build_object('tender_attempt_id',v_id,'transaction_id',p_transaction_id,'operation',p_operation)
  );

  return query select v_id, 'created'::text, false;
end;
$$;

revoke all on function public.mme_pos_create_tender_attempt(uuid,uuid,text,text,bigint,text,text,text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.mme_pos_create_tender_attempt(uuid,uuid,text,text,bigint,text,text,text,text,text,text,text)
  to service_role;

comment on table public.mme_pos_tender_attempts is
  'Build 009 tender intent ledger. A created attempt is not proof of authorization, capture, settlement or payment.';
comment on table public.mme_pos_tender_outbox is
  'Build 009 durable queue for provider-neutral tender dispatch requests.';

commit;
