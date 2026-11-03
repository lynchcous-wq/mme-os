-- Build 001: landed-cost pool allocation for aggregate inventory receipts.
-- Allocates pallet acquisition, freight, auction and handling costs by line value.
-- Uses the existing receipt RPC so stock, weighted-average cost and movement ledger stay atomic.

create table public.mme_inventory_landed_cost_pools (
 id uuid primary key default gen_random_uuid(),
 pool_reference text not null unique,
 receipt_id uuid not null unique references public.mme_inventory_receipts(id) on delete restrict,
 acquisition_cost_cents bigint not null check(acquisition_cost_cents>=0),
 freight_cost_cents bigint not null default 0 check(freight_cost_cents>=0),
 auction_fee_cents bigint not null default 0 check(auction_fee_cents>=0),
 handling_cost_cents bigint not null default 0 check(handling_cost_cents>=0),
 other_cost_cents bigint not null default 0 check(other_cost_cents>=0),
 landed_cost_total_cents bigint generated always as
  (acquisition_cost_cents+freight_cost_cents+auction_fee_cents+handling_cost_cents+other_cost_cents) stored,
 allocation_method text not null default 'extended_acquisition_value'
  check(allocation_method in ('extended_acquisition_value','equal_per_unit')),
 created_by_identity_id uuid not null,
 approved_by_identity_id uuid,
 created_at timestamptz not null default now()
);

