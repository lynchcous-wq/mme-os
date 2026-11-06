-- Build 001: aggregate inventory receiving, adjustments, transfers, and audit ledger.
-- Trusted server only. The server must enforce MME role/CEO approval before invoking
-- privileged adjustment RPCs; service_role is not an end-user authorization model.

alter table public.mme_inventory_balances
  add column average_unit_cost_cents bigint not null default 0
    check (average_unit_cost_cents >= 0);

create table public.mme_inventory_receipts (
  id uuid primary key default gen_random_uuid(),
  receipt_reference text not null unique,
  supplier_reference text,
  source_type text not null check (source_type in ('auction_pallet','supplier','customer_return','other')),
  purchase_total_cents bigint not null check (purchase_total_cents >= 0),
  received_by_identity_id uuid not null,
  approved_by_identity_id uuid,
  received_at timestamptz not null default now(),
  notes text,
  created_at timestamptz not null default now()
);

create table public.mme_inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  movement_type text not null check (movement_type in
    ('receipt','adjustment_increase','adjustment_decrease','transfer_in','transfer_out','damage','repair','quarantine','release_quarantine')),
  quantity_delta integer not null check (quantity_delta <> 0),
  on_hand_before integer not null check (on_hand_before >= 0),
  on_hand_after integer not null check (on_hand_after >= 0),
  reserved_before integer not null check (reserved_before >= 0),
  reserved_after integer not null check (reserved_after >= 0),
  unit_cost_cents bigint not null check (unit_cost_cents >= 0),
  receipt_id uuid references public.mme_inventory_receipts(id) on delete restrict,
  transfer_group_id uuid,
  reason text not null,
  reference_text text,
  actor_identity_id uuid not null,
  approved_by_identity_id uuid,
  created_at timestamptz not null default now(),
  check (reserved_after <= on_hand_after)
);

create index mme_inventory_movements_product_created_idx
  on public.mme_inventory_movements(product_id,created_at desc);
create index mme_inventory_movements_location_created_idx
  on public.mme_inventory_movements(location_id,created_at desc);
create index mme_inventory_movements_receipt_idx
  on public.mme_inventory_movements(receipt_id) where receipt_id is not null;
create index mme_inventory_movements_transfer_idx
  on public.mme_inventory_movements(transfer_group_id) where transfer_group_id is not null;

alter table public.mme_inventory_receipts enable row level security;
alter table public.mme_inventory_movements enable row level security;
revoke all on public.mme_inventory_receipts from anon,authenticated;
revoke all on public.mme_inventory_movements from anon,authenticated;
grant all on public.mme_inventory_receipts to service_role;
grant all on public.mme_inventory_movements to service_role;

