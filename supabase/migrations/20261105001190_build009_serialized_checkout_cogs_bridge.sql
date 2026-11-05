-- Build 009.39 — Serialized customer checkout and sale-time COGS bridge.
-- Connects the Build 001 serialized checkout/payment lifecycle to Build 009.38
-- cost records. This migration does not expose database writes to browsers.
begin;

alter table public.mme_store_locations
 add column if not exists business_timezone text not null default 'America/New_York';
alter table public.mme_orders add column if not exists paid_at timestamptz;
alter table public.mme_inventory_serial_cost_units
 add column if not exists legacy_serialized_unit_id uuid
 references public.mme_serialized_units(id) on delete restrict;
create unique index if not exists mme_inventory_serial_cost_legacy_unit_unique
 on public.mme_inventory_serial_cost_units(legacy_serialized_unit_id)
 where legacy_serialized_unit_id is not null;

create table public.mme_order_inventory_cogs_snapshots (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 order_line_id uuid not null unique references public.mme_order_lines(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 serial_cost_unit_id uuid not null references public.mme_inventory_serial_cost_units(id) on delete restrict,
 sku_reference text not null,
 product_category text,
 quantity integer not null default 1 check(quantity=1),
 unit_cost_cents bigint not null check(unit_cost_cents>=0),
 total_cost_cents bigint not null check(total_cost_cents>=0),
 cost_method text not null default 'serialized_unit' check(cost_method='serialized_unit'),
 source_cost_reference text not null,
 captured_at timestamptz not null default now(),
 unique(order_id,order_line_id)
);
create index mme_order_inventory_cogs_location_captured_idx
 on public.mme_order_inventory_cogs_snapshots(location_id,captured_at desc);
alter table public.mme_order_inventory_cogs_snapshots enable row level security;
revoke all on public.mme_order_inventory_cogs_snapshots from public,anon,authenticated;
grant all on public.mme_order_inventory_cogs_snapshots to service_role;

-- One receiving operation creates both the checkout identity and the
-- cost-bearing inventory record. Serial number is mandatory in Build 001.
create or replace function public.mme_pos_receive_serialized_inventory_checkout_ready(
 p_receipt_reference text,p_supplier_reference text,p_source_type text,
 p_actor_person_id uuid,p_approved_by_person_id uuid,p_items jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public,extensions
as $$
declare v_receipt_id uuid; v_item record; v_legacy_unit_id uuid; v_cost_unit_id uuid;
 v_serial_digest text; v_imei_digest text;
begin
 if p_items is null or jsonb_typeof(p_items) is distinct from 'array'
  or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>200 then
  raise exception 'Invalid checkout-ready serialized receipt' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,serial_number text,imei text,unit_cost_cents bigint)
  where x.product_id is null or x.location_id is null or nullif(btrim(x.serial_number),'') is null
   or length(x.serial_number)>128 or x.unit_cost_cents is null or x.unit_cost_cents<0
   or (x.imei is not null and length(x.imei)>20)) then
  raise exception 'Each serialized unit requires a valid serial number and nonnegative actual cost' using errcode='22023';
 end if;
 v_receipt_id:=public.mme_pos_receive_serialized_inventory(
  p_receipt_reference,p_supplier_reference,p_source_type,p_actor_person_id,
  p_approved_by_person_id,p_items,p_notes
 );
 for v_item in select * from jsonb_to_recordset(p_items) as x(
  product_id uuid,location_id uuid,serial_number text,imei text,unit_cost_cents bigint
 ) order by product_id,location_id,lower(btrim(serial_number))
 loop
  v_legacy_unit_id:=public.mme_receive_serialized_unit(
   v_item.product_id,v_item.location_id,btrim(v_item.serial_number),
   nullif(btrim(v_item.imei),''),(select condition_grade from public.mme_products where id=v_item.product_id)
  );
  v_serial_digest:=encode(digest(lower(btrim(v_item.serial_number)),'sha256'),'hex');
  v_imei_digest:=case when nullif(regexp_replace(coalesce(v_item.imei,''),'[^0-9]','','g'),'') is null then null
   else encode(digest(regexp_replace(v_item.imei,'[^0-9]','','g'),'sha256'),'hex') end;
  select id into v_cost_unit_id from public.mme_inventory_serial_cost_units
   where receipt_id=v_receipt_id and serial_digest=v_serial_digest
    and imei_digest is not distinct from v_imei_digest for update;
  if not found then raise exception 'Cost-bearing unit could not be matched to serialized catalog unit' using errcode='23514'; end if;
  update public.mme_inventory_serial_cost_units set legacy_serialized_unit_id=v_legacy_unit_id
   where id=v_cost_unit_id and legacy_serialized_unit_id is null;
  if not found then raise exception 'Serialized unit already linked or link conflict detected' using errcode='23505'; end if;
 end loop;
 return v_receipt_id;