create table public.mme_inventory_landed_cost_allocations (
 id uuid primary key default gen_random_uuid(),
 pool_id uuid not null references public.mme_inventory_landed_cost_pools(id) on delete restrict,
 receipt_id uuid not null references public.mme_inventory_receipts(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 received_quantity integer not null check(received_quantity>0),
 acquisition_line_cost_cents bigint not null check(acquisition_line_cost_cents>=0),
 allocated_additional_cost_cents bigint not null check(allocated_additional_cost_cents>=0),
 landed_line_cost_cents bigint not null check(landed_line_cost_cents>=0),
 landed_unit_cost_cents bigint not null check(landed_unit_cost_cents>=0),
 allocation_remainder_cents bigint not null default 0 check(allocation_remainder_cents>=0),
 created_at timestamptz not null default now(),
 unique(pool_id,product_id,location_id)
);
create index mme_landed_cost_allocations_receipt_idx
 on public.mme_inventory_landed_cost_allocations(receipt_id);
alter table public.mme_inventory_landed_cost_pools enable row level security;
alter table public.mme_inventory_landed_cost_allocations enable row level security;
revoke all on public.mme_inventory_landed_cost_pools,public.mme_inventory_landed_cost_allocations from public,anon,authenticated;
grant all on public.mme_inventory_landed_cost_pools,public.mme_inventory_landed_cost_allocations to service_role;

create or replace function public.mme_receive_inventory_with_landed_cost(
 p_receipt_reference text,p_supplier_reference text,p_source_type text,
 p_acquisition_cost_cents bigint,p_freight_cost_cents bigint,p_auction_fee_cents bigint,
 p_handling_cost_cents bigint,p_other_cost_cents bigint,p_allocation_method text,
 p_actor_identity_id uuid,p_approved_by_identity_id uuid,p_notes text,p_items jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_receipt_id uuid; v_pool_id uuid; v_item record; v_total_base numeric:=0;
 v_total_qty bigint:=0; v_extra bigint:=0; v_allocated bigint:=0;
 v_line_base bigint; v_line_extra bigint; v_line_landed bigint; v_unit_cost bigint;
 v_index integer:=0; v_count integer;
 v_cost_items jsonb:='[]'::jsonb;
begin
 if p_acquisition_cost_cents is null or p_acquisition_cost_cents<0
  or p_freight_cost_cents is null or p_freight_cost_cents<0
  or p_auction_fee_cents is null or p_auction_fee_cents<0
  or p_handling_cost_cents is null or p_handling_cost_cents<0
  or p_other_cost_cents is null or p_other_cost_cents<0
  or p_allocation_method not in ('extended_acquisition_value','equal_per_unit')
  or p_actor_identity_id is null or p_items is null or jsonb_typeof(p_items)<>'array'
  or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>200 then
  raise exception 'Invalid landed-cost receipt' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,acquisition_unit_cost_cents bigint)
  where x.product_id is null or x.location_id is null or x.quantity is null or x.quantity<1 or x.quantity>10000
   or x.acquisition_unit_cost_cents is null or x.acquisition_unit_cost_cents<0)
  or exists(select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,acquisition_unit_cost_cents bigint)
  group by x.product_id,x.location_id having count(*)>1) then
  raise exception 'Invalid or duplicate landed-cost line' using errcode='22023';
 end if;
 select count(*),sum(x.quantity),sum(x.quantity::numeric*x.acquisition_unit_cost_cents)
 into v_count,v_total_qty,v_total_base
 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,acquisition_unit_cost_cents bigint);
 v_extra:=p_freight_cost_cents+p_auction_fee_cents+p_handling_cost_cents+p_other_cost_cents;
 if v_total_base<>p_acquisition_cost_cents then
  raise exception 'Acquisition cost must equal sum of item line acquisition costs' using errcode='22023';
 end if;
 if v_total_base=0 and v_extra>0 then
  raise exception 'Cannot allocate additional costs when acquisition value is zero' using errcode='22023';
 end if;
 for v_item in
  select x.product_id,x.location_id,x.quantity,x.acquisition_unit_cost_cents
  from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,acquisition_unit_cost_cents bigint)
  order by x.product_id,x.location_id
 loop
  v_index:=v_index+1;
  v_line_base:=v_item.quantity::bigint*v_item.acquisition_unit_cost_cents;
  if v_index=v_count then
   v_line_extra:=v_extra-v_allocated;
  elsif p_allocation_method='equal_per_unit' then
   v_line_extra:=floor(v_extra::numeric*v_item.quantity/v_total_qty)::bigint;
  else
   v_line_extra:=floor(v_extra::numeric*v_line_base/v_total_base)::bigint;
  end if;
  v_allocated:=v_allocated+v_line_extra;
  v_line_landed:=v_line_base+v_line_extra;
  v_unit_cost:=floor(v_line_landed::numeric/v_item.quantity)::bigint;
  v_cost_items:=v_cost_items||jsonb_build_array(jsonb_build_object(
   'product_id',v_item.product_id,'location_id',v_item.location_id,'quantity',v_item.quantity,
   'unit_cost_cents',v_unit_cost));
 end loop;
 perform 1 from public.mme_products p
 join jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,acquisition_unit_cost_cents bigint)
  on x.product_id=p.id
 where p.active=true and p.serialized=false
 for update of p;
 if (select count(*) from (select distinct x.product_id,x.location_id from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,acquisition_unit_cost_cents bigint)) q)
  <> v_count then
  raise exception 'Each landed-cost line must identify a unique aggregate product/location' using errcode='22023';
 end if;
 v_receipt_id:=public.mme_receive_inventory(
  p_receipt_reference,p_supplier_reference,p_source_type,
  p_acquisition_cost_cents+v_extra,p_actor_identity_id,p_approved_by_identity_id,p_notes,v_cost_items);
 insert into public.mme_inventory_landed_cost_pools(
  pool_reference,receipt_id,acquisition_cost_cents,freight_cost_cents,auction_fee_cents,
  handling_cost_cents,other_cost_cents,allocation_method,created_by_identity_id,approved_by_identity_id
 ) values (
  p_receipt_reference,v_receipt_id,p_acquisition_cost_cents,p_freight_cost_cents,p_auction_fee_cents,
  p_handling_cost_cents,p_other_cost_cents,p_allocation_method,p_actor_identity_id,p_approved_by_identity_id
 ) returning id into v_pool_id;
 v_index:=0;
 v_allocated:=0;
 for v_item in
  select x.product_id,x.location_id,x.quantity,x.acquisition_unit_cost_cents
  from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,acquisition_unit_cost_cents bigint)
  order by x.product_id,x.location_id
 loop
  v_index:=v_index+1;
  v_line_base:=v_item.quantity::bigint*v_item.acquisition_unit_cost_cents;
  if p_allocation_method='equal_per_unit' then
   v_line_extra:=floor(v_extra::numeric*v_item.quantity/v_total_qty)::bigint;
  else
   v_line_extra:=floor(v_extra::numeric*v_line_base/v_total_base)::bigint;
  end if;
  if v_index=v_count then
   v_line_extra:=v_extra-(select coalesce(sum(a.allocated_additional_cost_cents),0) from public.mme_inventory_landed_cost_allocations a where a.pool_id=v_pool_id);
  end if;
  v_line_landed:=v_line_base+v_line_extra;
  v_unit_cost:=floor(v_line_landed::numeric/v_item.quantity)::bigint;
  insert into public.mme_inventory_landed_cost_allocations(
   pool_id,receipt_id,product_id,location_id,received_quantity,acquisition_line_cost_cents,
   allocated_additional_cost_cents,landed_line_cost_cents,landed_unit_cost_cents,
   allocation_remainder_cents
  ) values(v_pool_id,v_receipt_id,v_item.product_id,v_item.location_id,v_item.quantity,
   v_line_base,v_line_extra,v_line_landed,v_unit_cost,v_line_landed-(v_unit_cost*v_item.quantity));
 end loop;
 return v_receipt_id;
end; $$;

revoke all on function public.mme_receive_inventory_with_landed_cost(text,text,text,bigint,bigint,bigint,bigint,bigint,text,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.mme_receive_inventory_with_landed_cost(text,text,text,bigint,bigint,bigint,bigint,bigint,text,uuid,uuid,text,jsonb) to service_role;

comment on table public.mme_inventory_landed_cost_pools is
 'Receipt-level acquisition, freight, auction, handling and other landed-cost pool.';
comment on table public.mme_inventory_landed_cost_allocations is
 'Per product/location landed-cost allocation with residual cents preserved at pool level.';
