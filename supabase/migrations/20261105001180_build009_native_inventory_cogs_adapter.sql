-- Build 009.38 — Native inventory costing and POS COGS adapter.
-- Adds landed-cost allocations, serialized unit cost records, sale-time cost snapshots,
-- and idempotent COGS export into Build 009.32 financial reporting.
begin;
create extension if not exists pgcrypto;

create or replace function public.mme_pos_authorize_hardware_action(
 p_actor_person_id uuid,p_permission_key text,p_location_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_person_status text; v_ceo_person_id uuid; v_frozen boolean; v_employment_status text;
begin
 if p_actor_person_id is null or p_location_id is null or p_permission_key not in (
  'pos.hardware.register','pos.hardware.command','pos.hardware.incident.view',
  'pos.hardware.incident.acknowledge','pos.hardware.incident.resolve','pos.hardware.admin',
  'pos.hardware.assign','pos.hardware.configure','pos.hardware.approve','pos.hardware.retire',
  'pos.network.view','pos.network.manage','pos.network.certificates','pos.network.incidents',
  'pos.security.view','pos.security.manage','pos.security.investigate','pos.security.contain','pos.security.rules.manage',
  'pos.fraud.view','pos.fraud.review','pos.fraud.rules.manage','pos.fraud.case.manage','pos.fraud.override',
  'pos.disputes.view','pos.disputes.manage','pos.disputes.evidence','pos.disputes.approve','pos.disputes.submit',
  'pos.settlement.view','pos.settlement.reconcile','pos.settlement.exception.manage','pos.settlement.approve',
  'pos.settlement.bank.match','pos.settlement.cash.manage','pos.settlement.close.prepare','pos.settlement.close.approve',
  'pos.settlement.adjustment.request','pos.finance.report.view','pos.finance.report.build','pos.finance.report.import',
  'pos.inventory.cost.view','pos.inventory.cost.manage','pos.inventory.cost.approve'
 ) then return false; end if;
 select lifecycle_status into v_person_status from public.mme_person_identities where person_id=p_actor_person_id;
 if not found or v_person_status is distinct from 'active' then return false; end if;
 select ceo_person_id,employee_access_frozen into v_ceo_person_id,v_frozen from public.employee_security_settings where singleton=true;
 if not found or v_frozen is distinct from false or v_ceo_person_id is null then return false; end if;
 select employment_status into v_employment_status from public.employee_relationships where person_id=p_actor_person_id;
 if v_employment_status is distinct from 'active' then return false; end if;
 if p_actor_person_id=v_ceo_person_id then return true; end if;
 return exists(select 1 from public.employee_permission_grants g where g.person_id=p_actor_person_id
  and g.permission_key=p_permission_key and g.revoked_at is null and (g.expires_at is null or g.expires_at>now())
  and (g.scope='{}'::jsonb or g.scope->>'location_id'=p_location_id::text));
end;
$$;

alter table public.mme_inventory_movements
 drop constraint if exists mme_inventory_movements_movement_type_check;
alter table public.mme_inventory_movements
 add constraint mme_inventory_movements_movement_type_check
 check(movement_type in ('receipt','adjustment_increase','adjustment_decrease','transfer_in','transfer_out',
  'damage','repair','quarantine','release_quarantine','sale'));

alter table public.mme_inventory_receipts
 add column if not exists landed_cost_total_cents bigint not null default 0 check(landed_cost_total_cents>=0);

create table public.mme_inventory_receipt_cost_components (
 id uuid primary key default gen_random_uuid(),
 receipt_id uuid not null references public.mme_inventory_receipts(id) on delete restrict,
 component_reference text not null check(length(btrim(component_reference)) between 1 and 120),
 component_type text not null check(component_type in ('freight','shipping','auction_fee','customs','refurbishment','insurance','other')),
 amount_cents bigint not null check(amount_cents>0),
 allocation_method text not null check(allocation_method in ('extended_cost','quantity')),
 actor_identity_id uuid not null,
 approved_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 unique(receipt_id,component_reference),
 check(actor_identity_id<>approved_by_identity_id)
);
create table public.mme_inventory_receipt_cost_allocations (
 id uuid primary key default gen_random_uuid(),
 component_id uuid not null references public.mme_inventory_receipt_cost_components(id) on delete restrict,
 movement_id uuid not null references public.mme_inventory_movements(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 quantity integer not null check(quantity>0),
 allocated_amount_cents bigint not null check(allocated_amount_cents>=0),
 average_cost_delta_cents bigint not null check(average_cost_delta_cents>=0),
 created_at timestamptz not null default now(),
 unique(component_id,movement_id)
);
alter table public.mme_inventory_receipt_cost_components enable row level security;
alter table public.mme_inventory_receipt_cost_allocations enable row level security;
revoke all on public.mme_inventory_receipt_cost_components,public.mme_inventory_receipt_cost_allocations from public,anon,authenticated;
grant all on public.mme_inventory_receipt_cost_components,public.mme_inventory_receipt_cost_allocations to service_role;

create or replace function public.mme_pos_allocate_receipt_landed_cost(
 p_receipt_id uuid,p_actor_person_id uuid,p_approved_by_person_id uuid,
 p_component_reference text,p_component_type text,p_amount_cents bigint,p_allocation_method text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_receipt public.mme_inventory_receipts%rowtype; v_component_id uuid; v_line record;
 v_total_weight numeric; v_remaining bigint; v_alloc bigint; v_delta bigint; v_balance record;
begin
 if p_receipt_id is null or p_actor_person_id is null or p_approved_by_person_id is null
  or p_actor_person_id=p_approved_by_person_id
  or p_component_reference is null or length(btrim(p_component_reference)) not between 1 and 120
  or p_component_type is null or p_allocation_method is null
  or p_component_type not in ('freight','shipping','auction_fee','customs','refurbishment','insurance','other')
  or p_amount_cents is null or p_amount_cents<=0
  or p_allocation_method not in ('extended_cost','quantity') then
  raise exception 'Invalid landed-cost allocation request' using errcode='22023';
 end if;
 select * into v_receipt from public.mme_inventory_receipts where id=p_receipt_id for update;
 if not found then raise exception 'Inventory receipt not found' using errcode='P0002'; end if;
 if not exists(select 1 from public.mme_inventory_movements where receipt_id=p_receipt_id and movement_type='receipt') then
  raise exception 'Receipt has no receiving movement records' using errcode='23514';
 end if;
 if exists(select 1 from public.mme_inventory_movements m where m.receipt_id=p_receipt_id and m.movement_type='receipt'
  and (not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.inventory.cost.manage',m.location_id)
   or not public.mme_pos_authorize_hardware_action(p_approved_by_person_id,'pos.inventory.cost.approve',m.location_id))) then
  raise exception 'Landed-cost management or approval permission denied for one or more stores' using errcode='42501';
 end if;
 if exists(select 1 from public.mme_inventory_receipt_cost_components where receipt_id=p_receipt_id and component_reference=btrim(p_component_reference)) then
  raise exception 'Landed-cost component reference already exists' using errcode='23505';
 end if;
 select sum(case when p_allocation_method='extended_cost' then quantity_delta::numeric*unit_cost_cents else quantity_delta::numeric end)
 into v_total_weight from public.mme_inventory_movements
 where receipt_id=p_receipt_id and movement_type='receipt';
 if coalesce(v_total_weight,0)<=0 then raise exception 'Receipt has no allocatable inventory lines' using errcode='23514'; end if;
 -- Do not rewrite historical COGS after a later stock movement; require cost capture before movement.
 if exists(
  select 1 from public.mme_inventory_movements r
  join public.mme_inventory_movements later on later.product_id=r.product_id and later.location_id=r.location_id
   and later.created_at>r.created_at and later.receipt_id is distinct from p_receipt_id
  where r.receipt_id=p_receipt_id and r.movement_type='receipt'
 ) then raise exception 'Landed cost must be recorded before subsequent inventory movements' using errcode='55000'; end if;
 insert into public.mme_inventory_receipt_cost_components(receipt_id,component_reference,component_type,amount_cents,
  allocation_method,actor_identity_id,approved_by_identity_id)
 values(p_receipt_id,btrim(p_component_reference),p_component_type,p_amount_cents,p_allocation_method,
  p_actor_person_id,p_approved_by_person_id) returning id into v_component_id;
 v_remaining:=p_amount_cents;
 for v_line in
  select m.id,m.product_id,m.location_id,m.quantity_delta as quantity,m.unit_cost_cents,
   case when p_allocation_method='extended_cost' then m.quantity_delta::numeric*m.unit_cost_cents
    else m.quantity_delta::numeric end as weight,
   row_number() over(order by m.id) as rn,count(*) over() as n
  from public.mme_inventory_movements m
  where m.receipt_id=p_receipt_id and m.movement_type='receipt'
  order by m.id
 loop
  if v_line.rn=v_line.n then v_alloc:=v_remaining;
  else v_alloc:=floor(p_amount_cents::numeric*v_line.weight/v_total_weight)::bigint; end if;
  v_remaining:=v_remaining-v_alloc;
  select id,on_hand_quantity,average_unit_cost_cents into v_balance from public.mme_inventory_balances
   where product_id=v_line.product_id and location_id=v_line.location_id for update;
  if not found or v_balance.on_hand_quantity<v_line.quantity then
   raise exception 'Receipt stock changed before landed-cost allocation' using errcode='55000';
  end if;
  v_delta:=round(v_alloc::numeric/v_balance.on_hand_quantity)::bigint;
  update public.mme_inventory_balances set average_unit_cost_cents=average_unit_cost_cents+v_delta,updated_at=now()
   where id=v_balance.id;
  insert into public.mme_inventory_receipt_cost_allocations(component_id,movement_id,product_id,location_id,
   quantity,allocated_amount_cents,average_cost_delta_cents)
  values(v_component_id,v_line.id,v_line.product_id,v_line.location_id,v_line.quantity,v_alloc,v_delta);
 end loop;
 update public.mme_inventory_receipts set landed_cost_total_cents=landed_cost_total_cents+p_amount_cents
  where id=p_receipt_id;
 return v_component_id;
end;
$$;

create table public.mme_inventory_serial_cost_units (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.mme_products(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 receipt_id uuid not null references public.mme_inventory_receipts(id) on delete restrict,
 serial_digest text check(serial_digest is null or serial_digest ~ '^[a-f0-9]{64}$'),
 serial_last4 text,
 imei_digest text check(imei_digest is null or imei_digest ~ '^[a-f0-9]{64}$'),
 imei_last4 text,
 unit_cost_cents bigint not null check(unit_cost_cents>=0),
 status text not null default 'available' check(status in ('available','reserved','sold','quarantined','returned')),
 reserved_order_id uuid references public.mme_orders(id) on delete restrict,
 sold_order_id uuid references public.mme_orders(id) on delete restrict,
 received_at timestamptz not null default now(),
 sold_at timestamptz,
 created_at timestamptz not null default now(),
 check(serial_digest is not null or imei_digest is not null),
 check((status='reserved')=(reserved_order_id is not null)),
 check((status='sold')=(sold_order_id is not null))
);
create unique index mme_inventory_serial_digest_unique on public.mme_inventory_serial_cost_units(serial_digest) where serial_digest is not null;
create unique index mme_inventory_imei_digest_unique on public.mme_inventory_serial_cost_units(imei_digest) where imei_digest is not null;
create index mme_inventory_serial_available_idx on public.mme_inventory_serial_cost_units(product_id,location_id,status,received_at);
create table public.mme_inventory_serial_cost_events (
 id uuid primary key default gen_random_uuid(),
 serial_unit_id uuid not null references public.mme_inventory_serial_cost_units(id) on delete restrict,
 event_type text not null check(event_type in ('received','reserved','released','sold','quarantined','returned')),
 actor_person_id uuid not null,
 order_id uuid references public.mme_orders(id) on delete restrict,
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 created_at timestamptz not null default now()
);
alter table public.mme_inventory_serial_cost_units enable row level security;
alter table public.mme_inventory_serial_cost_events enable row level security;
revoke all on public.mme_inventory_serial_cost_units,public.mme_inventory_serial_cost_events from public,anon,authenticated;
grant all on public.mme_inventory_serial_cost_units,public.mme_inventory_serial_cost_events to service_role;

create or replace function public.mme_pos_receive_serialized_inventory(
 p_receipt_reference text,p_supplier_reference text,p_source_type text,p_actor_person_id uuid,
 p_approved_by_person_id uuid,p_items jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public,extensions
as $$
declare v_receipt_id uuid; v_item record; v_product record; v_balance record; v_serial_id uuid; v_sum bigint:=0;
begin
 if p_receipt_reference is null or length(btrim(p_receipt_reference))<3 or length(p_receipt_reference)>100
  or p_source_type is null or p_source_type not in ('auction_pallet','supplier','customer_return','other')
  or p_actor_person_id is null or p_approved_by_person_id is null or p_actor_person_id=p_approved_by_person_id
  or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>200 then
  raise exception 'Invalid serialized receipt' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,serial_number text,imei text,unit_cost_cents bigint)
  where x.product_id is null or x.location_id is null or x.unit_cost_cents is null or x.unit_cost_cents<0
   or (nullif(btrim(x.serial_number),'') is null and nullif(btrim(x.imei),'') is null)
   or length(coalesce(x.serial_number,''))>120 or length(coalesce(x.imei,''))>32) then
  raise exception 'Invalid serialized inventory unit' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,serial_number text,imei text,unit_cost_cents bigint)
  group by lower(coalesce(nullif(btrim(x.serial_number),''),'')),lower(coalesce(nullif(btrim(x.imei),''),'')) having count(*)>1) then
  raise exception 'Duplicate serial or IMEI in receipt' using errcode='23505';
 end if;
 select sum(unit_cost_cents) into v_sum from jsonb_to_recordset(p_items) as x(unit_cost_cents bigint);
 insert into public.mme_inventory_receipts(receipt_reference,supplier_reference,source_type,purchase_total_cents,
  received_by_identity_id,approved_by_identity_id,notes)
 values(btrim(p_receipt_reference),p_supplier_reference,p_source_type,v_sum,p_actor_person_id,p_approved_by_person_id,p_notes)
 returning id into v_receipt_id;
 for v_item in select * from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,
  serial_number text,imei text,unit_cost_cents bigint) order by product_id,location_id,coalesce(serial_number,imei)
 loop
  select id,serialized,active into v_product from public.mme_products where id=v_item.product_id for update;
  if not found or not v_product.active or not v_product.serialized then
   raise exception 'Serialized receipt requires an active serialized product' using errcode='23514';
  end if;
  if not exists(select 1 from public.mme_store_locations where id=v_item.location_id and active=true) then
   raise exception 'Serialized receipt store is inactive' using errcode='P0002';
  end if;
  insert into public.mme_inventory_balances(product_id,location_id,on_hand_quantity,reserved_quantity,average_unit_cost_cents)
   values(v_item.product_id,v_item.location_id,0,0,0) on conflict(product_id,location_id) do nothing;
  select id,on_hand_quantity,reserved_quantity,average_unit_cost_cents into v_balance
   from public.mme_inventory_balances where product_id=v_item.product_id and location_id=v_item.location_id for update;
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity+1,
   average_unit_cost_cents=case when on_hand_quantity=0 then v_item.unit_cost_cents
    else round((on_hand_quantity::numeric*average_unit_cost_cents+v_item.unit_cost_cents)/(on_hand_quantity+1))::bigint end,
   updated_at=now() where id=v_balance.id;
  insert into public.mme_inventory_serial_cost_units(product_id,location_id,receipt_id,serial_digest,serial_last4,
   imei_digest,imei_last4,unit_cost_cents)
  values(v_item.product_id,v_item.location_id,v_receipt_id,
   case when nullif(btrim(v_item.serial_number),'') is null then null else encode(digest(lower(btrim(v_item.serial_number)),'sha256'),'hex') end,
   case when nullif(btrim(v_item.serial_number),'') is null then null else right(regexp_replace(v_item.serial_number,'[^A-Za-z0-9]','','g'),4) end,
   case when nullif(btrim(v_item.imei),'') is null then null else encode(digest(regexp_replace(v_item.imei,'[^0-9]','','g'),'sha256'),'hex') end,
   case when nullif(btrim(v_item.imei),'') is null then null else right(regexp_replace(v_item.imei,'[^0-9]','','g'),4) end,
   v_item.unit_cost_cents) returning id into v_serial_id;
  insert into public.mme_inventory_movements(product_id,location_id,movement_type,quantity_delta,on_hand_before,on_hand_after,
   reserved_before,reserved_after,unit_cost_cents,receipt_id,reason,reference_text,actor_identity_id,approved_by_identity_id)
  values(v_item.product_id,v_item.location_id,'receipt',1,v_balance.on_hand_quantity,v_balance.on_hand_quantity+1,
   v_balance.reserved_quantity,v_balance.reserved_quantity,v_item.unit_cost_cents,v_receipt_id,
   'Serialized inventory received',btrim(p_receipt_reference),p_actor_person_id,p_approved_by_person_id);
  insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id)
   values(v_serial_id,'received',p_actor_person_id);
 end loop;
 return v_receipt_id;