end;
$$;

-- Existing Build 001 order creation reserves the serialized identity first.
-- This trigger also reserves the corresponding aggregate balance and cost unit.
create or replace function public.mme_pos_bridge_serialized_order_line_reservation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_unit public.mme_inventory_serial_cost_units%rowtype;
 v_res public.mme_inventory_reservations%rowtype; v_balance public.mme_inventory_balances%rowtype;
begin
 if new.serialized_unit_id is null then return new; end if;
 if new.quantity<>1 then raise exception 'Serialized order lines must have quantity one' using errcode='23514'; end if;
 select * into v_res from public.mme_inventory_reservations
  where order_id=new.order_id and status='active' and expires_at>now() for update;
 if not found then raise exception 'Active serialized order reservation required' using errcode='23514'; end if;
 select * into v_unit from public.mme_inventory_serial_cost_units
  where legacy_serialized_unit_id=new.serialized_unit_id for update;
 if not found or v_unit.status<>'available' or v_unit.product_id<>new.product_id
  or v_unit.location_id<>new.location_id then
  raise exception 'Serialized unit requires matching available cost ledger record' using errcode='23514';
 end if;
 select * into v_balance from public.mme_inventory_balances
  where product_id=new.product_id and location_id=new.location_id for update;
 if not found or v_balance.on_hand_quantity-v_balance.reserved_quantity<1 then
  raise exception 'Serialized unit has no reservable aggregate stock' using errcode='P0001';
 end if;
 update public.mme_inventory_balances set reserved_quantity=reserved_quantity+1,updated_at=now()
  where id=v_balance.id;
 insert into public.mme_inventory_reservation_lines(reservation_id,inventory_balance_id,product_id,location_id,quantity)
 values(v_res.id,v_balance.id,new.product_id,new.location_id,1)
 on conflict(reservation_id,inventory_balance_id) do update
 set quantity=public.mme_inventory_reservation_lines.quantity+1;
 update public.mme_inventory_serial_cost_units set status='reserved',reserved_order_id=new.order_id
  where id=v_unit.id and status='available';
 if not found then raise exception 'Serialized cost unit was concurrently reserved' using errcode='40001'; end if;
 update public.mme_order_lines set inventory_serial_unit_id=v_unit.id where id=new.id;
 insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,order_id,event_data)
 values(v_unit.id,'reserved',coalesce((select customer_identity_id from public.mme_orders where id=new.order_id),v_unit.id),
  new.order_id,jsonb_build_object('legacy_serialized_unit_id',new.serialized_unit_id));
 return new;
end;
$$;
drop trigger if exists mme_pos_bridge_serialized_order_line_reservation on public.mme_order_lines;
create trigger mme_pos_bridge_serialized_order_line_reservation
after insert on public.mme_order_lines for each row
execute function public.mme_pos_bridge_serialized_order_line_reservation();

