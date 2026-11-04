-- Build 001: serialized device unit ledger.
-- This migration records each physical IMEI/serial-tracked unit separately.
-- Serialized checkout remains disabled until dedicated order reservation and
-- payment-consumption RPCs are reviewed and tested in a disposable database.

create table public.mme_serialized_units (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  serial_number text not null,
  imei text,
  condition_grade text not null
    check (condition_grade in ('new','open_box','refurbished','used')),
  unit_status text not null default 'in_stock'
    check (unit_status in ('in_stock','reserved','sold','repair','quarantine')),
  received_at timestamptz not null default now(),
  sold_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (serial_number),
  check (serial_number = btrim(serial_number) and length(serial_number) between 1 and 128),
  check (imei is null or (imei = btrim(imei) and length(imei) between 8 and 20))
);

create unique index mme_serialized_units_imei_unique
  on public.mme_serialized_units(imei) where imei is not null;
create index mme_serialized_units_product_location_status_idx
  on public.mme_serialized_units(product_id,location_id,unit_status);

create table public.mme_serialized_unit_reservations (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.mme_inventory_reservations(id) on delete restrict,
  order_id uuid not null references public.mme_orders(id) on delete restrict,
  unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
  serial_snapshot text not null,
  imei_snapshot text,
  status text not null default 'active'
    check (status in ('active','consumed','released','expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index mme_serialized_unit_reservations_one_active_unit
  on public.mme_serialized_unit_reservations(unit_id) where status='active';
create index mme_serialized_unit_reservations_order_idx
  on public.mme_serialized_unit_reservations(order_id,status);

alter table public.mme_serialized_units enable row level security;
alter table public.mme_serialized_unit_reservations enable row level security;
revoke all on public.mme_serialized_units from anon,authenticated;
revoke all on public.mme_serialized_unit_reservations from anon,authenticated;
grant all on public.mme_serialized_units to service_role;
grant all on public.mme_serialized_unit_reservations to service_role;

-- Server-only intake. IMEI is optional for non-phone serialized devices.
create or replace function public.mme_receive_serialized_unit(
  p_product_id uuid,
  p_location_id uuid,
  p_serial_number text,
  p_imei text,
  p_condition_grade text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if p_product_id is null or p_location_id is null
     or p_serial_number is null or p_serial_number<>btrim(p_serial_number)
     or length(p_serial_number) not between 1 and 128
     or p_imei is not null and (p_imei<>btrim(p_imei) or length(p_imei) not between 8 and 20)
     or p_condition_grade not in ('new','open_box','refurbished','used') then
    raise exception 'Invalid serialized unit intake' using errcode='22023';
  end if;

  perform 1 from public.mme_products
   where id=p_product_id and active=true and serialized=true for update;
  if not found then raise exception 'Active serialized product not found' using errcode='P0002'; end if;

  perform 1 from public.mme_store_locations where id=p_location_id and active=true;
  if not found then raise exception 'Active store location not found' using errcode='P0002'; end if;

  insert into public.mme_serialized_units(product_id,location_id,serial_number,imei,condition_grade)
  values(p_product_id,p_location_id,p_serial_number,p_imei,p_condition_grade)
  returning id into v_id;
  return v_id;
end; $$;

revoke all on function public.mme_receive_serialized_unit(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_receive_serialized_unit(uuid,uuid,text,text,text) to service_role;

comment on table public.mme_serialized_units is
  'One row per physical serialized device. Never use aggregate quantity for IMEI/serial-controlled units.';
comment on table public.mme_serialized_unit_reservations is
  'Immutable device identity snapshots and reservation lifecycle records for serialized checkout.';
