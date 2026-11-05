-- Build 009: durable POS transaction orchestration primitives.
-- Additive only. Uses Build 001 orders/reservations as authoritative records.
-- This migration does not connect a payment provider or enable live checkout.

begin;

create table public.mme_pos_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.mme_orders(id) on delete restrict,
  idempotency_key text not null unique,
  created_by_person_id uuid not null,
  status text not null default 'inventory_reserved'
    check (status in (
      'inventory_reserved','pricing_confirmed','tendering','partially_tendered',
      'fully_tendered','finalization_pending','finalized',
      'reconciliation_required','cancelled'
    )),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_cents bigint not null default 0 check (total_cents >= 0),
  revision bigint not null default 0 check (revision >= 0),
  calculation_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finalized_at timestamptz
);

create table public.mme_pos_transaction_events (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
  revision bigint not null check (revision > 0),
  event_type text not null check (event_type in (
    'pricing_confirmed','tender_submitted','tender_result',
    'reconciliation_result','finalization_started','finalization_confirmed','cancelled'
  )),
  idempotency_key text not null,
  actor_person_id uuid not null,
  previous_status text not null,
  next_status text not null,
  event_data jsonb not null default '{}'::jsonb
    check (jsonb_typeof(event_data) = 'object'),
  request_fingerprint text not null,
  created_at timestamptz not null default now(),
  unique (transaction_id, revision),
  unique (transaction_id, idempotency_key)
);

create table public.mme_pos_outbox (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
  transaction_event_id uuid not null unique references public.mme_pos_transaction_events(id) on delete restrict,
  event_type text not null,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending','processing','delivered','failed','dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  last_error_code text
);

create index mme_pos_events_transaction_idx
  on public.mme_pos_transaction_events(transaction_id, revision);
create index mme_pos_outbox_delivery_idx
  on public.mme_pos_outbox(delivery_status, available_at, created_at);

alter table public.mme_pos_transactions enable row level security;
alter table public.mme_pos_transaction_events enable row level security;
alter table public.mme_pos_outbox enable row level security;

revoke all on public.mme_pos_transactions, public.mme_pos_transaction_events, public.mme_pos_outbox
  from public, anon, authenticated;
grant all on public.mme_pos_transactions, public.mme_pos_transaction_events, public.mme_pos_outbox
  to service_role;

