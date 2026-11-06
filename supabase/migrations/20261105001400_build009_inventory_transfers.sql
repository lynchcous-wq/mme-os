-- Build 009.60 — controlled inter-location transfers and in-transit accountability.
begin;
create table public.mme_inventory_transfers (
 transfer_id uuid primary key default gen_random_uuid(),
 transfer_number text not null unique,
 source_location text not null, destination_location text not null,
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','picking','dispatched','in_transit','partially_received','received','exception','cancelled')),
 requested_by uuid not null, approved_by uuid, approved_at timestamptz,
 dispatched_by uuid, dispatched_at timestamptz, received_by uuid, received_at timestamptz,
 carrier text, tracking_reference text, shipment_reference text,
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(source_location<>destination_location),
 check(approved_by is null or approved_by<>requested_by)
);
create table public.mme_inventory_transfer_lines (
 transfer_line_id uuid primary key default gen_random_uuid(),
 transfer_id uuid not null references public.mme_inventory_transfers(transfer_id) on delete restrict,
 sku_reference text not null, currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 requested_quantity bigint not null check(requested_quantity>0),
 approved_quantity bigint not null default 0 check(approved_quantity>=0),
 picked_quantity bigint not null default 0 check(picked_quantity>=0),
 dispatched_quantity bigint not null default 0 check(dispatched_quantity>=0),
 received_quantity bigint not null default 0 check(received_quantity>=0),
 damaged_quantity bigint not null default 0 check(damaged_quantity>=0),
 missing_quantity bigint not null default 0 check(missing_quantity>=0),
 unit_cost numeric(18,6) not null default 0 check(unit_cost>=0),
 line_status text not null default 'draft' check(line_status in ('draft','approved','picked','dispatched','received','exception','cancelled')),
 created_at timestamptz not null default now(),
 unique(transfer_id,sku_reference,currency_code),
 check(approved_quantity<=requested_quantity),
 check(picked_quantity<=approved_quantity),
 check(dispatched_quantity<=picked_quantity),
 check(received_quantity+damaged_quantity<=dispatched_quantity)
);
create table public.mme_inventory_transfer_serials (
 transfer_serial_id uuid primary key default gen_random_uuid(),
 transfer_line_id uuid not null references public.mme_inventory_transfer_lines(transfer_line_id) on delete restrict,
 serial_number text, imei text, barcode text,
 serial_status text not null default 'picked' check(serial_status in ('picked','dispatched','received','damaged','missing','quarantined')),
 captured_by uuid not null, captured_at timestamptz not null default now(),
 check(coalesce(nullif(trim(serial_number),''),nullif(trim(imei),''),nullif(trim(barcode),'')) is not null),
 unique(serial_number),unique(imei),unique(barcode)
);
create table public.mme_inventory_transfer_events (
 event_id bigint generated always as identity primary key,
 transfer_id uuid not null references public.mme_inventory_transfers(transfer_id) on delete restrict,
 transfer_line_id uuid references public.mme_inventory_transfer_lines(transfer_line_id) on delete restrict,
 event_type text not null, actor_user_id uuid not null,
 event_data jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table public.mme_inventory_transfer_exceptions (
 exception_id uuid primary key default gen_random_uuid(),
 transfer_id uuid not null references public.mme_inventory_transfers(transfer_id) on delete restrict,
 transfer_line_id uuid references public.mme_inventory_transfer_lines(transfer_line_id) on delete restrict,
 exception_type text not null check(exception_type in ('short_pick','damaged_in_transit','missing_in_transit','wrong_sku','serial_mismatch','quantity_mismatch','other')),
 severity text not null default 'medium' check(severity in ('low','medium','high','critical')),
 description text not null, evidence_reference text,
 status text not null default 'open' check(status in ('open','investigating','resolved','waived')),
 resolution_note text, resolved_by uuid, resolved_at timestamptz,
 created_by uuid not null, created_at timestamptz not null default now()
);
create index mme_inventory_transfers_status_idx on public.mme_inventory_transfers(status,created_at desc);
create index mme_inventory_transfer_lines_transfer_idx on public.mme_inventory_transfer_lines(transfer_id);
create index mme_inventory_transfer_exceptions_open_idx on public.mme_inventory_transfer_exceptions(status,severity,created_at);
do $$ declare t text; begin foreach t in array array['mme_inventory_transfers','mme_inventory_transfer_lines','mme_inventory_transfer_serials','mme_inventory_transfer_events','mme_inventory_transfer_exceptions'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop; end $$;
grant select,insert,update on public.mme_inventory_transfers,public.mme_inventory_transfer_lines,public.mme_inventory_transfer_serials,public.mme_inventory_transfer_exceptions to service_role;
grant select,insert on public.mme_inventory_transfer_events to service_role;
revoke update,delete,truncate on public.mme_inventory_transfer_events from public,anon,authenticated,service_role;

create or replace function public.mme_inventory_transfer_create(p_number text,p_source text,p_destination text,p_actor uuid,p_notes text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid;
begin
 if p_source=p_destination or trim(coalesce(p_number,''))='' then raise exception 'Distinct locations and transfer number required' using errcode='22023'; end if;
 insert into public.mme_inventory_transfers(transfer_number,source_location,destination_location,requested_by,notes)
 values(p_number,p_source,p_destination,p_actor,left(p_notes,2000)) returning transfer_id into v_id;
 insert into public.mme_inventory_transfer_events(transfer_id,event_type,actor_user_id,event_data) values(v_id,'created',p_actor,jsonb_build_object('source',p_source,'destination',p_destination));
 return v_id;
end; $$;

create or replace function public.mme_inventory_transfer_add_line(p_transfer uuid,p_sku text,p_currency text,p_qty bigint,p_actor uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare t public.mme_inventory_transfers%rowtype; v_id uuid;
begin
 select * into t from public.mme_inventory_transfers where transfer_id=p_transfer for update;
 if not found or t.status<>'draft' then raise exception 'Draft transfer required' using errcode='55000'; end if;
 insert into public.mme_inventory_transfer_lines(transfer_id,sku_reference,currency_code,requested_quantity)
 values(p_transfer,p_sku,p_currency,p_qty) returning transfer_line_id into v_id;
 insert into public.mme_inventory_transfer_events(transfer_id,transfer_line_id,event_type,actor_user_id,event_data) values(p_transfer,v_id,'line_added',p_actor,jsonb_build_object('sku',p_sku,'quantity',p_qty));
 return v_id;
end; $$;

create or replace function public.mme_inventory_transfer_submit(p_transfer uuid,p_actor uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare n bigint;
begin
 perform 1 from public.mme_inventory_transfers where transfer_id=p_transfer and requested_by=p_actor and status='draft' for update;
 if not found then raise exception 'Transfer owner and draft status required' using errcode='55000'; end if;
 select count(*) into n from public.mme_inventory_transfer_lines where transfer_id=p_transfer;
 if n=0 then raise exception 'At least one transfer line required' using errcode='23514'; end if;
 update public.mme_inventory_transfers set status='pending_approval',updated_at=now() where transfer_id=p_transfer;
 insert into public.mme_inventory_transfer_events(transfer_id,event_type,actor_user_id) values(p_transfer,'submitted_for_approval',p_actor);
end; $$;

create or replace function public.mme_inventory_transfer_approve(p_transfer uuid,p_reviewer uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare t public.mme_inventory_transfers%rowtype; l record; b public.mme_inventory_balances%rowtype;
begin
 select * into t from public.mme_inventory_transfers where transfer_id=p_transfer for update;
 if not found or t.status<>'pending_approval' or t.requested_by=p_reviewer then raise exception 'Independent reviewer required for pending transfer' using errcode='55000'; end if;
 for l in select * from public.mme_inventory_transfer_lines where transfer_id=p_transfer order by transfer_line_id loop
  select * into b from public.mme_inventory_balances where sku_reference=l.sku_reference and location_code=t.source_location and currency_code=l.currency_code for update;
  if not found or b.on_hand_quantity-b.reserved_quantity<l.requested_quantity then raise exception 'Insufficient available source stock for SKU %',l.sku_reference using errcode='23514'; end if;
  update public.mme_inventory_transfer_lines set approved_quantity=requested_quantity,line_status='approved' where transfer_line_id=l.transfer_line_id;
 end loop;
 update public.mme_inventory_transfers set status='approved',approved_by=p_reviewer,approved_at=now(),updated_at=now() where transfer_id=p_transfer;
 insert into public.mme_inventory_transfer_events(transfer_id,event_type,actor_user_id) values(p_transfer,'approved',p_reviewer);
end; $$;

create or replace function public.mme_inventory_transfer_pick(p_line uuid,p_qty bigint,p_actor uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare l public.mme_inventory_transfer_lines%rowtype; t public.mme_inventory_transfers%rowtype;
begin
 select * into l from public.mme_inventory_transfer_lines where transfer_line_id=p_line for update;
 select * into t from public.mme_inventory_transfers where transfer_id=l.transfer_id for update;
 if t.status not in ('approved','picking') or p_qty<1 or l.picked_quantity+p_qty>l.approved_quantity then raise exception 'Invalid pick quantity or transfer state' using errcode='55000'; end if;
 update public.mme_inventory_transfer_lines set picked_quantity=picked_quantity+p_qty,line_status='picked' where transfer_line_id=p_line;
 update public.mme_inventory_transfers set status='picking',updated_at=now() where transfer_id=t.transfer_id;
 insert into public.mme_inventory_transfer_events(transfer_id,transfer_line_id,event_type,actor_user_id,event_data) values(t.transfer_id,p_line,'picked',p_actor,jsonb_build_object('quantity',p_qty));
end; $$;

create or replace function public.mme_inventory_transfer_capture_serial(p_line uuid,p_actor uuid,p_serial text,p_imei text,p_barcode text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid; l public.mme_inventory_transfer_lines%rowtype;
begin
 select * into l from public.mme_inventory_transfer_lines where transfer_line_id=p_line for update;
 if not found or l.line_status not in ('approved','picked') then raise exception 'Approved transfer line required' using errcode='55000'; end if;
 insert into public.mme_inventory_transfer_serials(transfer_line_id,serial_number,imei,barcode,captured_by)
 values(p_line,nullif(trim(p_serial),''),nullif(trim(p_imei),''),nullif(trim(p_barcode),''),p_actor) returning transfer_serial_id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_inventory_transfer_dispatch(p_transfer uuid,p_actor uuid,p_carrier text,p_tracking text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare t public.mme_inventory_transfers%rowtype; l public.mme_inventory_transfer_lines%rowtype; b public.mme_inventory_balances%rowtype;
 q bigint; val numeric(18,2); unit numeric(18,6); e uuid; ik text; serials bigint;
begin
 select * into t from public.mme_inventory_transfers where transfer_id=p_transfer for update;
 if not found or t.status not in ('approved','picking') then raise exception 'Approved transfer ready for dispatch required' using errcode='55000'; end if;
 if exists(select 1 from public.mme_inventory_transfer_lines where transfer_id=p_transfer and picked_quantity<>approved_quantity) then raise exception 'All approved quantities must be picked before dispatch' using errcode='23514'; end if;
 for l in select * from public.mme_inventory_transfer_lines where transfer_id=p_transfer order by transfer_line_id loop
  perform pg_advisory_xact_lock(hashtextextended(l.sku_reference||'|'||t.source_location||'|'||l.currency_code,0));
  select * into b from public.mme_inventory_balances where sku_reference=l.sku_reference and location_code=t.source_location and currency_code=l.currency_code for update;
  q:=l.picked_quantity;
  if b.on_hand_quantity-b.reserved_quantity<q then raise exception 'Source stock changed; dispatch blocked' using errcode='23514'; end if;
  val:=round(q*b.average_unit_cost,2); unit:=b.average_unit_cost;
  ik:='transfer-out:'||p_transfer::text||':'||l.transfer_line_id::text;
  insert into public.mme_inventory_ledger(idempotency_key,sku_reference,location_code,movement_type,quantity_delta,unit_cost,value_delta,currency_code,source_type,source_id,actor_user_id,reason)
  values(ik,l.sku_reference,t.source_location,'transfer_out',-q,unit,-val,l.currency_code,'inventory_transfer',p_transfer,p_actor,'Dispatch to '||t.destination_location) returning ledger_entry_id into e;
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity-q,inventory_value=inventory_value-val,
   average_unit_cost=case when on_hand_quantity-q=0 then 0 else round((inventory_value-val)/(on_hand_quantity-q),6) end,
   version=version+1,updated_at=now() where balance_id=b.balance_id;
  update public.mme_inventory_transfer_lines set dispatched_quantity=q,unit_cost=unit,line_status='dispatched' where transfer_line_id=l.transfer_line_id;
  select count(*) into serials from public.mme_inventory_transfer_serials where transfer_line_id=l.transfer_line_id;
  if serials>0 and serials<>q then raise exception 'Serialized transfer must capture one identifier per dispatched unit' using errcode='23514'; end if;
  update public.mme_inventory_transfer_serials set serial_status='dispatched' where transfer_line_id=l.transfer_line_id;
 end loop;
 update public.mme_inventory_transfers set status='in_transit',dispatched_by=p_actor,dispatched_at=now(),carrier=p_carrier,tracking_reference=p_tracking,updated_at=now() where transfer_id=p_transfer;
 insert into public.mme_inventory_transfer_events(transfer_id,event_type,actor_user_id,event_data) values(p_transfer,'dispatched',p_actor,jsonb_build_object('carrier',p_carrier,'tracking',p_tracking));
end; $$;

create or replace function public.mme_inventory_transfer_receive(p_transfer uuid,p_line uuid,p_received bigint,p_damaged bigint,p_actor uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare t public.mme_inventory_transfers%rowtype; l public.mme_inventory_transfer_lines%rowtype; b public.mme_inventory_balances%rowtype;
 q bigint; val numeric(18,2); unit numeric(18,6); e uuid; ik text; open_count bigint;
begin
 select * into t from public.mme_inventory_transfers where transfer_id=p_transfer for update;
 select * into l from public.mme_inventory_transfer_lines where transfer_line_id=p_line and transfer_id=p_transfer for update;
 if not found or t.status not in ('in_transit','partially_received','exception') then raise exception 'In-transit transfer line required' using errcode='55000'; end if;
 if p_received<0 or p_damaged<0 or p_received+p_damaged>l.dispatched_quantity-l.received_quantity-l.damaged_quantity then raise exception 'Invalid receiving quantities' using errcode='23514'; end if;
 q:=p_received+p_damaged;
 unit:=l.unit_cost; val:=round(p_received*unit,2);
 if p_received>0 then
  perform pg_advisory_xact_lock(hashtextextended(l.sku_reference||'|'||t.destination_location||'|'||l.currency_code,0));
  insert into public.mme_inventory_balances(sku_reference,location_code,currency_code) values(l.sku_reference,t.destination_location,l.currency_code)
  on conflict(sku_reference,location_code,currency_code) do nothing;
  select * into b from public.mme_inventory_balances where sku_reference=l.sku_reference and location_code=t.destination_location and currency_code=l.currency_code for update;
  ik:='transfer-in:'||p_transfer::text||':'||p_line::text||':'||(l.received_quantity+p_received)::text||':'||(l.damaged_quantity+p_damaged)::text;
  insert into public.mme_inventory_ledger(idempotency_key,sku_reference,location_code,movement_type,quantity_delta,unit_cost,value_delta,currency_code,source_type,source_id,actor_user_id,reason)
  values(ik,l.sku_reference,t.destination_location,'transfer_in',p_received,unit,val,l.currency_code,'inventory_transfer',p_transfer,p_actor,'Received from '||t.source_location) returning ledger_entry_id into e;
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity+p_received,inventory_value=inventory_value+val,
   average_unit_cost=case when on_hand_quantity+p_received=0 then 0 else round((inventory_value+val)/(on_hand_quantity+p_received),6) end,
   version=version+1,updated_at=now() where balance_id=b.balance_id;
  insert into public.mme_inventory_cost_layers(ledger_entry_id,sku_reference,location_code,currency_code,original_quantity,remaining_quantity,unit_cost)
  values(e,l.sku_reference,t.destination_location,l.currency_code,p_received,p_received,unit);
 end if;
 update public.mme_inventory_transfer_lines set received_quantity=received_quantity+p_received,damaged_quantity=damaged_quantity+p_damaged,
 line_status=case when received_quantity+p_received+damaged_quantity+p_damaged=dispatched_quantity then case when p_damaged>0 or missing_quantity>0 then 'exception' else 'received' end else 'exception' end
 where transfer_line_id=p_line;
 if p_damaged>0 then
  insert into public.mme_inventory_transfer_exceptions(transfer_id,transfer_line_id,exception_type,severity,description,created_by)
  values(p_transfer,p_line,'damaged_in_transit','high','Damaged units reported at destination: '||p_damaged,p_actor);
 end if;
 update public.mme_inventory_transfer_serials set serial_status='received' where transfer_line_id=p_line and serial_status='dispatched';
 select count(*) into open_count from public.mme_inventory_transfer_exceptions where transfer_id=p_transfer and status not in ('resolved','waived');
 update public.mme_inventory_transfers set status=case when open_count>0 or exists(select 1 from public.mme_inventory_transfer_lines where transfer_id=p_transfer and received_quantity+damaged_quantity<dispatched_quantity) then 'partially_received'
 when exists(select 1 from public.mme_inventory_transfer_lines where transfer_id=p_transfer and damaged_quantity>0) then 'exception' else 'received' end,
 received_by=p_actor,received_at=case when not exists(select 1 from public.mme_inventory_transfer_lines where transfer_id=p_transfer and received_quantity+damaged_quantity<dispatched_quantity) then now() else received_at end,updated_at=now()
 where transfer_id=p_transfer;
 insert into public.mme_inventory_transfer_events(transfer_id,transfer_line_id,event_type,actor_user_id,event_data)
 values(p_transfer,p_line,'destination_receipt_recorded',p_actor,jsonb_build_object('received',p_received,'damaged',p_damaged));
 return e;
end; $$;

create or replace function public.mme_inventory_transfer_reconcile(p_transfer uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare t public.mme_inventory_transfers%rowtype; expected bigint; received bigint; damaged bigint; missing bigint; v_id uuid;
begin
 select * into t from public.mme_inventory_transfers where transfer_id=p_transfer for update;
 if not found then raise exception 'Transfer not found' using errcode='22023'; end if;
 select coalesce(sum(dispatched_quantity),0),coalesce(sum(received_quantity),0),coalesce(sum(damaged_quantity),0)
 into expected,received,damaged from public.mme_inventory_transfer_lines where transfer_id=p_transfer;
 missing:=expected-received-damaged;
 if missing>0 or damaged>0 or exists(select 1 from public.mme_inventory_transfer_exceptions where transfer_id=p_transfer and status not in ('resolved','waived')) then
  update public.mme_inventory_transfers set status='exception',updated_at=now() where transfer_id=p_transfer;
  insert into public.mme_inventory_transfer_exceptions(transfer_id,exception_type,severity,description,created_by)
  values(p_transfer,case when missing>0 then 'missing_in_transit' else 'other' end,case when missing>0 then 'high' else 'medium' end,
  'Transfer reconciliation: dispatched='||expected||', received='||received||', damaged='||damaged||', missing='||missing,p_actor);
 else update public.mme_inventory_transfers set status='received',updated_at=now() where transfer_id=p_transfer; end if;
 insert into public.mme_inventory_transfer_events(transfer_id,event_type,actor_user_id,event_data)
 values(p_transfer,'reconciled',p_actor,jsonb_build_object('dispatched',expected,'received',received,'damaged',damaged,'missing',missing));
 return p_transfer;
end; $$;

revoke all on function public.mme_inventory_transfer_create(text,text,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_add_line(uuid,text,text,bigint,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_submit(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_approve(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_pick(uuid,bigint,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_capture_serial(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_dispatch(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_receive(uuid,uuid,bigint,bigint,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_transfer_reconcile(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_transfer_create(text,text,text,uuid,text) to service_role;
grant execute on function public.mme_inventory_transfer_add_line(uuid,text,text,bigint,uuid) to service_role;
grant execute on function public.mme_inventory_transfer_submit(uuid,uuid) to service_role;
grant execute on function public.mme_inventory_transfer_approve(uuid,uuid) to service_role;
grant execute on function public.mme_inventory_transfer_pick(uuid,bigint,uuid) to service_role;
grant execute on function public.mme_inventory_transfer_capture_serial(uuid,uuid,text,text,text) to service_role;
grant execute on function public.mme_inventory_transfer_dispatch(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_inventory_transfer_receive(uuid,uuid,bigint,bigint,uuid) to service_role;
grant execute on function public.mme_inventory_transfer_reconcile(uuid,uuid) to service_role;
commit;
