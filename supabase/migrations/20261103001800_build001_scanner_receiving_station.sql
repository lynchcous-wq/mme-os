-- Build 001: receiving-station scanner sessions and scan-to-record workflow.
-- Scans are resolved server-side; browser clients never receive unrestricted table access.

create table public.mme_receiving_station_sessions (
 id uuid primary key default gen_random_uuid(),
 session_reference text not null unique,
 purchase_order_id uuid references public.mme_purchase_orders(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 session_status text not null default 'open' check(session_status in ('open','submitted','completed','cancelled')),
 station_identifier text,
 opened_by_identity_id uuid not null,
 submitted_by_identity_id uuid,
 completed_by_identity_id uuid,
 opened_at timestamptz not null default now(),
 submitted_at timestamptz,
 completed_at timestamptz,
 notes text,
 created_at timestamptz not null default now()
);
create table public.mme_receiving_station_scans (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.mme_receiving_station_sessions(id) on delete restrict,
 scan_sequence bigint generated always as identity,
 scan_type text not null check(scan_type in ('sku','mme_barcode','serial','imei')),
 scanned_value text not null,
 product_id uuid references public.mme_products(id) on delete restrict,
 serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
 quantity integer not null default 1 check(quantity between 1 and 1000),
 scan_result text not null check(scan_result in ('matched','unmatched','duplicate','rejected')),
 actor_identity_id uuid not null,
 scanned_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object')
);
create index mme_receiving_station_sessions_status_idx on public.mme_receiving_station_sessions(session_status,opened_at desc);
create index mme_receiving_station_scans_session_idx on public.mme_receiving_station_scans(session_id,scan_sequence);
create index mme_receiving_station_scans_value_idx on public.mme_receiving_station_scans(scanned_value);
alter table public.mme_receiving_station_sessions enable row level security;
alter table public.mme_receiving_station_scans enable row level security;
revoke all on public.mme_receiving_station_sessions,public.mme_receiving_station_scans from anon,authenticated;
grant all on public.mme_receiving_station_sessions,public.mme_receiving_station_scans to service_role;

create or replace function public.mme_open_receiving_station_session(
 p_reference text,p_location_id uuid,p_actor_identity_id uuid,p_purchase_order_id uuid default null,
 p_station_identifier text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if p_reference is null or length(btrim(p_reference)) not between 3 and 80 or p_location_id is null or p_actor_identity_id is null then
  raise exception 'Invalid receiving station session' using errcode='22023';
 end if;
 if not exists(select 1 from public.mme_store_locations where id=p_location_id and active=true) then
  raise exception 'Active receiving location required' using errcode='P0002';
 end if;
 if p_purchase_order_id is not null and not exists(
  select 1 from public.mme_purchase_orders where id=p_purchase_order_id and status in ('issued','acknowledged','partially_received')
 ) then raise exception 'Purchase order is not open for receiving' using errcode='P0001'; end if;
 insert into public.mme_receiving_station_sessions(session_reference,purchase_order_id,location_id,station_identifier,opened_by_identity_id,notes)
 values(upper(btrim(p_reference)),p_purchase_order_id,p_location_id,left(p_station_identifier,100),p_actor_identity_id,left(p_notes,500))
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_scan_receiving_station(
 p_session_id uuid,p_scan_type text,p_scanned_value text,p_quantity integer,p_actor_identity_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_session record; v_product record; v_unit record; v_scan_id uuid; v_value text;
begin
 if p_session_id is null or p_scan_type not in ('sku','mme_barcode','serial','imei')
  or p_scanned_value is null or length(btrim(p_scanned_value)) not between 1 and 128
  or p_quantity is null or p_quantity<1 or p_quantity>1000 or p_actor_identity_id is null then
  raise exception 'Invalid receiving scan' using errcode='22023';
 end if;
 select * into v_session from public.mme_receiving_station_sessions where id=p_session_id for update;
 if not found or v_session.session_status<>'open' then raise exception 'Receiving session is not open' using errcode='P0001'; end if;
 v_value:=btrim(p_scanned_value);
 if p_scan_type in ('serial','imei') then
  select u.id,u.product_id,u.location_id,u.serial_number,u.imei,u.condition_grade,u.unit_status,
   p.sku,p.title,p.serialized,p.active
  into v_unit from public.mme_serialized_units u join public.mme_products p on p.id=u.product_id
  where (p_scan_type='serial' and u.serial_number=v_value) or (p_scan_type='imei' and u.imei=v_value)
  for update of u;
  if not found or not v_unit.active or not v_unit.serialized then
   insert into public.mme_receiving_station_scans(session_id,scan_type,scanned_value,quantity,scan_result,actor_identity_id)
   values(p_session_id,p_scan_type,v_value,p_quantity,'unmatched',p_actor_identity_id) returning id into v_scan_id;
   return jsonb_build_object('result','unmatched','scan_id',v_scan_id);
  end if;
  insert into public.mme_receiving_station_scans(session_id,scan_type,scanned_value,product_id,serialized_unit_id,quantity,scan_result,actor_identity_id)
  values(p_session_id,p_scan_type,v_value,v_unit.product_id,v_unit.id,p_quantity,
   case when v_unit.location_id=v_session.location_id and v_unit.unit_status='in_stock' then 'matched' else 'rejected' end,p_actor_identity_id)
  returning id into v_scan_id;
  return jsonb_build_object('result',case when v_unit.location_id=v_session.location_id and v_unit.unit_status='in_stock' then 'matched' else 'rejected' end,
   'scan_id',v_scan_id,'product_id',v_unit.product_id,'sku',v_unit.sku,'title',v_unit.title,
   'serial_number',v_unit.serial_number,'imei_last4',right(coalesce(v_unit.imei,''),4),'condition',v_unit.condition_grade,'unit_status',v_unit.unit_status);
 end if;
 v_value:=case when p_scan_type='mme_barcode' and left(v_value,4)='MME:' then substring(v_value from 5) else v_value end;
 select id,sku,title,condition_grade,unit_price_cents,serialized,active
 into v_product from public.mme_products where sku=v_value;
 if not found or not v_product.active then
  insert into public.mme_receiving_station_scans(session_id,scan_type,scanned_value,quantity,scan_result,actor_identity_id)
  values(p_session_id,p_scan_type,p_scanned_value,p_quantity,'unmatched',p_actor_identity_id) returning id into v_scan_id;
  return jsonb_build_object('result','unmatched','scan_id',v_scan_id);
 end if;
 if v_product.serialized then
  insert into public.mme_receiving_station_scans(session_id,scan_type,scanned_value,product_id,quantity,scan_result,actor_identity_id)
  values(p_session_id,p_scan_type,p_scanned_value,v_product.id,p_quantity,'rejected',p_actor_identity_id) returning id into v_scan_id;
  return jsonb_build_object('result','serialized_unit_requires_imei_or_serial','scan_id',v_scan_id,'product_id',v_product.id,'sku',v_product.sku,'title',v_product.title);
 end if;
 insert into public.mme_receiving_station_scans(session_id,scan_type,scanned_value,product_id,quantity,scan_result,actor_identity_id)
 values(p_session_id,p_scan_type,p_scanned_value,v_product.id,p_quantity,'matched',p_actor_identity_id) returning id into v_scan_id;
 return jsonb_build_object('result','matched','scan_id',v_scan_id,'product_id',v_product.id,'sku',v_product.sku,
  'title',v_product.title,'condition',v_product.condition_grade,'unit_price_cents',v_product.unit_price_cents,'quantity',p_quantity);
end; $$;

create or replace function public.mme_submit_receiving_station_session(
 p_session_id uuid,p_actor_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if p_actor_identity_id is null then raise exception 'Actor required' using errcode='22023'; end if;
 update public.mme_receiving_station_sessions set session_status='submitted',submitted_by_identity_id=p_actor_identity_id,submitted_at=now()
 where id=p_session_id and session_status='open'
 and exists(select 1 from public.mme_receiving_station_scans where session_id=p_session_id and scan_result='matched');
 return found;
end; $$;

create or replace function public.mme_complete_receiving_station_session(
 p_session_id uuid,p_receipt_reference text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_session record; v_lines jsonb; v_receipt uuid;
begin
 select * into v_session from public.mme_receiving_station_sessions where id=p_session_id for update;
 if not found or v_session.session_status<>'submitted' or v_session.purchase_order_id is null then
  raise exception 'Submitted PO-linked receiving session required' using errcode='P0001';
 end if;
 if p_actor_identity_id is null or p_approved_by_identity_id is null then raise exception 'Verified receiving approval required' using errcode='22023'; end if;
 if exists(select 1 from public.mme_receiving_station_scans where session_id=p_session_id and scan_result='unmatched') then
  raise exception 'Resolve unmatched scans before completing receipt' using errcode='23514';
 end if;
 select jsonb_agg(jsonb_build_object('line_id',pl.id,'quantity',sum(s.quantity)) order by pl.id)
 into v_lines
 from public.mme_receiving_station_scans s
 join public.mme_purchase_order_lines pl on pl.purchase_order_id=v_session.purchase_order_id
 join public.mme_products p on p.id=pl.product_id and p.id=s.product_id
 where s.session_id=p_session_id and s.scan_result='matched'
  and p.serialized=false and pl.location_id=v_session.location_id
 group by pl.id;
 if v_lines is null then raise exception 'No aggregate PO lines scanned for receipt' using errcode='22023'; end if;
 v_receipt:=public.mme_receive_purchase_order_lines(v_session.purchase_order_id,p_receipt_reference,p_actor_identity_id,p_approved_by_identity_id,v_lines);
 update public.mme_receiving_station_sessions set session_status='completed',completed_by_identity_id=p_actor_identity_id,completed_at=now()
 where id=p_session_id and session_status='submitted';
 return v_receipt;
end; $$;

create or replace function public.mme_receive_scanned_serialized_unit(
 p_session_id uuid,p_scan_id uuid,p_serial_number text,p_imei text,p_condition_grade text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_session record; v_scan record; v_unit_id uuid;
begin
 select * into v_session from public.mme_receiving_station_sessions where id=p_session_id for update;
 if not found or v_session.session_status<>'open' then raise exception 'Receiving session is not open' using errcode='P0001'; end if;
 select s.id,s.product_id,s.scan_result into v_scan from public.mme_receiving_station_scans s
 where s.id=p_scan_id and s.session_id=p_session_id and s.scan_result='rejected' for update;
 if not found then raise exception 'Matching serialized SKU scan required' using errcode='P0002'; end if;
 v_unit_id:=public.mme_receive_serialized_unit(v_scan.product_id,v_session.location_id,p_serial_number,p_imei,p_condition_grade);
 update public.mme_receiving_station_scans set serialized_unit_id=v_unit_id,scan_type='serial',scanned_value=p_serial_number,scan_result='matched'
 where id=p_scan_id;
 return v_unit_id;
end; $$;

revoke all on function public.mme_open_receiving_station_session(text,uuid,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_scan_receiving_station(uuid,text,text,integer,uuid) from public,anon,authenticated;
revoke all on function public.mme_submit_receiving_station_session(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_complete_receiving_station_session(uuid,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_receive_scanned_serialized_unit(uuid,uuid,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_open_receiving_station_session(text,uuid,uuid,uuid,text,text) to service_role;
grant execute on function public.mme_scan_receiving_station(uuid,text,text,integer,uuid) to service_role;
grant execute on function public.mme_submit_receiving_station_session(uuid,uuid) to service_role;
grant execute on function public.mme_complete_receiving_station_session(uuid,text,uuid,uuid) to service_role;
grant execute on function public.mme_receive_scanned_serialized_unit(uuid,uuid,text,text,text,uuid) to service_role;

comment on table public.mme_receiving_station_sessions is 'Auditable scanner-assisted receiving sessions, optionally linked to a purchase order.';
comment on table public.mme_receiving_station_scans is 'Scan-by-scan audit trail; serialized devices require individual serial or IMEI capture.';
