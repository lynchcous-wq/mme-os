-- Build 001: link each serialized device to a PO line and receiving scan.
create table public.mme_purchase_order_serialized_receipts (
 id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.mme_purchase_orders(id) on delete restrict,
 purchase_order_line_id uuid not null references public.mme_purchase_order_lines(id) on delete restrict,
 receiving_session_id uuid not null references public.mme_receiving_station_sessions(id) on delete restrict,
 receiving_scan_id uuid not null unique references public.mme_receiving_station_scans(id) on delete restrict,
 unit_id uuid not null unique references public.mme_serialized_units(id) on delete restrict,
 receipt_reference text not null,
 received_by_identity_id uuid not null,
 approved_by_identity_id uuid not null,
 received_at timestamptz not null default now()
);
create index mme_po_serialized_receipts_po_line_idx on public.mme_purchase_order_serialized_receipts(purchase_order_line_id,received_at desc);
alter table public.mme_purchase_order_serialized_receipts enable row level security;
revoke all on public.mme_purchase_order_serialized_receipts from public,anon,authenticated;
grant all on public.mme_purchase_order_serialized_receipts to service_role;

create or replace function public.mme_receive_scanned_serialized_po_unit(
 p_session_id uuid,p_scan_id uuid,p_po_line_id uuid,p_serial_number text,p_imei text,
 p_condition_grade text,p_acquisition_cost_cents bigint,p_freight_cost_cents bigint,
 p_auction_fee_cents bigint,p_handling_cost_cents bigint,p_other_cost_cents bigint,
 p_receipt_reference text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_session record; v_scan record; v_line record; v_unit_id uuid; v_cost_id uuid;
begin
 if p_actor_identity_id is null or p_approved_by_identity_id is null or p_actor_identity_id=p_approved_by_identity_id then
  raise exception 'Independent receiving approval is required' using errcode='42501'; end if;
 if p_receipt_reference is null or length(btrim(p_receipt_reference)) not between 3 and 100 then
  raise exception 'Valid receipt reference required' using errcode='22023'; end if;
 if p_acquisition_cost_cents is null or p_acquisition_cost_cents<0 or p_freight_cost_cents is null or p_freight_cost_cents<0
  or p_auction_fee_cents is null or p_auction_fee_cents<0 or p_handling_cost_cents is null or p_handling_cost_cents<0
  or p_other_cost_cents is null or p_other_cost_cents<0 then raise exception 'Invalid per-unit cost' using errcode='22023'; end if;
 select * into v_session from public.mme_receiving_station_sessions where id=p_session_id for update;
 if not found or v_session.session_status<>'open' or v_session.purchase_order_id is null then
  raise exception 'Open PO-linked receiving session required' using errcode='P0001'; end if;
 select s.id,s.product_id,s.scan_result,s.serialized_unit_id into v_scan
 from public.mme_receiving_station_scans s where s.id=p_scan_id and s.session_id=p_session_id for update;
 if not found or v_scan.scan_result<>'rejected' or v_scan.serialized_unit_id is not null then
  raise exception 'Unresolved serialized SKU scan required' using errcode='P0002'; end if;
 select pl.* into v_line from public.mme_purchase_order_lines pl
 join public.mme_products p on p.id=pl.product_id and p.serialized=true
 where pl.id=p_po_line_id and pl.purchase_order_id=v_session.purchase_order_id
  and pl.product_id=v_scan.product_id and pl.location_id=v_session.location_id for update of pl;
 if not found then raise exception 'Serialized product does not match this PO line and location' using errcode='23514'; end if;
 if v_line.received_quantity>=v_line.ordered_quantity then raise exception 'PO line is already fully received' using errcode='23514'; end if;
 v_unit_id:=public.mme_receive_serialized_unit(v_line.product_id,v_line.location_id,p_serial_number,p_imei,p_condition_grade);
 v_cost_id:=public.mme_record_serialized_unit_landed_cost(v_unit_id,p_acquisition_cost_cents,p_freight_cost_cents,
  p_auction_fee_cents,p_handling_cost_cents,p_other_cost_cents,p_receipt_reference,p_actor_identity_id,p_approved_by_identity_id);
 insert into public.mme_purchase_order_serialized_receipts(purchase_order_id,purchase_order_line_id,receiving_session_id,
  receiving_scan_id,unit_id,receipt_reference,received_by_identity_id,approved_by_identity_id)
 values(v_session.purchase_order_id,p_po_line_id,p_session_id,p_scan_id,v_unit_id,btrim(p_receipt_reference),p_actor_identity_id,p_approved_by_identity_id);
 update public.mme_purchase_order_lines set received_quantity=received_quantity+1 where id=p_po_line_id;
 update public.mme_receiving_station_scans set serialized_unit_id=v_unit_id,scan_type='serial',scanned_value=p_serial_number,
  scan_result='matched',metadata=metadata||jsonb_build_object('po_line_id',p_po_line_id,'landed_cost_record_id',v_cost_id)
 where id=p_scan_id;
 insert into public.mme_purchase_order_events(purchase_order_id,event_type,event_data,actor_identity_id)
 values(v_session.purchase_order_id,'serialized_unit_received',jsonb_build_object('po_line_id',p_po_line_id,'unit_id',v_unit_id,'receipt_reference',p_receipt_reference),p_actor_identity_id);
 return v_unit_id;
end; $$;

create or replace function public.mme_complete_receiving_station_session(
 p_session_id uuid,p_receipt_reference text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_session record; v_lines jsonb; v_receipt uuid; v_has_serialized boolean:=false;
begin
 select * into v_session from public.mme_receiving_station_sessions where id=p_session_id for update;
 if not found or v_session.session_status<>'submitted' or v_session.purchase_order_id is null then
  raise exception 'Submitted PO-linked receiving session required' using errcode='P0001'; end if;
 if p_actor_identity_id is null or p_approved_by_identity_id is null or p_actor_identity_id=p_approved_by_identity_id then
  raise exception 'Independent receiving approval required' using errcode='42501'; end if;
 if exists(select 1 from public.mme_receiving_station_scans where session_id=p_session_id and scan_result in ('unmatched','rejected','duplicate')) then
  raise exception 'Resolve all unmatched, rejected and duplicate scans before completing receipt' using errcode='23514'; end if;
 if exists(select 1 from public.mme_receiving_station_scans s where s.session_id=p_session_id and s.scan_result='matched'
  and s.serialized_unit_id is not null and not exists(select 1 from public.mme_purchase_order_serialized_receipts r
   where r.receiving_scan_id=s.id and r.receiving_session_id=p_session_id and r.purchase_order_id=v_session.purchase_order_id)) then
  raise exception 'Every serialized scan must be reconciled to a PO line' using errcode='23514'; end if;
 if exists(select 1 from public.mme_receiving_station_scans s where s.session_id=p_session_id and s.scan_result='matched'
  and s.serialized_unit_id is null and not exists(select 1 from public.mme_purchase_order_lines pl
   where pl.purchase_order_id=v_session.purchase_order_id and pl.product_id=s.product_id and pl.location_id=v_session.location_id)) then
  raise exception 'Scanned product is not on this PO at this receiving location' using errcode='23514'; end if;
 select coalesce(bool_or(s.serialized_unit_id is not null),false) into v_has_serialized
 from public.mme_receiving_station_scans s where s.session_id=p_session_id and s.scan_result='matched';
 select jsonb_agg(jsonb_build_object('line_id',pl.id,'quantity',sum(s.quantity)) order by pl.id)
 into v_lines from public.mme_receiving_station_scans s
 join public.mme_purchase_order_lines pl on pl.purchase_order_id=v_session.purchase_order_id
 join public.mme_products p on p.id=pl.product_id and p.id=s.product_id
 where s.session_id=p_session_id and s.scan_result='matched' and s.serialized_unit_id is null
  and p.serialized=false and pl.location_id=v_session.location_id group by pl.id;
 if v_lines is not null then
  v_receipt:=public.mme_receive_purchase_order_lines(v_session.purchase_order_id,p_receipt_reference,p_actor_identity_id,p_approved_by_identity_id,v_lines);
 elsif not v_has_serialized then raise exception 'No reconciled items found for receipt' using errcode='22023';
 else v_receipt:=gen_random_uuid(); end if;
 update public.mme_purchase_orders po set status=case when not exists(select 1 from public.mme_purchase_order_lines pl
  where pl.purchase_order_id=po.id and pl.received_quantity<pl.ordered_quantity) then 'received'
  else 'partially_received' end,updated_at=now() where po.id=v_session.purchase_order_id;
 update public.mme_receiving_station_sessions set session_status='completed',completed_by_identity_id=p_actor_identity_id,completed_at=now()
 where id=p_session_id and session_status='submitted';
 return v_receipt;
end; $$;

revoke all on function public.mme_receive_scanned_serialized_po_unit(uuid,uuid,uuid,text,text,text,bigint,bigint,bigint,bigint,bigint,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_receive_scanned_serialized_po_unit(uuid,uuid,uuid,text,text,text,bigint,bigint,bigint,bigint,bigint,text,uuid,uuid) to service_role;
revoke all on function public.mme_complete_receiving_station_session(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_complete_receiving_station_session(uuid,text,uuid,uuid) to service_role;
comment on table public.mme_purchase_order_serialized_receipts is 'One-to-one link between a PO line, receiving scan, physical serialized device and per-unit landed-cost record.';