end;
$$;

alter table public.mme_order_lines
 add column if not exists inventory_serial_unit_id uuid references public.mme_inventory_serial_cost_units(id) on delete restrict;
create unique index if not exists mme_order_lines_serial_unit_unique on public.mme_order_lines(inventory_serial_unit_id)
 where inventory_serial_unit_id is not null;

create or replace function public.mme_pos_assign_serial_unit_to_order_line(
 p_order_line_id uuid,p_serial_unit_id uuid,p_actor_person_id uuid,p_expires_at timestamptz default now()+interval '15 minutes'
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_line public.mme_order_lines%rowtype; v_order public.mme_orders%rowtype;
 v_unit public.mme_inventory_serial_cost_units%rowtype; v_res public.mme_inventory_reservations%rowtype;
 v_balance public.mme_inventory_balances%rowtype;
begin
 select * into v_line from public.mme_order_lines where id=p_order_line_id for update;
 if not found then raise exception 'Order line not found' using errcode='P0002'; end if;
 select * into v_order from public.mme_orders where id=v_line.order_id for update;
 if not found or v_order.status<>'pending_payment' or v_line.quantity<>1 then
  raise exception 'Serial assignment requires one unit on a pending order line' using errcode='23514';
 end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.inventory.cost.manage',v_line.location_id) then
  raise exception 'Serial assignment permission denied' using errcode='42501';
 end if;
 if v_line.inventory_serial_unit_id=p_serial_unit_id then return true; end if;
 if v_line.inventory_serial_unit_id is not null then raise exception 'Order line already has a serial unit' using errcode='23505'; end if;
 select * into v_unit from public.mme_inventory_serial_cost_units where id=p_serial_unit_id for update;
 if not found or v_unit.product_id<>v_line.product_id or v_unit.location_id<>v_line.location_id or v_unit.status<>'available' then
  raise exception 'Serial unit is unavailable or does not match order line' using errcode='23514';
 end if;
 if not exists(select 1 from public.mme_products where id=v_line.product_id and serialized=true and active=true) then
  raise exception 'Order line product is not serialized' using errcode='23514';
 end if;
 if p_expires_at<=now() or p_expires_at>now()+interval '30 minutes' then
  raise exception 'Serial reservation expiry must be within 30 minutes' using errcode='22023';
 end if;
 select * into v_res from public.mme_inventory_reservations where order_id=v_order.id for update;
 if not found then
  insert into public.mme_inventory_reservations(order_id,status,expires_at) values(v_order.id,'active',p_expires_at)
  returning * into v_res;
 elsif v_res.status<>'active' or v_res.expires_at<=now() then
  raise exception 'Order inventory reservation is not active' using errcode='55000';
 end if;
 select * into v_balance from public.mme_inventory_balances where product_id=v_line.product_id and location_id=v_line.location_id for update;
 if not found or v_balance.on_hand_quantity-v_balance.reserved_quantity<1 then
  raise exception 'Serialized unit has no available inventory balance' using errcode='P0001';
 end if;
 update public.mme_inventory_balances set reserved_quantity=reserved_quantity+1,updated_at=now() where id=v_balance.id;
 insert into public.mme_inventory_reservation_lines(reservation_id,inventory_balance_id,product_id,location_id,quantity)
 values(v_res.id,v_balance.id,v_line.product_id,v_line.location_id,1)
 on conflict(reservation_id,inventory_balance_id) do update
 set quantity=public.mme_inventory_reservation_lines.quantity+1;
 update public.mme_inventory_serial_cost_units set status='reserved',reserved_order_id=v_order.id where id=v_unit.id;
 update public.mme_order_lines set inventory_serial_unit_id=v_unit.id where id=v_line.id;
 insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,order_id)
 values(v_unit.id,'reserved',p_actor_person_id,v_order.id);
 return true;
