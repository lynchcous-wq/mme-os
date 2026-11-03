-- Build 001: idempotent receiving adapter for approved auction lots.
-- All stock, serial, cost and audit writes occur in one database transaction.
-- External CEO/role authorization and source-document scanning remain trusted-server duties.

create table public.mme_auction_import_serials (
 id uuid primary key default gen_random_uuid(),
 batch_line_id uuid not null references public.mme_auction_import_lines(id) on delete restrict,
 serial_number text not null unique check(serial_number=btrim(serial_number) and length(serial_number) between 1 and 128),
 imei text unique check(imei is null or (imei=btrim(imei) and length(imei) between 8 and 20)),
 created_at timestamptz not null default now()
);
create index mme_auction_import_serials_line_idx on public.mme_auction_import_serials(batch_line_id);
alter table public.mme_auction_import_serials enable row level security;
revoke all on public.mme_auction_import_serials from public,anon,authenticated;
grant all on public.mme_auction_import_serials to service_role;

create table public.mme_auction_import_line_costs (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_auction_import_batches(id) on delete restrict,
 batch_line_id uuid not null unique references public.mme_auction_import_lines(id) on delete restrict,
 receipt_id uuid not null references public.mme_inventory_receipts(id) on delete restrict,
 acquisition_line_cost_cents bigint not null check(acquisition_line_cost_cents>=0),
 allocated_additional_cost_cents bigint not null check(allocated_additional_cost_cents>=0),
 landed_line_cost_cents bigint not null check(landed_line_cost_cents>=0),
 quantity integer not null check(quantity>0),
 unit_cost_floor_cents bigint not null check(unit_cost_floor_cents>=0),
 line_remainder_cents bigint not null check(line_remainder_cents>=0),
 created_at timestamptz not null default now()
);
create index mme_auction_import_line_costs_batch_idx on public.mme_auction_import_line_costs(batch_id);
alter table public.mme_auction_import_line_costs enable row level security;
revoke all on public.mme_auction_import_line_costs from public,anon,authenticated;
grant all on public.mme_auction_import_line_costs to service_role;

create or replace function public.mme_set_auction_import_serials(
 p_line_id uuid,p_actor_identity_id uuid,p_serials jsonb
) returns integer language plpgsql security definer set search_path=''
as $$
declare v_batch_id uuid; v_qty integer; v_type text; v_status text; v_count integer;
begin
 if p_line_id is null or p_actor_identity_id is null or p_serials is null
  or jsonb_typeof(p_serials)<>'array' or jsonb_array_length(p_serials)>10000 then
  raise exception 'Invalid serialized identifier list' using errcode='22023';
 end if;
 select l.batch_id,l.source_quantity,l.inventory_type,b.status
 into v_batch_id,v_qty,v_type,v_status
 from public.mme_auction_import_lines l join public.mme_auction_import_batches b on b.id=l.batch_id
 where l.id=p_line_id for update of l,b;
 if not found or v_status not in ('staged','needs_review') or v_type<>'serialized' then
  raise exception 'Serialized import line is not editable' using errcode='23514';
 end if;
 if jsonb_array_length(p_serials)<>v_qty then
  raise exception 'One serial number is required for every serialized unit' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_to_recordset(p_serials) x(serial_number text,imei text)
  where x.serial_number is null or x.serial_number<>btrim(x.serial_number)
   or length(x.serial_number) not between 1 and 128
   or x.imei is not null and (x.imei<>btrim(x.imei) or length(x.imei) not between 8 and 20))
  or exists(select 1 from jsonb_to_recordset(p_serials) x(serial_number text,imei text)
   group by x.serial_number having count(*)>1)
  or exists(select 1 from jsonb_to_recordset(p_serials) x(serial_number text,imei text)
   where x.imei is not null group by x.imei having count(*)>1) then
  raise exception 'Invalid or duplicate serial/IMEI in import line' using errcode='22023';
 end if;
 delete from public.mme_auction_import_serials where batch_line_id=p_line_id;
 insert into public.mme_auction_import_serials(batch_line_id,serial_number,imei)
 select p_line_id,x.serial_number,x.imei
 from jsonb_to_recordset(p_serials) x(serial_number text,imei text);
 insert into public.mme_auction_import_events(batch_id,line_id,event_type,event_data,actor_identity_id)
 values(v_batch_id,p_line_id,'line_reviewed',jsonb_build_object('serialized_identifier_count',v_qty),p_actor_identity_id);
 return v_qty;