-- The original Build 001 release RPC changes the legacy reservation status.
-- Mirror that transition into the cost ledger and aggregate stock reservation.
create or replace function public.mme_pos_bridge_serialized_reservation_release()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_unit public.mme_inventory_serial_cost_units%rowtype; v_balance public.mme_inventory_balances%rowtype;
begin
 if old.status<>'active' or new.status not in ('released','expired') then return new; end if;
 select * into v_unit from public.mme_inventory_serial_cost_units
  where legacy_serialized_unit_id=new.unit_id and status='reserved' and reserved_order_id=new.order_id for update;
 if not found then return new; end if;
 select * into v_balance from public.mme_inventory_balances
  where product_id=v_unit.product_id and location_id=v_unit.location_id for update;
 if not found or v_balance.reserved_quantity<1 then
  raise exception 'Serialized reservation balance invariant failed on release' using errcode='23514';
 end if;
 update public.mme_inventory_balances set reserved_quantity=reserved_quantity-1,updated_at=now()
  where id=v_balance.id;
 update public.mme_inventory_reservation_lines set quantity=quantity-1
  where reservation_id=new.reservation_id and inventory_balance_id=v_balance.id and quantity>1;
 delete from public.mme_inventory_reservation_lines
  where reservation_id=new.reservation_id and inventory_balance_id=v_balance.id and quantity=1;
 update public.mme_inventory_serial_cost_units set status='available',reserved_order_id=null where id=v_unit.id;
 insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,order_id,event_data)
 values(v_unit.id,'released',v_unit.id,new.order_id,jsonb_build_object('legacy_reservation_status',new.status));
 return new;
end;
$$;
drop trigger if exists mme_pos_bridge_serialized_reservation_release on public.mme_serialized_unit_reservations;
create trigger mme_pos_bridge_serialized_reservation_release
after update of status on public.mme_serialized_unit_reservations
for each row execute function public.mme_pos_bridge_serialized_reservation_release();

-- The Build 001 verified Stripe payment RPC marks legacy units sold and
-- reservations consumed before changing the order status to paid. This
-- trigger mirrors the cost-ledger and aggregate-stock effects atomically.
create or replace function public.mme_pos_capture_serialized_order_cogs()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_line record; v_unit public.mme_inventory_serial_cost_units%rowtype;
 v_balance public.mme_inventory_balances%rowtype; v_res public.mme_inventory_reservations%rowtype;
begin
 if new.status<>'paid' or old.status='paid' then return new; end if;
 new.paid_at:=coalesce(new.paid_at,now());
 select * into v_res from public.mme_inventory_reservations
  where order_id=new.id and status='consumed' for update;
 if not found then raise exception 'Consumed inventory reservation required for paid order' using errcode='23514'; end if;
 for v_line in
  select l.id,l.product_id,l.location_id,l.quantity,l.sku_snapshot,
   coalesce(p.category_key,'uncategorized') product_category,l.inventory_serial_unit_id,l.serialized_unit_id
  from public.mme_order_lines l join public.mme_products p on p.id=l.product_id
  where l.order_id=new.id and l.serialized_unit_id is not null order by l.id
 loop
  if v_line.quantity<>1 or v_line.inventory_serial_unit_id is null then
   raise exception 'Paid serialized line is missing linked cost unit' using errcode='23514';
  end if;
  select * into v_unit from public.mme_inventory_serial_cost_units
   where id=v_line.inventory_serial_unit_id for update;
  if not found or v_unit.status<>'reserved' or v_unit.reserved_order_id<>new.id
   or v_unit.product_id<>v_line.product_id or v_unit.location_id<>v_line.location_id
   or v_unit.legacy_serialized_unit_id<>v_line.serialized_unit_id then
   raise exception 'Paid order cost unit does not match reservation' using errcode='23514';
  end if;
  select * into v_balance from public.mme_inventory_balances
   where product_id=v_line.product_id and location_id=v_line.location_id for update;
  if not found or v_balance.on_hand_quantity<1 or v_balance.reserved_quantity<1 then
   raise exception 'Paid serialized inventory balance invariant failed' using errcode='23514';
  end if;
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity-1,
   reserved_quantity=reserved_quantity-1,updated_at=now() where id=v_balance.id;
  update public.mme_inventory_reservation_lines set quantity=quantity-1
   where reservation_id=v_res.id and inventory_balance_id=v_balance.id and quantity>1;
  delete from public.mme_inventory_reservation_lines
   where reservation_id=v_res.id and inventory_balance_id=v_balance.id and quantity=1;
  update public.mme_inventory_serial_cost_units set status='sold',reserved_order_id=null,
   sold_order_id=new.id,sold_at=new.paid_at where id=v_unit.id;
  insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,order_id,event_data)
  values(v_unit.id,'sold',coalesce(new.customer_identity_id,v_unit.id),new.id,
   jsonb_build_object('order_line_id',v_line.id,'unit_cost_cents',v_unit.unit_cost_cents));
  insert into public.mme_order_inventory_cogs_snapshots(
   order_id,order_line_id,location_id,product_id,serial_cost_unit_id,sku_reference,
   product_category,quantity,unit_cost_cents,total_cost_cents,source_cost_reference,captured_at
  ) values(new.id,v_line.id,v_line.location_id,v_line.product_id,v_unit.id,
   left(v_line.sku_snapshot,160),left(v_line.product_category,120),1,v_unit.unit_cost_cents,
   v_unit.unit_cost_cents,'serialized-unit:'||v_unit.id::text,new.paid_at);
 end loop;
 return new;