end;
$$;

create table public.mme_pos_inventory_cogs_snapshots (
 id uuid primary key default gen_random_uuid(),
 transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
 order_line_id uuid not null references public.mme_order_lines(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 sku_reference text not null,
 product_category text,
 quantity integer not null check(quantity>0),
 unit_cost_cents bigint not null check(unit_cost_cents>=0),
 total_cost_cents bigint not null check(total_cost_cents>=0),
 cost_method text not null check(cost_method in ('weighted_average','serialized_unit')),
 source_cost_reference text not null,
 created_at timestamptz not null default now(),
 unique(transaction_id,order_line_id)
);
create index mme_pos_inventory_cogs_location_created_idx on public.mme_pos_inventory_cogs_snapshots(location_id,created_at desc);
alter table public.mme_pos_inventory_cogs_snapshots enable row level security;
revoke all on public.mme_pos_inventory_cogs_snapshots from public,anon,authenticated;
grant all on public.mme_pos_inventory_cogs_snapshots to service_role;

create or replace function public.mme_pos_apply_inventory_sale_and_snapshot_cogs()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_order public.mme_orders%rowtype; v_res public.mme_inventory_reservations%rowtype;
 v_line record; v_balance public.mme_inventory_balances%rowtype; v_unit public.mme_inventory_serial_cost_units%rowtype;
 v_unit_cost bigint; v_total bigint; v_method text;
begin
 if new.status='finalized' and old.status is distinct from 'finalized' then
  select * into v_order from public.mme_orders where id=new.order_id for update;
  if not found then raise exception 'Finalized POS order not found' using errcode='P0002'; end if;
  select * into v_res from public.mme_inventory_reservations where order_id=v_order.id and status='active' and expires_at>now() for update;
  if not found then raise exception 'Active inventory reservation required at POS finalization' using errcode='23514'; end if;
  for v_line in
   select l.id,l.product_id,l.location_id,l.quantity,l.sku_snapshot,
    coalesce(p.category_key,'uncategorized') product_category,p.serialized,l.inventory_serial_unit_id
   from public.mme_order_lines l join public.mme_products p on p.id=l.product_id
   where l.order_id=v_order.id order by l.id
  loop
   select * into v_balance from public.mme_inventory_balances
    where product_id=v_line.product_id and location_id=v_line.location_id for update;
   if not found or v_balance.on_hand_quantity<v_line.quantity or v_balance.reserved_quantity<v_line.quantity then
    raise exception 'Inventory reservation and on-hand balance do not cover finalized sale' using errcode='23514';
   end if;
   if v_line.serialized then
    if v_line.quantity<>1 or v_line.inventory_serial_unit_id is null then
     raise exception 'Serialized POS line requires one assigned serial/IMEI unit' using errcode='23514';
    end if;
    select * into v_unit from public.mme_inventory_serial_cost_units where id=v_line.inventory_serial_unit_id for update;
    if not found or v_unit.status<>'reserved' or v_unit.reserved_order_id<>v_order.id
     or v_unit.product_id<>v_line.product_id or v_unit.location_id<>v_line.location_id then
     raise exception 'Serialized inventory unit reservation is inconsistent' using errcode='23514';
    end if;
    v_unit_cost:=v_unit.unit_cost_cents; v_method:='serialized_unit';
    update public.mme_inventory_serial_cost_units set status='sold',reserved_order_id=null,
     sold_order_id=v_order.id,sold_at=coalesce(new.finalized_at,now()) where id=v_unit.id;
    insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,order_id)
     values(v_unit.id,'sold',new.created_by_person_id,v_order.id);
   else
    if v_line.inventory_serial_unit_id is not null then raise exception 'Non-serialized product cannot carry serial unit' using errcode='23514'; end if;
    v_unit_cost:=v_balance.average_unit_cost_cents; v_method:='weighted_average';
   end if;
   v_total:=v_unit_cost*v_line.quantity;
   update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity-v_line.quantity,
    reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now() where id=v_balance.id;
   insert into public.mme_inventory_movements(product_id,location_id,movement_type,quantity_delta,on_hand_before,on_hand_after,
    reserved_before,reserved_after,unit_cost_cents,reason,reference_text,actor_identity_id)
   values(v_line.product_id,v_line.location_id,'sale',-v_line.quantity,v_balance.on_hand_quantity,
    v_balance.on_hand_quantity-v_line.quantity,v_balance.reserved_quantity,v_balance.reserved_quantity-v_line.quantity,
    v_unit_cost,'Finalized POS sale',new.id::text,new.created_by_person_id);
   insert into public.mme_pos_inventory_cogs_snapshots(transaction_id,order_line_id,location_id,product_id,sku_reference,
    product_category,quantity,unit_cost_cents,total_cost_cents,cost_method,source_cost_reference)
   values(new.id,v_line.id,v_line.location_id,v_line.product_id,left(v_line.sku_snapshot,160),
    left(v_line.product_category,120),v_line.quantity,v_unit_cost,v_total,v_method,
    case when v_method='serialized_unit' then 'serial-unit:'||v_unit.id::text else 'inventory-balance:'||v_balance.id::text end);
  end loop;
  update public.mme_inventory_reservations set status='consumed',updated_at=now() where id=v_res.id;
 elsif new.status='cancelled' and old.status is distinct from 'cancelled' then
  for v_unit in select * from public.mme_inventory_serial_cost_units where reserved_order_id=new.order_id and status='reserved' for update
  loop
   update public.mme_inventory_serial_cost_units set status='available',reserved_order_id=null where id=v_unit.id;
   insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,order_id)
    values(v_unit.id,'released',new.created_by_person_id,new.order_id);
  end loop;
  update public.mme_inventory_reservations set status='released',updated_at=now()
   where order_id=new.order_id and status='active';
  update public.mme_inventory_balances b set reserved_quantity=greatest(0,b.reserved_quantity-rl.quantity),updated_at=now()
   from public.mme_inventory_reservation_lines rl join public.mme_inventory_reservations r on r.id=rl.reservation_id
   where r.order_id=new.order_id and b.id=rl.inventory_balance_id and r.status='released';
 end if;
 return new;