create or replace function public.mme_receive_inventory(
  p_receipt_reference text,
  p_supplier_reference text,
  p_source_type text,
  p_purchase_total_cents bigint,
  p_actor_identity_id uuid,
  p_approved_by_identity_id uuid,
  p_notes text,
  p_items jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_receipt_id uuid;
  v_item record;
  v_product record;
  v_balance record;
  v_new_qty integer;
  v_new_cost bigint;
  v_total_units bigint:=0;
begin
  if p_receipt_reference is null or length(btrim(p_receipt_reference))<3 or length(p_receipt_reference)>100
     or p_source_type is null or p_source_type not in ('auction_pallet','supplier','customer_return','other')
     or p_purchase_total_cents is null or p_purchase_total_cents<0
     or p_actor_identity_id is null
     or p_items is null or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>200 then
    raise exception 'Invalid inventory receipt' using errcode='22023';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,unit_cost_cents bigint)
    where x.product_id is null or x.location_id is null or x.quantity is null or x.quantity<1 or x.quantity>10000
       or x.unit_cost_cents is null or x.unit_cost_cents<0
  ) then raise exception 'Invalid receipt line' using errcode='22023'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,unit_cost_cents bigint)
    group by x.product_id,x.location_id having count(*)>1
  ) then raise exception 'Duplicate product/location receipt line' using errcode='22023'; end if;

  insert into public.mme_inventory_receipts(
    receipt_reference,supplier_reference,source_type,purchase_total_cents,
    received_by_identity_id,approved_by_identity_id,notes
  ) values (
    btrim(p_receipt_reference),p_supplier_reference,p_source_type,p_purchase_total_cents,
    p_actor_identity_id,p_approved_by_identity_id,p_notes
  ) returning id into v_receipt_id;

  for v_item in
    select x.product_id,x.location_id,x.quantity,x.unit_cost_cents
    from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,unit_cost_cents bigint)
    order by x.product_id,x.location_id
  loop
    select id,serialized,active into v_product from public.mme_products
     where id=v_item.product_id for update;
    if not found or not v_product.active or v_product.serialized then
      raise exception 'Receipt product unavailable or serialized' using errcode='P0002';
    end if;
    perform 1 from public.mme_store_locations where id=v_item.location_id and active=true;
    if not found then raise exception 'Receipt location unavailable' using errcode='P0002'; end if;

    insert into public.mme_inventory_balances(product_id,location_id,on_hand_quantity,reserved_quantity,average_unit_cost_cents)
    values(v_item.product_id,v_item.location_id,0,0,0)
    on conflict(product_id,location_id) do nothing;

    select id,on_hand_quantity,reserved_quantity,average_unit_cost_cents into v_balance
      from public.mme_inventory_balances
     where product_id=v_item.product_id and location_id=v_item.location_id for update;

    v_new_qty:=v_balance.on_hand_quantity+v_item.quantity;
    if v_new_qty>2147483647 then raise exception 'Inventory quantity overflow' using errcode='22003'; end if;
    if v_balance.on_hand_quantity=0 then
      v_new_cost:=v_item.unit_cost_cents;
    else
      v_new_cost:=((v_balance.on_hand_quantity::numeric*v_balance.average_unit_cost_cents
                    +v_item.quantity::numeric*v_item.unit_cost_cents)/v_new_qty)::bigint;
    end if;

    update public.mme_inventory_balances
       set on_hand_quantity=v_new_qty,average_unit_cost_cents=v_new_cost,updated_at=now()
     where id=v_balance.id;

    insert into public.mme_inventory_movements(
      product_id,location_id,movement_type,quantity_delta,on_hand_before,on_hand_after,
      reserved_before,reserved_after,unit_cost_cents,receipt_id,reason,reference_text,
      actor_identity_id,approved_by_identity_id
    ) values (
      v_item.product_id,v_item.location_id,'receipt',v_item.quantity,
      v_balance.on_hand_quantity,v_new_qty,v_balance.reserved_quantity,v_balance.reserved_quantity,
      v_item.unit_cost_cents,v_receipt_id,'Inventory received',btrim(p_receipt_reference),
      p_actor_identity_id,p_approved_by_identity_id
    );
    v_total_units:=v_total_units+v_item.quantity;
  end loop;
  return v_receipt_id;
end; $$;