end;
$$;
drop trigger if exists mme_pos_capture_serialized_order_cogs on public.mme_orders;
create trigger mme_pos_capture_serialized_order_cogs
before update of status on public.mme_orders for each row
execute function public.mme_pos_capture_serialized_order_cogs();

create or replace function public.mme_pos_export_serialized_order_cogs(
 p_order_id uuid,p_worker_person_id uuid
) returns integer language plpgsql security definer set search_path=pg_catalog,public,extensions
as $$
declare v_order public.mme_orders%rowtype; v_line record; v_count integer:=0;
 v_timezone text; v_digest text;
begin
 if p_order_id is null or p_worker_person_id is null then
  raise exception 'Order and finance worker are required' using errcode='22023';
 end if;
 select * into v_order from public.mme_orders where id=p_order_id;
 if not found or v_order.status<>'paid' or v_order.paid_at is null then
  raise exception 'Only paid orders with captured COGS can be exported' using errcode='55000';
 end if;
 for v_line in select s.* from public.mme_order_inventory_cogs_snapshots s
  where s.order_id=v_order.id order by s.order_line_id
 loop
  select business_timezone into v_timezone from public.mme_store_locations where id=v_line.location_id;
  if v_timezone is null or not exists(select 1 from pg_timezone_names where name=v_timezone) then
   raise exception 'Store business timezone is missing or invalid' using errcode='23514';
  end if;
  v_digest:=encode(digest(jsonb_build_object('order_id',v_order.id,'line_id',v_line.order_line_id,
   'product_id',v_line.product_id,'quantity',v_line.quantity,'unit_cost_cents',v_line.unit_cost_cents,
   'source_cost_reference',v_line.source_cost_reference,'paid_at',v_order.paid_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(
   v_line.location_id,p_worker_person_id,'inventory',
   'web-order:'||v_order.id::text||':line:'||v_line.order_line_id::text,
   'cost_of_goods_sold',(v_order.paid_at at time zone v_timezone)::date,v_order.paid_at,v_timezone,
   v_order.currency,-v_line.total_cost_cents,1000,left(v_line.product_category,120),
   left(v_line.sku_reference,160),null,null,v_order.id::text,v_digest
  );
  v_count:=v_count+1;
 end loop;
 return v_count;
end;
$$;

revoke all on function public.mme_pos_receive_serialized_inventory_checkout_ready(text,text,text,uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_bridge_serialized_order_line_reservation() from public,anon,authenticated;
revoke all on function public.mme_pos_bridge_serialized_reservation_release() from public,anon,authenticated;
revoke all on function public.mme_pos_capture_serialized_order_cogs() from public,anon,authenticated;
revoke all on function public.mme_pos_export_serialized_order_cogs(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_receive_serialized_inventory_checkout_ready(text,text,text,uuid,uuid,jsonb,text) to service_role;
grant execute on function public.mme_pos_export_serialized_order_cogs(uuid,uuid) to service_role;

comment on table public.mme_order_inventory_cogs_snapshots is
 'Immutable sale-time cost snapshots for serialized web orders; separate from POS transaction COGS because customer orders have no POS transaction id.';
commit;