end;
$$;
drop trigger if exists mme_pos_inventory_sale_cogs_after_status on public.mme_pos_transactions;
create trigger mme_pos_inventory_sale_cogs_after_status after update of status on public.mme_pos_transactions
 for each row execute function public.mme_pos_apply_inventory_sale_and_snapshot_cogs();

create or replace function public.mme_pos_export_finalized_transaction_financial_facts(
 p_transaction_id uuid,p_lease_token uuid,p_worker_person_id uuid,p_business_timezone text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public,extensions
as $$
declare
 v_export public.mme_pos_financial_pos_exports%rowtype;
 v_tx public.mme_pos_transactions%rowtype;
 v_order public.mme_orders%rowtype;
 v_line record; v_refund record;
 v_line_count integer; v_distinct_locations integer; v_line_total bigint;
 v_captured_total bigint; v_bad_tenders integer;
 v_digest text; v_reference text; v_fact_count integer:=0; v_safe_code text:='NATIVE_POS_EXPORT_FAILED';
 v_sqlstate text;
begin
 select * into v_export from public.mme_pos_financial_pos_exports
 where transaction_id=p_transaction_id for update;
 if not found or v_export.status<>'processing' or v_export.lease_token is distinct from p_lease_token
  or v_export.lease_expires_at is null or v_export.lease_expires_at<now() then
  raise exception 'Native POS financial export lease is invalid' using errcode='40001';
 end if;
 if not public.mme_pos_authorize_hardware_action(p_worker_person_id,'pos.finance.report.import',v_export.location_id) then
  raise exception 'Native POS financial export permission denied' using errcode='42501';
 end if;
 select * into v_tx from public.mme_pos_transactions where id=p_transaction_id for update;
 if not found or v_tx.status<>'finalized' or v_tx.finalized_at is null then
  raise exception 'Only finalized POS transactions can be exported' using errcode='55000';
 end if;
 if v_tx.location_id is null or v_tx.location_id<>v_export.location_id then
  raise exception 'POS transaction store attribution is missing or inconsistent' using errcode='23514';
 end if;
 if not exists(select 1 from pg_timezone_names where name=p_business_timezone) then
  raise exception 'Invalid store business timezone' using errcode='22023';
 end if;
 select * into v_order from public.mme_orders where id=v_tx.order_id;
 if not found or v_order.currency<>v_tx.currency or v_order.total_cents<>v_tx.total_cents then
  raise exception 'POS order and transaction totals do not match' using errcode='23514';
 end if;
 select count(*),count(distinct location_id),coalesce(sum(line_total_cents),0)
 into v_line_count,v_distinct_locations,v_line_total
 from public.mme_order_lines where order_id=v_order.id;
 if v_line_count<1 or v_distinct_locations<>1 or v_line_total<>v_order.subtotal_cents
  or exists(select 1 from public.mme_order_lines where order_id=v_order.id and location_id<>v_tx.location_id) then
  raise exception 'POS order lines are incomplete or cross-store' using errcode='23514';
 end if;
 select coalesce(sum(captured_amount_minor),0),
  count(*) filter(where status not in ('captured','partially_refunded','refunded'))
 into v_captured_total,v_bad_tenders
 from public.mme_pos_tender_attempts where transaction_id=p_transaction_id;
 if v_captured_total<>v_order.total_cents or v_bad_tenders<>0
  or not exists(select 1 from public.mme_pos_tender_attempts where transaction_id=p_transaction_id) then
  raise exception 'POS transaction does not have a fully captured and resolved tender ledger' using errcode='23514';
 end if;

 for v_line in
  select l.id,l.sku_snapshot,l.quantity,l.unit_price_cents,l.line_total_cents,l.condition_snapshot,
   coalesce(p.category_key,'uncategorized') as product_category
  from public.mme_order_lines l join public.mme_products p on p.id=l.product_id
  where l.order_id=v_order.id order by l.id
 loop
  v_reference:='pos:'||p_transaction_id::text||':line:'||v_line.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'line_id',v_line.id,
   'sku',v_line.sku_snapshot,'quantity',v_line.quantity,'unit_price_cents',v_line.unit_price_cents,
   'line_total_cents',v_line.line_total_cents,'condition',v_line.condition_snapshot,
   'product_category',v_line.product_category,'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'gross_sale',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,v_line.line_total_cents,v_line.quantity::bigint*1000,
   left(v_line.product_category,120),left(v_line.sku_snapshot,160),v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end loop;

 if v_order.fulfillment_cents>0 then
  v_reference:='pos:'||p_transaction_id::text||':fulfillment';
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'fulfillment_cents',v_order.fulfillment_cents,
   'fulfillment_method',v_order.fulfillment_method,'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'gross_sale',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,v_order.fulfillment_cents,null,'fulfillment',null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end if;
 if v_order.discount_cents>0 then
  v_reference:='pos:'||p_transaction_id::text||':discount';
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'discount_cents',v_order.discount_cents,
   'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'discount',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,-v_order.discount_cents,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end if;
 if v_order.tax_cents>0 then
  v_reference:='pos:'||p_transaction_id::text||':tax';
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'tax_cents',v_order.tax_cents,
   'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'sales_tax',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,v_order.tax_cents,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end if;

 for v_line in
  select id,method,operation,captured_amount_minor,currency,provider_operation_reference,provider_payment_reference,updated_at
  from public.mme_pos_tender_attempts where transaction_id=p_transaction_id
   and captured_amount_minor>0 and status in ('captured','partially_refunded','refunded')
  order by id
 loop
  v_reference:='pos:'||p_transaction_id::text||':tender-capture:'||v_line.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'tender_id',v_line.id,
   'method',v_line.method,'operation',v_line.operation,'captured_amount_minor',v_line.captured_amount_minor,
   'currency',v_line.currency,'provider_operation_reference',v_line.provider_operation_reference,
   'provider_payment_reference',v_line.provider_payment_reference)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'payment_capture',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_line.currency,v_line.captured_amount_minor,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end loop;

 for v_refund in
  select id,amount_minor,currency,updated_at from public.mme_pos_refund_requests
  where transaction_id=p_transaction_id and request_type='refund' and status='completed'
  order by updated_at,id
 loop
  v_reference:='pos:'||p_transaction_id::text||':refund:'||v_refund.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'refund_id',v_refund.id,
   'amount_minor',v_refund.amount_minor,'currency',v_refund.currency,'completed_at',v_refund.updated_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'refund',(v_refund.updated_at at time zone p_business_timezone)::date,v_refund.updated_at,p_business_timezone,
   v_refund.currency,-v_refund.amount_minor,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
  v_reference:='pos:'||p_transaction_id::text||':payment-refund:'||v_refund.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'refund_id',v_refund.id,
   'payment_amount_minor',v_refund.amount_minor,'currency',v_refund.currency,'completed_at',v_refund.updated_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'payment_refund',(v_refund.updated_at at time zone p_business_timezone)::date,v_refund.updated_at,p_business_timezone,
   v_refund.currency,-v_refund.amount_minor,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end loop;

 for v_line in
  select order_line_id,total_cost_cents,quantity,product_category,sku_reference,created_at
  from public.mme_pos_inventory_cogs_snapshots where transaction_id=p_transaction_id order by order_line_id
 loop
  v_reference:='pos:'||p_transaction_id::text||':cogs:'||v_line.order_line_id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'order_line_id',v_line.order_line_id,
   'total_cost_cents',v_line.total_cost_cents,'quantity',v_line.quantity,'sku',v_line.sku_reference,
   'category',v_line.product_category,'cost_snapshot_at',v_line.created_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'inventory',v_reference,
   'cost_of_goods_sold',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,-v_line.total_cost_cents,v_line.quantity::bigint*1000,
   left(v_line.product_category,120),left(v_line.sku_reference,160),v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end loop;

 update public.mme_pos_financial_pos_exports set status='exported',lease_token=null,lease_expires_at=null,
  next_attempt_at=now()+interval '15 minutes',last_exported_at=now(),facts_processed=v_fact_count,
  safe_error_code=null,updated_at=now() where id=v_export.id;
 insert into public.mme_pos_financial_pos_export_events(export_id,transaction_id,location_id,actor_person_id,event_type,facts_processed)
 values(v_export.id,p_transaction_id,v_tx.location_id,p_worker_person_id,'exported',v_fact_count);
 return true;
