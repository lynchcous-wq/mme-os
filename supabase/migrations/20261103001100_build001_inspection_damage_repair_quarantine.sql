-- Build 001: inspection, damage, repair, quarantine, and return-to-stock controls.
-- Aggregate held quantities are removed from sellable on-hand until disposition.
-- Serialized units retain their individual unit identity and state history.

create table public.mme_inventory_inspections (
  id uuid primary key default gen_random_uuid(),
  inspection_reference text not null unique,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  aggregate_quantity integer not null default 0 check (aggregate_quantity >= 0),
  serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
  order_id uuid references public.mme_orders(id) on delete restrict,
  inspection_type text not null check (inspection_type in
    ('customer_return','receiving_damage','warehouse_damage','repair_intake','quality_check','warranty_return')),
  condition_before text,
  condition_after text check (condition_after is null or condition_after in ('new','open_box','refurbished','used','damaged','unusable')),
  disposition text not null default 'pending'
    check (disposition in ('pending','return_to_stock','repair','quarantine','write_off','return_to_supplier')),
  reason text not null check (length(btrim(reason))>=5),
  findings jsonb not null default '{}'::jsonb check (jsonb_typeof(findings)='object'),
  photo_evidence jsonb not null default '[]'::jsonb check (jsonb_typeof(photo_evidence)='array'),
  inspected_by_identity_id uuid not null,
  approved_by_identity_id uuid,
  resolved_by_identity_id uuid,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (serialized_unit_id is not null and aggregate_quantity=0)
    or (serialized_unit_id is null and aggregate_quantity>0)
  ),
  check (
    (disposition='pending' and resolved_at is null)
    or (disposition<>'pending' and resolved_at is not null and resolved_by_identity_id is not null)
  )
);

