-- Build 009: durable POS orchestration records.
-- Additive only. Does not create orders, change inventory, accept tender, or call providers.
-- All live commands must be performed by a trusted server adapter after Build 004 authorization.

begin;

create table public.mme_pos_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.mme_orders(id) on delete restrict,
  store_id uuid not null references public.mme_store_locations(id) on delete restrict,
  register_session_id uuid,
  status text not null default 'draft'
    check (status in (
      'draft','inventory_reserved','pricing_confirmed','tendering',
      'partially_tendered','fully_tendered','finalization_pending',
      'finalized','reconciliation_required','cancelled'
    )),
  currency text not null default 'USD' check (currency = 'USD'),
  total_cents bigint not null default 0 check (total_cents >= 0),
  reservation_reference text,
  calculation_reference text,
  request_fingerprint text not null,
  created_by_person_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finalized_at timestamptz,
  revision bigint not null default 0 check (revision >= 0),
  unique(order_id),
  check ((status = 'finalized') = (finalized_at is not null))
);

create table public.mme_pos_tender_allocations (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
  order_id uuid not null references public.mme_orders(id) on delete restrict,
  method text not null check (method in (
    'card_present','card_not_present','cash','gift_card','financing','store_credit','other_approved'
  )),
  operation text not null check (operation in ('authorize','capture','sale','void','refund')),
  status text not null check (status in (
    'created','requires_customer_action','pending','authorized','partially_captured',
    'captured','declined','cancelled','voided','partially_refunded','refunded','unknown_reconciliation'
  )),
  requested_amount_cents bigint not null check (requested_amount_cents > 0),
  authorized_amount_cents bigint check (authorized_amount_cents is null or authorized_amount_cents >= 0),
  captured_amount_cents bigint check (captured_amount_cents is null or captured_amount_cents >= 0),
  refunded_amount_cents bigint check (refunded_amount_cents is null or refunded_amount_cents >= 0),
  currency text not null check (currency = 'USD'),
  provider text not null,
  provider_account_reference text not null,
  provider_payment_reference text,
  provider_operation_reference text,
  idempotency_key text not null unique,
  request_fingerprint text not null,
  reconciliation_status text not null default 'pending'
    check (reconciliation_status in ('not_required','pending','matched','mismatch','manual_review')),
  display_reference text,
  failure_code text,
  failure_category text,
  failure_message text,
  created_by_person_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (refunded_amount_cents is null or captured_amount_cents is null
    or refunded_amount_cents <= captured_amount_cents)
);

create index mme_pos_tender_transaction_idx
  on public.mme_pos_tender_allocations(transaction_id, created_at);

create table public.mme_pos_transaction_events (
  id bigint generated always as identity primary key,
  transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
  event_type text not null,
  from_status text,
  to_status text not null,
  actor_person_id uuid not null,
  reason_code text,
  event_fingerprint text not null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  unique(transaction_id, event_fingerprint)
);

create index mme_pos_events_transaction_idx
  on public.mme_pos_transaction_events(transaction_id, id);

