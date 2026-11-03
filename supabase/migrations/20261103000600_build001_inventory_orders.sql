-- Build 001: authoritative catalog, orders, reservations, and payment-event ledger.
-- Apply only to a disposable/development Supabase project after review.
-- This migration is additive. It does not connect Stripe or enable customer checkout.

create table public.mme_store_locations (
  id uuid primary key default gen_random_uuid(),
  location_code text not null unique,
  display_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.mme_products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  title text not null,
  description text,
  category_key text,
  condition_grade text not null default 'new'
    check (condition_grade in ('new','open_box','refurbished','used')),
  unit_price_cents bigint not null check (unit_price_cents >= 0),
  currency text not null default 'USD' check (currency = 'USD'),
  serialized boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.mme_inventory_balances (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  on_hand_quantity integer not null default 0 check (on_hand_quantity >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0),
  updated_at timestamptz not null default now(),
  unique (product_id, location_id),
  check (reserved_quantity <= on_hand_quantity)
);

create table public.mme_orders (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  customer_identity_id uuid,
  status text not null default 'pending_payment'
    check (status in ('pending_payment','paid','payment_failed','cancelled','expired','partially_refunded','refunded','disputed')),
  currency text not null default 'USD' check (currency = 'USD'),
  subtotal_cents bigint not null check (subtotal_cents >= 0),
  tax_cents bigint not null default 0 check (tax_cents >= 0),
  fulfillment_cents bigint not null default 0 check (fulfillment_cents >= 0),
  discount_cents bigint not null default 0 check (discount_cents >= 0),
  total_cents bigint not null check (total_cents >= 0),
  fulfillment_method text not null check (fulfillment_method in ('pickup','shipping')),
  fulfillment_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.mme_order_lines (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.mme_orders(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  sku_snapshot text not null,
  title_snapshot text not null,
  condition_snapshot text not null,
  quantity integer not null check (quantity > 0),
  unit_price_cents bigint not null check (unit_price_cents >= 0),
  line_total_cents bigint not null check (line_total_cents >= 0),
  created_at timestamptz not null default now()
);

create table public.mme_inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.mme_orders(id) on delete restrict,
  status text not null default 'active'
    check (status in ('active','consumed','released','expired')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create table public.mme_inventory_reservation_lines (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.mme_inventory_reservations(id) on delete restrict,
  inventory_balance_id uuid not null references public.mme_inventory_balances(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),
  unique (reservation_id, inventory_balance_id)
);

create table public.mme_payment_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('stripe')),
  provider_event_id text not null,
  event_type text not null,
  provider_object_id text,
  order_id uuid references public.mme_orders(id) on delete restrict,
  processing_status text not null default 'received'
    check (processing_status in ('received','processed','ignored','failed')),
  payload_sha256 text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider, provider_event_id)
);

create index mme_orders_status_created_idx on public.mme_orders(status, created_at desc);
create index mme_order_lines_order_idx on public.mme_order_lines(order_id);
create index mme_inventory_balances_product_idx on public.mme_inventory_balances(product_id);
create index mme_inventory_reservations_expiry_idx on public.mme_inventory_reservations(status, expires_at);
create index mme_payment_events_status_received_idx on public.mme_payment_events(processing_status, received_at);

-- Atomically reserve stock for an already-created pending order.
-- A failure rolls back all balance changes and reservation records.
create or replace function public.mme_reserve_inventory(
  p_order_id uuid,
  p_items jsonb,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reservation_id uuid;
  v_item record;
  v_balance_id uuid;
  v_on_hand integer;
  v_reserved integer;
begin
  if p_order_id is null or p_items is null or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 50 then
    raise exception 'Invalid reservation request' using errcode = '22023';
  end if;

  if p_expires_at is null or p_expires_at <= now()
     or p_expires_at > now() + interval '30 minutes' then
    raise exception 'Reservation expiry must be within the next 30 minutes' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(product_id uuid, location_id uuid, quantity integer)
    group by x.product_id, x.location_id
    having count(*) > 1
  ) then
    raise exception 'Duplicate product/location reservation line' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(product_id uuid, location_id uuid, quantity integer)
    where x.product_id is null or x.location_id is null
       or x.quantity is null or x.quantity < 1 or x.quantity > 20
  ) then
    raise exception 'Invalid product, location, or quantity' using errcode = '22023';
  end if;

  perform 1
  from public.mme_orders o
  where o.id = p_order_id and o.status = 'pending_payment'
  for update;

  if not found then
    raise exception 'Pending order not found' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.mme_inventory_reservations r where r.order_id = p_order_id) then
    raise exception 'Order already has a reservation' using errcode = '23505';
  end if;

  insert into public.mme_inventory_reservations(order_id, expires_at)
  values (p_order_id, p_expires_at)
  returning id into v_reservation_id;

  for v_item in
    select x.product_id, x.location_id, x.quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid, location_id uuid, quantity integer)
    order by x.product_id, x.location_id
  loop
    select b.id, b.on_hand_quantity, b.reserved_quantity
      into v_balance_id, v_on_hand, v_reserved
    from public.mme_products p
    join public.mme_inventory_balances b on b.product_id = p.id
    where p.id = v_item.product_id
      and p.active = true
      and p.serialized = false
      and b.location_id = v_item.location_id
      and (select l.active from public.mme_store_locations l where l.id = b.location_id) = true
    for update of p, b;

    if not found then
      raise exception 'Product or location unavailable' using errcode = 'P0002';
    end if;

    if v_on_hand - v_reserved < v_item.quantity then
      raise exception 'Insufficient available inventory' using errcode = 'P0001';
    end if;

    update public.mme_inventory_balances
      set reserved_quantity = reserved_quantity + v_item.quantity,
          updated_at = now()
    where id = v_balance_id;

    insert into public.mme_inventory_reservation_lines(
      reservation_id, inventory_balance_id, product_id, location_id, quantity
    ) values (
      v_reservation_id, v_balance_id, v_item.product_id, v_item.location_id, v_item.quantity
    );
  end loop;

  return v_reservation_id;