create table public.mme_inventory_holds (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null unique references public.mme_inventory_inspections(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  quantity integer not null check (quantity>0),
  hold_type text not null check (hold_type in ('repair','quarantine','damage')),
  hold_status text not null default 'active' check (hold_status in ('active','released','written_off','returned_to_supplier')),
  unit_cost_cents bigint not null check (unit_cost_cents>=0),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index mme_inventory_inspections_product_created_idx
  on public.mme_inventory_inspections(product_id,created_at desc);
create index mme_inventory_inspections_disposition_idx
  on public.mme_inventory_inspections(disposition,created_at);
create index mme_inventory_holds_status_idx
  on public.mme_inventory_holds(hold_status,created_at);

alter table public.mme_inventory_inspections enable row level security;
alter table public.mme_inventory_holds enable row level security;
revoke all on public.mme_inventory_inspections from anon,authenticated;
revoke all on public.mme_inventory_holds from anon,authenticated;
grant all on public.mme_inventory_inspections to service_role;
grant all on public.mme_inventory_holds to service_role;

create or replace function public.mme_inspect_aggregate_inventory(
  p_reference text,p_product_id uuid,p_location_id uuid,p_quantity integer,
  p_inspection_type text,p_disposition text,p_reason text,p_findings jsonb,
  p_photo_evidence jsonb,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_product record; v_balance record; v_inspection_id uuid; v_hold_type text;
begin
  if p_reference is null or length(btrim(p_reference))<3 or length(p_reference)>100
     or p_product_id is null or p_location_id is null or p_quantity is null or p_quantity<1
     or p_inspection_type is null or p_inspection_type not in ('customer_return','receiving_damage','warehouse_damage','repair_intake','quality_check','warranty_return')
     or p_disposition is null or p_disposition not in ('repair','quarantine','write_off','return_to_supplier')
     or p_reason is null or length(btrim(p_reason))<5
     or p_findings is null or jsonb_typeof(p_findings)<>'object'
     or p_photo_evidence is null or jsonb_typeof(p_photo_evidence)<>'array'
     or jsonb_array_length(p_photo_evidence)>20 or p_actor_identity_id is null then
    raise exception 'Invalid aggregate inspection request' using errcode='22023';
  end if;
  select id,serialized,active into v_product from public.mme_products where id=p_product_id for update;
  if not found or not v_product.active or v_product.serialized then
    raise exception 'Aggregate product unavailable' using errcode='P0002';
  end if;
  select id,on_hand_quantity,reserved_quantity,average_unit_cost_cents into v_balance
    from public.mme_inventory_balances where product_id=p_product_id and location_id=p_location_id for update;
  if not found or v_balance.on_hand_quantity-v_balance.reserved_quantity<p_quantity then
    raise exception 'Insufficient unreserved stock for inspection hold' using errcode='P0001';
  end if;
  v_hold_type:=case when p_disposition='repair' then 'repair' when p_disposition='quarantine' then 'quarantine' else 'damage' end;
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity-p_quantity,updated_at=now()
    where id=v_balance.id;
  insert into public.mme_inventory_inspections(
    inspection_reference,product_id,location_id,aggregate_quantity,inspection_type,
    condition_before,disposition,reason,findings,photo_evidence,inspected_by_identity_id,approved_by_identity_id
  ) values (
    btrim(p_reference),p_product_id,p_location_id,p_quantity,p_inspection_type,
    (select condition_grade from public.mme_products where id=p_product_id),
    'pending',btrim(p_reason),p_findings,p_photo_evidence,p_actor_identity_id,p_approved_by_identity_id
  ) returning id into v_inspection_id;
  insert into public.mme_inventory_holds(
    inspection_id,product_id,location_id,quantity,hold_type,unit_cost_cents
  ) values(v_inspection_id,p_product_id,p_location_id,p_quantity,v_hold_type,v_balance.average_unit_cost_cents);
  insert into public.mme_inventory_movements(
    product_id,location_id,movement_type,quantity_delta,on_hand_before,on_hand_after,
    reserved_before,reserved_after,unit_cost_cents,reason,reference_text,actor_identity_id,approved_by_identity_id
  ) values(
    p_product_id,p_location_id,
    case when p_disposition='repair' then 'repair' when p_disposition='quarantine' then 'quarantine' else 'damage' end,
    -p_quantity,v_balance.on_hand_quantity,v_balance.on_hand_quantity-p_quantity,
    v_balance.reserved_quantity,v_balance.reserved_quantity,v_balance.average_unit_cost_cents,
    btrim(p_reason),btrim(p_reference),p_actor_identity_id,p_approved_by_identity_id
  );
  return v_inspection_id;
end; $$;

create or replace function public.mme_resolve_aggregate_inspection(
  p_inspection_id uuid,p_resolution text,p_condition_after text,
  p_reason text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_i record; v_h record; v_balance record;
begin
  if p_inspection_id is null or p_resolution not in ('return_to_stock','write_off','return_to_supplier')
     or p_reason is null or length(btrim(p_reason))<5 or p_actor_identity_id is null
     or p_condition_after is not null and p_condition_after not in ('new','open_box','refurbished','used','damaged','unusable') then
    raise exception 'Invalid inspection resolution' using errcode='22023';
  end if;
  select * into v_i from public.mme_inventory_inspections where id=p_inspection_id for update;
  if not found or v_i.disposition<>'pending' or v_i.serialized_unit_id is not null then return false; end if;
  select * into v_h from public.mme_inventory_holds where inspection_id=p_inspection_id for update;
  if not found or v_h.hold_status<>'active' then return false; end if;

  if p_resolution='return_to_stock' then
    insert into public.mme_inventory_balances(product_id,location_id,on_hand_quantity,reserved_quantity,average_unit_cost_cents)
    values(v_h.product_id,v_h.location_id,v_h.quantity,0,v_h.unit_cost_cents)
    on conflict(product_id,location_id) do update
      set on_hand_quantity=public.mme_inventory_balances.on_hand_quantity+excluded.on_hand_quantity,updated_at=now();
    update public.mme_inventory_holds set hold_status='released',resolved_at=now() where id=v_h.id;
    insert into public.mme_inventory_movements(
      product_id,location_id,movement_type,quantity_delta,on_hand_before,on_hand_after,
      reserved_before,reserved_after,unit_cost_cents,reason,reference_text,actor_identity_id,approved_by_identity_id
    ) select v_h.product_id,v_h.location_id,'release_quarantine',v_h.quantity,
      b.on_hand_quantity-v_h.quantity,b.on_hand_quantity,b.reserved_quantity,b.reserved_quantity,
      v_h.unit_cost_cents,btrim(p_reason),v_i.inspection_reference,p_actor_identity_id,p_approved_by_identity_id
      from public.mme_inventory_balances b where b.product_id=v_h.product_id and b.location_id=v_h.location_id;
  elsif p_resolution='write_off' then
    update public.mme_inventory_holds set hold_status='written_off',resolved_at=now() where id=v_h.id;
  else
    update public.mme_inventory_holds set hold_status='returned_to_supplier',resolved_at=now() where id=v_h.id;
  end if;
  update public.mme_inventory_inspections set disposition=p_resolution,condition_after=p_condition_after,
    reason=reason||' | Resolution: '||btrim(p_reason),resolved_by_identity_id=p_actor_identity_id,
    approved_by_identity_id=coalesce(p_approved_by_identity_id,approved_by_identity_id),
    resolved_at=now(),updated_at=now() where id=p_inspection_id;
  return true;
end; $$;

create or replace function public.mme_inspect_serialized_unit(
  p_reference text,p_unit_id uuid,p_inspection_type text,p_disposition text,
  p_reason text,p_findings jsonb,p_photo_evidence jsonb,p_actor_identity_id uuid,
  p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_unit record; v_inspection_id uuid;
begin
  if p_reference is null or length(btrim(p_reference))<3 or p_unit_id is null
     or p_inspection_type not in ('customer_return','receiving_damage','warehouse_damage','repair_intake','quality_check','warranty_return')
     or p_disposition not in ('repair','quarantine','write_off','return_to_supplier')
     or p_reason is null or length(btrim(p_reason))<5
     or p_findings is null or jsonb_typeof(p_findings)<>'object'
     or p_photo_evidence is null or jsonb_typeof(p_photo_evidence)<>'array'
     or jsonb_array_length(p_photo_evidence)>20 or p_actor_identity_id is null then
    raise exception 'Invalid serialized inspection request' using errcode='22023';
  end if;
  select * into v_unit from public.mme_serialized_units where id=p_unit_id for update;
  if not found or v_unit.unit_status not in ('in_stock','sold') then
    raise exception 'Serialized unit cannot enter inspection from current state' using errcode='P0001';
  end if;
  insert into public.mme_inventory_inspections(
    inspection_reference,product_id,location_id,serialized_unit_id,inspection_type,
    condition_before,disposition,reason,findings,photo_evidence,inspected_by_identity_id,approved_by_identity_id
  ) values(
    btrim(p_reference),v_unit.product_id,v_unit.location_id,p_unit_id,p_inspection_type,
    v_unit.condition_grade,'pending',btrim(p_reason),p_findings,p_photo_evidence,p_actor_identity_id,p_approved_by_identity_id
  ) returning id into v_inspection_id;
  update public.mme_serialized_units set unit_status=
    case when p_disposition='repair' then 'repair' else 'quarantine' end,updated_at=now()
   where id=p_unit_id;
  return v_inspection_id;
end; $$;

create or replace function public.mme_resolve_serialized_inspection(
  p_inspection_id uuid,p_resolution text,p_condition_after text,
  p_reason text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_i record; v_unit record;
begin
  if p_inspection_id is null or p_resolution not in ('return_to_stock','write_off','return_to_supplier')
     or p_reason is null or length(btrim(p_reason))<5 or p_actor_identity_id is null
     or p_condition_after is not null and p_condition_after not in ('new','open_box','refurbished','used','damaged','unusable') then
    raise exception 'Invalid serialized inspection resolution' using errcode='22023';
  end if;
  select * into v_i from public.mme_inventory_inspections where id=p_inspection_id for update;
  if not found or v_i.disposition<>'pending' or v_i.serialized_unit_id is null then return false; end if;
  select * into v_unit from public.mme_serialized_units where id=v_i.serialized_unit_id for update;
  if not found or v_unit.unit_status not in ('repair','quarantine') then return false; end if;

  if p_resolution='return_to_stock' then
    if p_condition_after not in ('new','open_box','refurbished','used') then
      raise exception 'Return-to-stock requires a saleable condition grade' using errcode='22023';
    end if;
    update public.mme_serialized_units set unit_status='in_stock',condition_grade=p_condition_after,
      sold_at=null,updated_at=now() where id=v_unit.id;
  else
    update public.mme_serialized_units set unit_status='quarantine',updated_at=now() where id=v_unit.id;
  end if;
  update public.mme_inventory_inspections set disposition=p_resolution,condition_after=p_condition_after,
    reason=reason||' | Resolution: '||btrim(p_reason),resolved_by_identity_id=p_actor_identity_id,
    approved_by_identity_id=coalesce(p_approved_by_identity_id,approved_by_identity_id),
    resolved_at=now(),updated_at=now() where id=p_inspection_id;
  return true;
end; $$;

revoke all on function public.mme_inspect_aggregate_inventory(text,uuid,uuid,integer,text,text,text,jsonb,jsonb,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_resolve_aggregate_inspection(uuid,text,text,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inspect_serialized_unit(text,uuid,text,text,text,jsonb,jsonb,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_inspect_aggregate_inventory(text,uuid,uuid,integer,text,text,text,jsonb,jsonb,uuid,uuid) to service_role;
grant execute on function public.mme_resolve_aggregate_inspection(uuid,text,text,text,uuid,uuid) to service_role;
grant execute on function public.mme_inspect_serialized_unit(text,uuid,text,text,text,jsonb,jsonb,uuid,uuid) to service_role;
grant execute on function public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid) to service_role;

comment on table public.mme_inventory_inspections is
  'Inspection findings, photo evidence references, condition changes, approvals and disposition history.';
comment on table public.mme_inventory_holds is
  'Aggregate units removed from sellable on-hand stock while under repair, quarantine or damage disposition.';