create table public.mme_pos_outbox (
  id bigint generated always as identity primary key,
  transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
  event_id bigint not null references public.mme_pos_transaction_events(id) on delete restrict,
  event_type text not null,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  status text not null default 'pending'
    check (status in ('pending','processing','delivered','retry','dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  delivered_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  unique(event_id, event_type)
);

create index mme_pos_outbox_delivery_idx
  on public.mme_pos_outbox(status, available_at, id);

-- The immutable history is protected from ordinary update/delete operations.
create or replace function public.mme_pos_reject_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'POS transaction events are append-only' using errcode = '55000';
end;
$$;

create trigger mme_pos_events_immutable
before update or delete on public.mme_pos_transaction_events
for each row execute function public.mme_pos_reject_event_mutation();

-- Register-session ownership remains a separate future contract. This function
-- creates only an orchestration envelope bound to an already-created Build 001 order.
create or replace function public.mme_pos_create_transaction(
  p_order_id uuid,
  p_store_id uuid,
  p_actor_person_id uuid,
  p_idempotency_key text,
  p_request_fingerprint text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction_id uuid;
  v_order_status text;
  v_order_currency text;
  v_order_total bigint;
  v_existing_fingerprint text;
  v_event_id bigint;
begin
  if p_order_id is null or p_store_id is null or p_actor_person_id is null
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(p_idempotency_key) > 128
     or p_request_fingerprint is null or length(p_request_fingerprint) < 16 then
    raise exception 'Invalid POS transaction request' using errcode = '22023';
  end if;

  -- This is an additional guard, not a substitute for route-level permission checks.
  if not exists (
    select 1 from public.employee_relationships er
    where er.person_id = p_actor_person_id
      and er.employment_status = 'active'
  ) or not exists (
    select 1 from public.mme_person_identities pi
    where pi.person_id = p_actor_person_id
      and pi.lifecycle_status = 'active'
  ) then
    raise exception 'Active employee identity required' using errcode = '42501';
  end if;

  select o.status, o.currency, o.total_cents
    into v_order_status, v_order_currency, v_order_total
  from public.mme_orders o
  where o.id = p_order_id
  for update;

  if not found or v_order_status <> 'pending_payment' then
    raise exception 'Pending Build 001 order required' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.mme_store_locations l
    where l.id = p_store_id and l.active = true
  ) then
    raise exception 'Active store location required' using errcode = 'P0002';
  end if;

  select t.id, t.request_fingerprint
    into v_transaction_id, v_existing_fingerprint
  from public.mme_pos_transactions t
  where t.order_id = p_order_id
  for update;

  if found then
    if v_existing_fingerprint <> p_request_fingerprint then
      raise exception 'POS order already bound to a different request' using errcode = '23505';
    end if;
    return v_transaction_id;
  end if;

  insert into public.mme_pos_transactions(
    order_id, store_id, status, currency, total_cents,
    request_fingerprint, created_by_person_id
  ) values (
    p_order_id, p_store_id, 'draft', v_order_currency, v_order_total,
    p_request_fingerprint, p_actor_person_id
  ) returning id into v_transaction_id;

  insert into public.mme_pos_transaction_events(
    transaction_id, event_type, from_status, to_status,
    actor_person_id, event_fingerprint, metadata
  ) values (
    v_transaction_id, 'transaction_created', null, 'draft',
    p_actor_person_id, p_idempotency_key,
    jsonb_build_object('order_id', p_order_id, 'store_id', p_store_id)
  ) returning id into v_event_id;

  insert into public.mme_pos_outbox(transaction_id, event_id, event_type, payload)
  values (
    v_transaction_id, v_event_id, 'pos.transaction.created',
    jsonb_build_object('transaction_id', v_transaction_id, 'order_id', p_order_id)
  );

  return v_transaction_id;
end;
$$;

revoke all on function public.mme_pos_reject_event_mutation() from public, anon, authenticated;
revoke all on function public.mme_pos_create_transaction(uuid,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.mme_pos_create_transaction(uuid,uuid,uuid,text,text) to service_role;

alter table public.mme_pos_transactions enable row level security;
alter table public.mme_pos_tender_allocations enable row level security;
alter table public.mme_pos_transaction_events enable row level security;
alter table public.mme_pos_outbox enable row level security;

revoke all on public.mme_pos_transactions from anon, authenticated;
revoke all on public.mme_pos_tender_allocations from anon, authenticated;
revoke all on public.mme_pos_transaction_events from anon, authenticated;
revoke all on public.mme_pos_outbox from anon, authenticated;

grant all on public.mme_pos_transactions to service_role;
grant all on public.mme_pos_tender_allocations to service_role;
grant all on public.mme_pos_transaction_events to service_role;
grant all on public.mme_pos_outbox to service_role;

comment on table public.mme_pos_transactions is
  'Build 009 POS orchestration envelope; Build 001 mme_orders remains authoritative order ledger.';
comment on table public.mme_pos_tender_allocations is
  'Build 009 references to Payments Center tender operations; not a substitute for provider payment truth.';
comment on table public.mme_pos_transaction_events is
  'Build 009 append-only transaction transition audit history.';
comment on table public.mme_pos_outbox is
  'Build 009 transactional outbox for downstream idempotent consumers.';

commit;