-- Build 004 person-keyed authorization gate for POS actions.
-- Actor IDs are resolved by the trusted server from the authenticated subject;
-- these SECURITY DEFINER functions are callable only by service_role.
create or replace function public.mme_person_authorize_pos_action(
  p_actor_person_id uuid,
  p_permission_key text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $
declare
  v_person_status text;
  v_ceo_person_id uuid;
  v_frozen boolean;
  v_employment_status text;
begin
  if p_actor_person_id is null
     or p_permission_key not in (
       'pos.transaction.create','pos.transaction.price','pos.tender.create',
       'pos.tender.capture','pos.tender.reconcile','pos.transaction.finalize',
       'pos.transaction.cancel'
     ) then
    return false;
  end if;

  select lifecycle_status into v_person_status
    from public.mme_person_identities
   where person_id = p_actor_person_id;

  if not found or v_person_status is distinct from 'active' then
    return false;
  end if;

  select ceo_person_id, employee_access_frozen
    into v_ceo_person_id, v_frozen
    from public.employee_security_settings
   where singleton = true;

  if not found or v_frozen is distinct from false or v_ceo_person_id is null then
    return false;
  end if;

  select employment_status into v_employment_status
    from public.employee_relationships
   where person_id = p_actor_person_id;

  if v_employment_status is distinct from 'active' then
    return false;
  end if;

  if p_actor_person_id = v_ceo_person_id then
    return true;
  end if;

  return exists (
    select 1
      from public.employee_permission_grants g
     where g.person_id = p_actor_person_id
       and g.permission_key = p_permission_key
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and g.scope = '{}'::jsonb
  );
end;
$;

revoke all on function public.mme_person_authorize_pos_action(uuid,text)
  from public, anon, authenticated;
grant execute on function public.mme_person_authorize_pos_action(uuid,text)
  to service_role;

create or replace function public.mme_pos_create_transaction(
  p_order_id uuid,
  p_idempotency_key text,
  p_actor_person_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_order public.mme_orders%rowtype;
  v_existing_id uuid;
  v_existing_key text;
  v_transaction_id uuid;
begin
  if p_order_id is null or p_actor_person_id is null
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(p_idempotency_key) > 128 then
    raise exception 'Invalid POS transaction creation request' using errcode = '22023';
  end if;

  if not public.mme_person_authorize_pos_action(p_actor_person_id, 'pos.transaction.create') then
    raise exception 'POS transaction creation permission denied' using errcode = '42501';
  end if;

  select * into v_order
    from public.mme_orders
   where id = p_order_id
   for update;

  if not found or v_order.status <> 'pending_payment' then
    raise exception 'Pending order not found' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.mme_inventory_reservations r
     where r.order_id = p_order_id and r.status = 'active' and r.expires_at > now()
  ) then
    raise exception 'Active inventory reservation required' using errcode = 'P0001';
  end if;

  select id, idempotency_key into v_existing_id, v_existing_key
    from public.mme_pos_transactions
   where order_id = p_order_id or idempotency_key = p_idempotency_key
   for update;

  if found then
    if v_existing_key <> p_idempotency_key then
      raise exception 'Order already has a POS transaction with another idempotency key' using errcode = '23505';
    end if;
    return v_existing_id;
  end if;

  insert into public.mme_pos_transactions(
    order_id, idempotency_key, created_by_person_id, status, currency, total_cents
  ) values (
    p_order_id, p_idempotency_key, p_actor_person_id,
    'inventory_reserved', v_order.currency, v_order.total_cents
  )
  returning id into v_transaction_id;

  return v_transaction_id;
end;
$$;

create or replace function public.mme_pos_append_transaction_event(
  p_transaction_id uuid,
  p_expected_revision bigint,
  p_event_type text,
  p_idempotency_key text,
  p_actor_person_id uuid,
  p_next_status text,
  p_event_data jsonb default '{}'::jsonb
)
returns table(transaction_id uuid, revision bigint, status text, event_id uuid, replayed boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_tx public.mme_pos_transactions%rowtype;
  v_existing public.mme_pos_transaction_events%rowtype;
  v_fingerprint text;
  v_allowed boolean := false;
  v_event_id uuid;
  v_revision bigint;
begin
  if p_transaction_id is null or p_expected_revision is null or p_expected_revision < 0
     or p_actor_person_id is null or p_idempotency_key is null
     or length(btrim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 128
     or p_event_data is null or jsonb_typeof(p_event_data) <> 'object'
     or p_event_type is null or p_next_status is null then
    raise exception 'Invalid POS transaction event request' using errcode = '22023';
  end if;

  if not public.mme_person_authorize_pos_action(
    p_actor_person_id,
    case p_event_type
      when 'pricing_confirmed' then 'pos.transaction.price'
      when 'tender_submitted' then 'pos.tender.create'
      when 'tender_result' then 'pos.tender.capture'
      when 'reconciliation_result' then 'pos.tender.reconcile'
      when 'finalization_started' then 'pos.transaction.finalize'
      when 'finalization_confirmed' then 'pos.transaction.finalize'
      when 'cancelled' then 'pos.transaction.cancel'
      else null
    end
  ) then
    raise exception 'POS transaction event permission denied' using errcode = '42501';
  end if;

  if p_event_data::text ~* '("?(pan|card_number|cvv|cvc|pin|track_data|raw_card_data)"?[[:space:]]*:)'
  then
    raise exception 'Sensitive payment data is not permitted in POS event payloads' using errcode = '22023';
  end if;

  select * into v_tx
    from public.mme_pos_transactions
   where id = p_transaction_id
   for update;

  if not found then
    raise exception 'POS transaction not found' using errcode = 'P0002';
  end if;

  v_fingerprint := md5(jsonb_build_object(
    'event_type', p_event_type,
    'next_status', p_next_status,
    'actor_person_id', p_actor_person_id,
    'event_data', p_event_data
  )::text);

  select * into v_existing
    from public.mme_pos_transaction_events
   where transaction_id = p_transaction_id and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception 'POS idempotency key reused with different request' using errcode = '23505';
    end if;
    return query select v_tx.id, v_existing.revision, v_tx.status, v_existing.id, true;
    return;
  end if;

  if v_tx.revision <> p_expected_revision then
    raise exception 'POS transaction revision conflict' using errcode = '40001';
  end if;

  v_allowed := case
    when v_tx.status = 'inventory_reserved' and p_event_type = 'pricing_confirmed' and p_next_status = 'pricing_confirmed' then true
    when v_tx.status in ('pricing_confirmed','partially_tendered') and p_event_type = 'tender_submitted' and p_next_status = 'tendering' then true
    when v_tx.status = 'tendering' and p_event_type = 'tender_result' and p_next_status in ('partially_tendered','fully_tendered','reconciliation_required') then true
    when v_tx.status = 'reconciliation_required' and p_event_type = 'reconciliation_result' and p_next_status in ('partially_tendered','fully_tendered','reconciliation_required') then true
    when v_tx.status = 'fully_tendered' and p_event_type = 'finalization_started' and p_next_status = 'finalization_pending' then true
    when v_tx.status = 'finalization_pending' and p_event_type = 'finalization_confirmed' and p_next_status = 'finalized' then true
    when v_tx.status in ('inventory_reserved','pricing_confirmed','partially_tendered') and p_event_type = 'cancelled' and p_next_status = 'cancelled' then true
    else false
  end;

  if not v_allowed then
    raise exception 'Invalid POS transaction state transition' using errcode = '23514';
  end if;

  if p_event_type = 'pricing_confirmed' then
    if coalesce((p_event_data ->> 'total_cents')::bigint, 0) <= 0
       or (p_event_data ->> 'total_cents')::bigint <> v_tx.total_cents
       or nullif(p_event_data ->> 'calculation_reference','') is null then
      raise exception 'Trusted pricing snapshot must match authoritative order total' using errcode = '22023';
    end if;
    update public.mme_pos_transactions
       set calculation_reference = p_event_data ->> 'calculation_reference'
     where id = p_transaction_id;
  end if;

  if p_event_type = 'finalization_confirmed' then
    update public.mme_pos_transactions
       set finalized_at = now()
     where id = p_transaction_id;
  end if;

  insert into public.mme_pos_transaction_events(
    transaction_id, revision, event_type, idempotency_key, actor_person_id,
    previous_status, next_status, event_data, request_fingerprint
  ) values (
    p_transaction_id, v_tx.revision + 1, p_event_type, p_idempotency_key,
    p_actor_person_id, v_tx.status, p_next_status, p_event_data, v_fingerprint
  ) returning id into v_event_id;

  update public.mme_pos_transactions
     set status = p_next_status, revision = revision + 1, updated_at = now()
   where id = p_transaction_id
  returning mme_pos_transactions.revision into v_revision;

  insert into public.mme_pos_outbox(transaction_id, transaction_event_id, event_type, payload)
  values (
    p_transaction_id, v_event_id, p_event_type,
    jsonb_build_object(
      'transaction_id', p_transaction_id,
      'event_id', v_event_id,
      'revision', v_revision,
      'event_type', p_event_type,
      'status', p_next_status
    )
  );

  return query select p_transaction_id, v_revision, p_next_status, v_event_id, false;
end;
$$;

revoke all on function public.mme_pos_create_transaction(uuid,text,uuid) from public, anon, authenticated;
revoke all on function public.mme_pos_append_transaction_event(uuid,bigint,text,text,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.mme_pos_create_transaction(uuid,text,uuid) to service_role;
grant execute on function public.mme_pos_append_transaction_event(uuid,bigint,text,text,uuid,text,jsonb) to service_role;

comment on table public.mme_pos_transactions is
  'Build 009 POS orchestration projection. References Build 001 order; not a competing order or payment ledger.';
comment on table public.mme_pos_transaction_events is
  'Build 009 append-only-by-contract POS state transition and audit history; provider raw payloads and card data prohibited.';
comment on table public.mme_pos_outbox is
  'Build 009 durable downstream event queue. Delivery does not determine payment or inventory truth.';

commit;