end; $$;

create or replace function public.mme_receive_approved_auction_batch(
 p_batch_id uuid,p_actor_identity_id uuid,p_approved_by_identity_id uuid,p_receipt_reference text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_batch public.mme_auction_import_batches%rowtype;
 v_receipt_id uuid; v_line record; v_serial record; v_unit_id uuid;
 v_total_base numeric; v_total_qty bigint; v_extra bigint; v_allocated bigint:=0;
 v_line_extra bigint; v_line_landed bigint; v_unit_cost bigint; v_remainder bigint;
 v_idx integer:=0; v_count integer; v_aggregate_items jsonb:='[]'::jsonb;
 v_unit_ids uuid[]; v_serial_count integer;
begin
 if p_batch_id is null or p_actor_identity_id is null or p_approved_by_identity_id is null
  or p_receipt_reference is null or length(btrim(p_receipt_reference)) not between 3 and 100 then
  raise exception 'Invalid auction receiving request' using errcode='22023';
 end if;
 select * into v_batch from public.mme_auction_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Auction batch not found' using errcode='P0002'; end if;
 if v_batch.status='received' then return v_batch.received_receipt_id; end if;
 if v_batch.status<>'approved' then raise exception 'Only approved auction batches can be received' using errcode='23514'; end if;
 if exists(select 1 from public.mme_auction_import_lines where batch_id=p_batch_id
  and (review_status<>'approved' or product_id is null or location_id is null)) then
  raise exception 'Every auction line must be approved and matched before receiving' using errcode='23514';
 end if;
 if exists(select 1 from public.mme_auction_import_lines l join public.mme_products p on p.id=l.product_id
  where l.batch_id=p_batch_id and ((l.inventory_type='aggregate' and p.serialized)
   or (l.inventory_type='serialized' and not p.serialized))) then
  raise exception 'Import inventory type does not match catalog product type' using errcode='23514';
 end if;
 if exists(select 1 from public.mme_auction_import_lines l where l.batch_id=p_batch_id
  and l.inventory_type='serialized' and
  (select count(*) from public.mme_auction_import_serials s where s.batch_line_id=l.id)<>l.source_quantity) then
  raise exception 'Serialized lines require one unique serial/IMEI record per unit' using errcode='23514';
 end if;
 select count(*),coalesce(sum(acquisition_line_cost_cents::numeric),0),coalesce(sum(source_quantity::bigint),0)
 into v_count,v_total_base,v_total_qty
 from public.mme_auction_import_lines where batch_id=p_batch_id;
 if v_count=0 or v_total_base<>v_batch.acquisition_cost_cents then
  raise exception 'Auction acquisition amount does not reconcile' using errcode='23514';
 end if;
 v_extra:=v_batch.freight_cost_cents+v_batch.auction_fee_cents+v_batch.handling_cost_cents+v_batch.other_cost_cents;
 if v_total_base=0 and v_extra>0 then raise exception 'Cannot allocate additional costs over zero acquisition value' using errcode='22023'; end if;

 -- Determine each line's landed cost. Last line receives the cent remainder.
 for v_line in select * from public.mme_auction_import_lines where batch_id=p_batch_id order by source_row_number loop
  v_idx:=v_idx+1;
  if v_idx=v_count then
   v_line_extra:=v_extra-v_allocated;
  elsif v_batch.allocation_method='equal_per_unit' then
   v_line_extra:=floor(v_extra::numeric*v_line.source_quantity/v_total_qty)::bigint;
  else
   v_line_extra:=floor(v_extra::numeric*v_line.acquisition_line_cost_cents/v_total_base)::bigint;
  end if;
  v_allocated:=v_allocated+v_line_extra;
  v_line_landed:=v_line.acquisition_line_cost_cents+v_line_extra;
  v_unit_cost:=floor(v_line_landed::numeric/v_line.source_quantity)::bigint;
  v_remainder:=v_line_landed-(v_unit_cost*v_line.source_quantity);
  if v_line.inventory_type='aggregate' then
   v_aggregate_items:=v_aggregate_items||jsonb_build_array(jsonb_build_object(
    'product_id',v_line.product_id,'location_id',v_line.location_id,'quantity',v_line.source_quantity,
    'unit_cost_cents',v_unit_cost));
  end if;
 end loop;

 -- One receipt header covers the whole lot. Aggregate stock movements are written by the existing receipt RPC.
 if jsonb_array_length(v_aggregate_items)>0 then
  v_receipt_id:=public.mme_receive_inventory(
   p_receipt_reference,v_batch.auction_lot_reference,'auction_pallet',
   v_batch.acquisition_cost_cents+v_extra,p_actor_identity_id,p_approved_by_identity_id,
   'Auction batch '||v_batch.batch_reference,v_aggregate_items);
 else
  insert into public.mme_inventory_receipts(receipt_reference,supplier_reference,source_type,purchase_total_cents,
   received_by_identity_id,approved_by_identity_id,notes)
  values(btrim(p_receipt_reference),v_batch.auction_lot_reference,'auction_pallet',
   v_batch.acquisition_cost_cents+v_extra,p_actor_identity_id,p_approved_by_identity_id,
   'Serialized-only auction batch '||v_batch.batch_reference)
  returning id into v_receipt_id;
 end if;

 insert into public.mme_inventory_landed_cost_pools(
  pool_reference,receipt_id,acquisition_cost_cents,freight_cost_cents,auction_fee_cents,
  handling_cost_cents,other_cost_cents,allocation_method,created_by_identity_id,approved_by_identity_id
 ) values(v_batch.batch_reference,v_receipt_id,v_batch.acquisition_cost_cents,v_batch.freight_cost_cents,
  v_batch.auction_fee_cents,v_batch.handling_cost_cents,v_batch.other_cost_cents,
  v_batch.allocation_method,p_actor_identity_id,p_approved_by_identity_id);

 v_idx:=0; v_allocated:=0;
 for v_line in select * from public.mme_auction_import_lines where batch_id=p_batch_id order by source_row_number loop
  v_idx:=v_idx+1;
  if v_idx=v_count then v_line_extra:=v_extra-v_allocated;
  elsif v_batch.allocation_method='equal_per_unit' then
   v_line_extra:=floor(v_extra::numeric*v_line.source_quantity/v_total_qty)::bigint;
  else
   v_line_extra:=floor(v_extra::numeric*v_line.acquisition_line_cost_cents/v_total_base)::bigint;
  end if;
  v_allocated:=v_allocated+v_line_extra;
  v_line_landed:=v_line.acquisition_line_cost_cents+v_line_extra;
  v_unit_cost:=floor(v_line_landed::numeric/v_line.source_quantity)::bigint;
  v_remainder:=v_line_landed-(v_unit_cost*v_line.source_quantity);

  insert into public.mme_auction_import_line_costs(batch_id,batch_line_id,receipt_id,
   acquisition_line_cost_cents,allocated_additional_cost_cents,landed_line_cost_cents,
   quantity,unit_cost_floor_cents,line_remainder_cents)
  values(p_batch_id,v_line.id,v_receipt_id,v_line.acquisition_line_cost_cents,v_line_extra,
   v_line_landed,v_line.source_quantity,v_unit_cost,v_remainder);

  if v_line.inventory_type='aggregate' then
   insert into public.mme_inventory_landed_cost_allocations(
    pool_id,receipt_id,product_id,location_id,received_quantity,acquisition_line_cost_cents,
    allocated_additional_cost_cents,landed_line_cost_cents,landed_unit_cost_cents,allocation_remainder_cents
   ) select p.id,v_receipt_id,v_line.product_id,v_line.location_id,v_line.source_quantity,
    v_line.acquisition_line_cost_cents,v_line_extra,v_line_landed,v_unit_cost,v_remainder
   from public.mme_inventory_landed_cost_pools p where p.receipt_id=v_receipt_id;
  else
   v_unit_ids:='{}'::uuid[];
   v_serial_count:=0;
   for v_serial in select * from public.mme_auction_import_serials where batch_line_id=v_line.id order by serial_number loop
    v_serial_count:=v_serial_count+1;
    -- Divide cents across units deterministically; residual cents go to the earliest sorted units.
    declare
     v_acq_unit bigint;
     v_extra_unit bigint;
     v_unit_acq_remainder bigint;
     v_unit_extra_remainder bigint;
    begin
     v_acq_unit:=floor(v_line.acquisition_line_cost_cents::numeric/v_line.source_quantity)::bigint;
     v_extra_unit:=floor(v_line_extra::numeric/v_line.source_quantity)::bigint;
     v_unit_acq_remainder:=v_line.acquisition_line_cost_cents-(v_acq_unit*v_line.source_quantity);
     v_unit_extra_remainder:=v_line_extra-(v_extra_unit*v_line.source_quantity);
     insert into public.mme_serialized_units(product_id,location_id,serial_number,imei,condition_grade)
     values(v_line.product_id,v_line.location_id,v_serial.serial_number,v_serial.imei,coalesce(v_line.condition_grade,'used'))
     returning id into v_unit_id;
     insert into public.mme_serialized_unit_costs(unit_id,acquisition_cost_cents,freight_cost_cents,
      auction_fee_cents,handling_cost_cents,other_cost_cents,source_reference,
      created_by_identity_id,approved_by_identity_id)
     values(v_unit_id,
      v_acq_unit+case when v_serial_count<=v_unit_acq_remainder then 1 else 0 end,
      case when v_serial_count<=floor(v_batch.freight_cost_cents::numeric*v_line_extra/greatest(v_extra,1)) then 0 else 0 end,
      0,0,0,v_batch.batch_reference,p_actor_identity_id,p_approved_by_identity_id);
     -- Replace the provisional cost components with a per-unit split of the line's additional allocation.
     update public.mme_serialized_unit_costs set
      freight_cost_cents=case when v_extra_unit+case when v_serial_count<=v_unit_extra_remainder then 1 else 0 end>0
       then v_extra_unit+case when v_serial_count<=v_unit_extra_remainder then 1 else 0 end else 0 end,
      other_cost_cents=0
     where unit_id=v_unit_id;
     v_unit_ids:=array_append(v_unit_ids,v_unit_id);
    end;
   end loop;
   update public.mme_auction_import_lines set linked_serialized_unit_ids=v_unit_ids,updated_at=now() where id=v_line.id;
  end if;
 end loop;

 update public.mme_auction_import_batches set status='received',received_receipt_id=v_receipt_id,updated_at=now()
 where id=p_batch_id and status='approved';
 if not found then raise exception 'Auction batch state changed during receiving' using errcode='40001'; end if;
 insert into public.mme_auction_import_events(batch_id,event_type,event_data,actor_identity_id)
 values(p_batch_id,'batch_received',jsonb_build_object('receipt_id',v_receipt_id,'total_landed_cost_cents',v_batch.acquisition_cost_cents+v_extra),p_actor_identity_id);
 return v_receipt_id;
end; $$;

revoke all on function public.mme_set_auction_import_serials(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.mme_receive_approved_auction_batch(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_set_auction_import_serials(uuid,uuid,jsonb) to service_role;
grant execute on function public.mme_receive_approved_auction_batch(uuid,uuid,uuid,text) to service_role;

comment on table public.mme_auction_import_serials is
 'Per-unit IMEI/serial data attached to serialized auction CSV rows before approval and receiving.';
comment on table public.mme_auction_import_line_costs is
 'Exact per-line auction landed-cost allocation, including residual cents for reconciliation.';