exception when others then
 get stacked diagnostics v_sqlstate=returned_sqlstate;
 v_safe_code:=case when v_sqlstate='55000' then 'CLOSED_PERIOD_OR_STATE_BLOCK'
  when v_sqlstate='42501' then 'WORKER_PERMISSION_DENIED'
  when v_sqlstate in ('23514','22023') then 'SOURCE_VALIDATION_FAILED'
  else 'NATIVE_POS_EXPORT_FAILED' end;
 update public.mme_pos_financial_pos_exports set status='failed',lease_token=null,lease_expires_at=null,
  next_attempt_at=now()+interval '5 minutes',safe_error_code=v_safe_code,updated_at=now()
 where transaction_id=p_transaction_id;
 insert into public.mme_pos_financial_pos_export_events(export_id,transaction_id,location_id,actor_person_id,event_type,safe_error_code)
 select id,p_transaction_id,location_id,p_worker_person_id,'failed',v_safe_code
 from public.mme_pos_financial_pos_exports where transaction_id=p_transaction_id;
 return false;
end;
$$;

revoke all on function public.mme_pos_allocate_receipt_landed_cost(uuid,uuid,uuid,text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.mme_pos_receive_serialized_inventory(text,text,text,uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_assign_serial_unit_to_order_line(uuid,uuid,uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_pos_export_finalized_transaction_financial_facts(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_apply_inventory_sale_and_snapshot_cogs() from public,anon,authenticated;
grant execute on function public.mme_pos_allocate_receipt_landed_cost(uuid,uuid,uuid,text,text,bigint,text) to service_role;
grant execute on function public.mme_pos_receive_serialized_inventory(text,text,text,uuid,uuid,jsonb,text) to service_role;
grant execute on function public.mme_pos_assign_serial_unit_to_order_line(uuid,uuid,uuid,timestamptz) to service_role;
grant execute on function public.mme_pos_export_finalized_transaction_financial_facts(uuid,uuid,uuid,text) to service_role;

commit;