end;
$$;

revoke all on function public.mme_reserve_inventory(uuid, jsonb, timestamptz) from public;
revoke all on function public.mme_reserve_inventory(uuid, jsonb, timestamptz) from anon;
revoke all on function public.mme_reserve_inventory(uuid, jsonb, timestamptz) from authenticated;
grant execute on function public.mme_reserve_inventory(uuid, jsonb, timestamptz) to service_role;

-- No direct browser access. All writes must pass through trusted server-side services.
alter table public.mme_store_locations enable row level security;
alter table public.mme_products enable row level security;
alter table public.mme_inventory_balances enable row level security;
alter table public.mme_orders enable row level security;
alter table public.mme_order_lines enable row level security;
alter table public.mme_inventory_reservations enable row level security;
alter table public.mme_inventory_reservation_lines enable row level security;
alter table public.mme_payment_events enable row level security;

revoke all on public.mme_store_locations from anon, authenticated;
revoke all on public.mme_products from anon, authenticated;
revoke all on public.mme_inventory_balances from anon, authenticated;
revoke all on public.mme_orders from anon, authenticated;
revoke all on public.mme_order_lines from anon, authenticated;
revoke all on public.mme_inventory_reservations from anon, authenticated;
revoke all on public.mme_inventory_reservation_lines from anon, authenticated;
revoke all on public.mme_payment_events from anon, authenticated;

grant all on public.mme_store_locations to service_role;
grant all on public.mme_products to service_role;
grant all on public.mme_inventory_balances to service_role;
grant all on public.mme_orders to service_role;
grant all on public.mme_order_lines to service_role;
grant all on public.mme_inventory_reservations to service_role;
grant all on public.mme_inventory_reservation_lines to service_role;
grant all on public.mme_payment_events to service_role;