create or replace function public.mme_adjust_inventory(
  p_product_id uuid,p_location_id uuid,p_quantity_delta integer,
  p_reason text,p_reference_text text,p_actor_identity_id uuid,
  p_approved_by_identity_id uuid,p_unit_cost_cents bigint default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_product record; v_balance record; v_after integer; v_movement_id uuid;
begin
  if p_product_id is null or p_location_id is null or p_quantity_delta is null or p_quantity_delta=0
     or p_reason is null or length(btrim(p_reason))<5 or length(p_reason)>500
     or p_actor_identity_id is null or p_unit_cost_cents is not null and p_unit_cost_cents<0 then
    raise exception 'Invalid inventory adjustment' using errcode='22023';
  end if;
  select id,serialized,active into v_product from public.mme_products where id=p_product_id for update;
  if not found or not v_product.active or v_product.serialized then
    raise exception 'Adjustment product unavailable or serialized' using errcode='P0002';
  end if;
  if not exists(select 1 from public.mme_store_locations where id=p_location_id and active=true) then
    raise exception 'Adjustment location unavailable' using errcode='P0002';
  end if;
  insert into public.mme_inventory_balances(product_id,location_id)
  values(p_product_id,p_location_id)
  on conflict(product_id,location_id) do nothing;
  select id,on_hand_quantity,reserved_quantity,average_unit_cost_cents into v_balance
   from public.mme_inventory_balances where product_id=p_product_id and location_id=p_location_id for update;
  v_after:=v_balance.on_hand_quantity+p_quantity_delta;
  if v_after< v_balance.reserved_quantity then
    raise exception 'Adjustment cannot reduce stock below reserved quantity' using errcode='23514';
  end if;
  if v_after<0 then raise exception 'Adjustment would create negative inventory' using errcode='23514'; end if;
  update public.mme_inventory_balances set on_hand_quantity=v_after,
    average_unit_cost_cents=coalesce(p_unit_cost_cents,average_unit_cost_cents),updated_at=now()
   where id=v_balance.id;
  insert into public.mme_inventory_movements(
    product_id,location_id,movement_type,quantity_delta,on_hand_before,on_hand_after,
    reserved_before,reserved_after,unit_cost_cents,reason,reference_text,actor_identity_id,approved_by_identity_id
  ) values (
    p_product_id,p_location_id,
    case when p_quantity_delta>0 then 'adjustment_increase' else 'adjustment_decrease' end,
    p_quantity_delta,v_balance.on_hand_quantity,v_after,v_balance.reserved_quantity,v_balance.reserved_quantity,
    coalesce(p_unit_cost_cents,v_balance.average_unit_cost_cents),btrim(p_reason),p_reference_text,
    p_actor_identity_id,p_approved_by_identity_id
  ) returning id into v_movement_id;
  return v_movement_id;
end; $$;

create or replace function public.mme_transfer_inventory(
  p_product_id uuid,p_from_location_id uuid,p_to_location_id uuid,
  p_quantity integer,p_reason text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_product record; v_from record; v_to record; v_group uuid;
begin
  if p_product_id is null or p_from_location_id is null or p_to_location_id is null
     or p_from_location_id=p_to_location_id or p_quantity is null or p_quantity<1
     or p_reason is null or length(btrim(p_reason))<5 or p_actor_identity_id is null then
    raise exception 'Invalid inventory transfer' using errcode='22023';
  end if;
  select id,serialized,active into v_product from public.mme_products where id=p_product_id for update;
  if not found or not v_product.active or v_product.serialized then
    raise exception 'Transfer product unavailable or serialized' using errcode='P0002';
  end if;
  if not exists(select 1 from public.mme_store_locations where id=p_from_location_id and active=true)
     or not exists(select 1 from public.mme_store_locations where id=p_to_location_id and active=true) then
    raise exception 'Transfer location unavailable' using errcode='P0002';
  end if;
  insert into public.mme_inventory_balances(product_id,location_id)
    values(p_product_id,p_from_location_id),(p_product_id,p_to_location_id)
    on conflict(product_id,location_id) do nothing;
  -- Lock both balance rows in deterministic location order to reduce
  -- deadlock risk when opposite-direction transfers run concurrently.
  perform 1 from public.mme_inventory_balances
   where product_id=p_product_id and location_id in (p_from_location_id,p_to_location_id)
   order by location_id for update;
  select id,on_hand_quantity,reserved_quantity,average_unit_cost_cents into v_from
    from public.mme_inventory_balances where product_id=p_product_id and location_id=p_from_location_id;
  select id,on_hand_quantity,reserved_quantity,average_unit_cost_cents into v_to
    from public.mme_inventory_balances where product_id=p_product_id and location_id=p_to_location_id;
  if v_from.on_hand_quantity-v_from.reserved_quantity<p_quantity then
    raise exception 'Insufficient unreserved stock to transfer' using errcode='P0001';
  end if;
  if v_to.on_hand_quantity::bigint+p_quantity>2147483647 then raise exception 'Destination quantity overflow' using errcode='22003'; end if;
  v_group:=gen_random_uuid();
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity-p_quantity,updated_at=now() where id=v_from.id;
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity+p_quantity,updated_at=now() where id=v_to.id;
  insert into public.mme_inventory_movements(
    product_id,location_id,movement_type,quantity_delta,on_hand_before,on_hand_after,
    reserved_before,reserved_after,unit_cost_cents,transfer_group_id,reason,actor_identity_id,approved_by_identity_id
  ) values
  (p_product_id,p_from_location_id,'transfer_out',-p_quantity,v_from.on_hand_quantity,v_from.on_hand_quantity-p_quantity,
   v_from.reserved_quantity,v_from.reserved_quantity,v_from.average_unit_cost_cents,v_group,btrim(p_reason),p_actor_identity_id,p_approved_by_identity_id),
  (p_product_id,p_to_location_id,'transfer_in',p_quantity,v_to.on_hand_quantity,v_to.on_hand_quantity+p_quantity,
   v_to.reserved_quantity,v_to.reserved_quantity,v_from.average_unit_cost_cents,v_group,btrim(p_reason),p_actor_identity_id,p_approved_by_identity_id);
  return v_group;
end; $$;

revoke all on function public.mme_receive_inventory(text,text,text,bigint,uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_adjust_inventory(uuid,uuid,integer,text,text,uuid,uuid,bigint) from public,anon,authenticated;
revoke all on function public.mme_transfer_inventory(uuid,uuid,uuid,integer,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_receive_inventory(text,text,text,bigint,uuid,uuid,text,jsonb) to service_role;
grant execute on function public.mme_adjust_inventory(uuid,uuid,integer,text,text,uuid,uuid,bigint) to service_role;
grant execute on function public.mme_transfer_inventory(uuid,uuid,uuid,integer,text,uuid,uuid) to service_role;
