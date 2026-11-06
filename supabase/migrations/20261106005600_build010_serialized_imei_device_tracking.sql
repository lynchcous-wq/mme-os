begin;
create table if not exists public.mme_inventory_device_assets(
 device_asset_id uuid primary key default gen_random_uuid(),
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 serial_number text,
 imei_1 text,
 imei_2 text,
 asset_status text not null default 'available' check(asset_status in('available','reserved','sold','repair','returned','retired','blacklisted','missing')),
 condition_grade text not null default 'ungraded' check(condition_grade in('ungraded','new','open_box','excellent','good','fair','parts_only')),
 acquisition_reference text,
 acquisition_date date,
 cost_basis numeric(12,2) check(cost_basis is null or cost_basis>=0),
 barcode_value text not null unique,
 warranty_reference text,
 notes text,
 registered_by_auth_user_id uuid not null,
 registered_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(serial_number is not null or imei_1 is not null),
 check(imei_1 is null or imei_1 ~ '^[0-9]{14,16}$'),
 check(imei_2 is null or imei_2 ~ '^[0-9]{14,16}$'),
 check(imei_2 is null or imei_1 is not null),
 unique(inventory_item_id,serial_number)
);
create unique index if not exists mme_device_assets_serial_unique on public.mme_inventory_device_assets(upper(serial_number)) where serial_number is not null;
create unique index if not exists mme_device_assets_imei1_unique on public.mme_inventory_device_assets(imei_1) where imei_1 is not null;
create unique index if not exists mme_device_assets_imei2_unique on public.mme_inventory_device_assets(imei_2) where imei_2 is not null;
create unique index if not exists mme_device_assets_imei_cross_1_unique on public.mme_inventory_device_assets(imei_1) where imei_1 is not null;
create or replace function public.mme_inventory_validate_device_identifiers()
returns trigger language plpgsql set search_path=public as $
begin
 if new.imei_1 is not null and (new.imei_1 !~ '^[0-9]{14,16}
create table if not exists public.mme_inventory_device_events(
 device_event_id uuid primary key default gen_random_uuid(),
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 event_type text not null check(event_type in('registered','condition_updated','location_changed','reserved','reservation_released','sold','returned','repair_started','repair_completed','blacklisted','unblacklisted','marked_missing','recovered','retired','warranty_updated')),
 from_status text,
 to_status text,
 from_location_id uuid references public.mme_inventory_locations(location_id) on delete restrict,
 to_location_id uuid references public.mme_inventory_locations(location_id) on delete restrict,
 source_reference text,
 event_detail text,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_inventory_device_events_asset_idx on public.mme_inventory_device_events(device_asset_id,created_at desc);
create table if not exists public.mme_warehouse_fulfillment_device_manifest(
 manifest_id uuid primary key default gen_random_uuid(),
 fulfillment_job_line_id uuid not null references public.mme_warehouse_fulfillment_job_lines(fulfillment_job_line_id) on delete restrict,
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 scanned_by_auth_user_id uuid not null,
 scanned_at timestamptz not null default now(),
 unique(fulfillment_job_line_id,device_asset_id),
 unique(device_asset_id)
);
create or replace function public.mme_inventory_register_device(p_item uuid,p_location uuid,p_serial text,p_imei1 text,p_imei2 text,p_grade text,p_acquisition_reference text,p_cost numeric,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.mme_inventory_items%rowtype; a public.mme_inventory_device_assets%rowtype; code text;
begin
 if p_actor is null or p_item is null or p_location is null then raise exception 'device_item_location_actor_required'; end if;
 select * into i from public.mme_inventory_items where inventory_item_id=p_item;
 if not found then raise exception 'inventory_item_not_found'; end if;
 if not coalesce(i.track_serial,false) and not coalesce(i.track_imei,false) then raise exception 'item_not_configured_for_device_tracking'; end if;
 if coalesce(i.track_serial,false) and nullif(trim(coalesce(p_serial,'')),'') is null then raise exception 'serial_number_required'; end if;
 if coalesce(i.track_imei,false) and nullif(trim(coalesce(p_imei1,'')),'') is null then raise exception 'imei_required'; end if;
 if p_imei1 is not null and p_imei1 !~ '^[0-9]{14,16}$' then raise exception 'invalid_imei_1'; end if;
 if p_imei2 is not null and p_imei2 !~ '^[0-9]{14,16}$' then raise exception 'invalid_imei_2'; end if;
 code:='MME-'||replace(gen_random_uuid()::text,'-','');
 insert into public.mme_inventory_device_assets(inventory_item_id,location_id,serial_number,imei_1,imei_2,condition_grade,acquisition_reference,cost_basis,barcode_value,registered_by_auth_user_id)
 values(p_item,p_location,nullif(trim(p_serial),''),nullif(trim(p_imei1),''),nullif(trim(p_imei2),''),coalesce(p_grade,'ungraded'),p_acquisition_reference,p_cost,code,p_actor) returning * into a;
 insert into public.mme_inventory_device_events(device_asset_id,event_type,to_status,to_location_id,event_detail,actor_auth_user_id)
 values(a.device_asset_id,'registered','available',p_location,'Device registered with unique serial/IMEI identifiers.',p_actor);
 return jsonb_build_object('device_asset_id',a.device_asset_id,'barcode_value',a.barcode_value,'asset_status',a.asset_status);
end $$;
create or replace function public.mme_inventory_attach_fulfillment_device(p_line uuid,p_device uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l public.mme_warehouse_fulfillment_job_lines%rowtype; a public.mme_inventory_device_assets%rowtype; j public.mme_warehouse_fulfillment_jobs%rowtype;
begin
 select * into l from public.mme_warehouse_fulfillment_job_lines where fulfillment_job_line_id=p_line for update;
 if not found then raise exception 'fulfillment_line_not_found'; end if;
 select * into j from public.mme_warehouse_fulfillment_jobs where fulfillment_job_id=l.fulfillment_job_id for update;
 if j.fulfillment_status in('shipped','cancelled') or j.inventory_posting_status='posted' then raise exception 'fulfillment_manifest_locked'; end if;
 select * into a from public.mme_inventory_device_assets where device_asset_id=p_device for update;
 if not found then raise exception 'device_asset_not_found'; end if;
 if a.inventory_item_id<>l.inventory_item_id or a.location_id<>l.source_location_id then raise exception 'device_item_or_location_mismatch'; end if;
 if a.asset_status not in('available','reserved') then raise exception 'device_not_available_for_fulfillment'; end if;
 insert into public.mme_warehouse_fulfillment_device_manifest(fulfillment_job_line_id,device_asset_id,scanned_by_auth_user_id) values(p_line,p_device,p_actor);
 insert into public.mme_inventory_device_events(device_asset_id,event_type,from_status,to_status,source_reference,event_detail,actor_auth_user_id)
 values(p_device,'reserved',a.asset_status,'reserved',j.source_reference,'Device scanned into fulfillment manifest.',p_actor);
 update public.mme_inventory_device_assets set asset_status='reserved',updated_at=now() where device_asset_id=p_device;
 return jsonb_build_object('manifest_id',(select manifest_id from public.mme_warehouse_fulfillment_device_manifest where fulfillment_job_line_id=p_line and device_asset_id=p_device),'device_asset_id',p_device,'asset_status','reserved');
end $$;
create or replace function public.mme_inventory_post_fulfillment_serialized(p_job uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare j public.mme_warehouse_fulfillment_jobs%rowtype; q public.mme_warehouse_inventory_posting_queue%rowtype; l record; b public.mme_inventory_stock_balances%rowtype; a public.mme_inventory_device_assets%rowtype; before_qty integer; after_qty integer; n integer:=0; total integer:=0; units integer; movement_ref text;
begin
 if p_job is null or p_actor is null then raise exception 'posting_job_and_actor_required'; end if;
 select * into j from public.mme_warehouse_fulfillment_jobs where fulfillment_job_id=p_job for update;
 if not found then raise exception 'fulfillment_job_not_found'; end if;
 select * into q from public.mme_warehouse_inventory_posting_queue where fulfillment_job_id=p_job for update;
 if not found then raise exception 'posting_queue_not_found'; end if;
 if q.posting_status='posted' or j.inventory_posting_status='posted' then return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','idempotent_replay',true,'inventory_changed',false); end if;
 if j.fulfillment_status in('cancelled','shipped') or (j.fulfillment_status='blocked' and j.inventory_posting_status<>'failed') then raise exception 'fulfillment_job_not_postable'; end if;
 if j.source_type<>'customer_order' then raise exception 'source_type_requires_specialized_inventory_workflow'; end if;
 if q.posting_status not in('pending','failed','processing') then raise exception 'posting_queue_not_retryable'; end if;
 update public.mme_warehouse_inventory_posting_queue set posting_status='processing',attempt_count=attempt_count+1,last_attempt_at=now(),updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
 update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='processing',updated_at=now() where fulfillment_job_id=p_job;
 begin
  if not exists(select 1 from public.mme_warehouse_fulfillment_job_lines where fulfillment_job_id=p_job) then raise exception 'fulfillment_has_no_lines'; end if;
  for l in select fl.*,i.sku,i.track_serial,i.track_imei from public.mme_warehouse_fulfillment_job_lines fl join public.mme_inventory_items i on i.inventory_item_id=fl.inventory_item_id where fl.fulfillment_job_id=p_job order by fl.inventory_item_id,fl.source_location_id,fl.fulfillment_job_line_id loop
   select * into b from public.mme_inventory_stock_balances where inventory_item_id=l.inventory_item_id and location_id=l.source_location_id for update;
   if not found then raise exception 'inventory_balance_not_initialized_for_sku_%',l.sku; end if;
   before_qty:=b.quantity_on_hand;
   if before_qty-b.quantity_reserved<l.fulfilled_quantity then raise exception 'insufficient_available_stock_for_sku_%',l.sku; end if;
   if coalesce(l.track_serial,false) or coalesce(l.track_imei,false) then
    select count(*) into units from public.mme_warehouse_fulfillment_device_manifest m join public.mme_inventory_device_assets d on d.device_asset_id=m.device_asset_id where m.fulfillment_job_line_id=l.fulfillment_job_line_id and d.asset_status='reserved';
    if units<>l.fulfilled_quantity then raise exception 'serialized_manifest_quantity_mismatch_for_sku_%',l.sku; end if;
    for a in select d.* from public.mme_warehouse_fulfillment_device_manifest m join public.mme_inventory_device_assets d on d.device_asset_id=m.device_asset_id where m.fulfillment_job_line_id=l.fulfillment_job_line_id order by d.device_asset_id for update of d loop
     if a.asset_status<>'reserved' or a.location_id<>l.source_location_id then raise exception 'serialized_device_state_or_location_mismatch'; end if;
     update public.mme_inventory_device_assets set asset_status='sold',updated_at=now() where device_asset_id=a.device_asset_id;
     insert into public.mme_inventory_device_events(device_asset_id,event_type,from_status,to_status,source_reference,event_detail,actor_auth_user_id)
     values(a.device_asset_id,'sold','reserved','sold',j.source_reference,'Serialized device sold through fulfillment posting.',p_actor);
    end loop;
   end if;
   after_qty:=before_qty-l.fulfilled_quantity;
   update public.mme_inventory_stock_balances set quantity_on_hand=after_qty,version=version+1,updated_at=now() where stock_balance_id=b.stock_balance_id;
   insert into public.mme_inventory_reservations(fulfillment_job_id,inventory_item_id,location_id,quantity,reservation_status,idempotency_key,finalized_at,actor_auth_user_id)
   values(p_job,l.inventory_item_id,l.source_location_id,l.fulfilled_quantity,'consumed','fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,now(),p_actor);
   insert into public.mme_inventory_movements(movement_number,inventory_item_id,location_id,movement_type,quantity_delta,quantity_before,quantity_after,source_type,source_reference,fulfillment_job_id,idempotency_key,actor_auth_user_id)
   values('FUL-'||replace(gen_random_uuid()::text,'-',''),l.inventory_item_id,l.source_location_id,'fulfillment_sale',-l.fulfilled_quantity,before_qty,after_qty,j.source_type,j.source_reference,p_job,'fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,p_actor) returning movement_number into movement_ref;
   n:=n+1;total:=total+l.fulfilled_quantity;
  end loop;
  update public.mme_warehouse_inventory_posting_queue set posting_status='posted',posted_movement_reference='fulfillment:'||p_job::text,updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='posted',fulfillment_status='inventory_posted',inventory_posted_at=now(),failure_code=null,failure_detail=null,updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'inventory_posted',format('Atomically posted %s inventory movement lines totaling %s units.',n,total),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','movement_lines',n,'units_posted',total,'inventory_changed',true,'idempotent_replay',false);
 exception when others then
  update public.mme_warehouse_inventory_posting_queue set posting_status='failed',error_code=sqlstate,error_detail=left(sqlerrm,500),updated_at=now() where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='failed',fulfillment_status='blocked',failure_code=sqlstate,failure_detail=left(sqlerrm,500),updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'posting_failed',left(sqlerrm,500),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','failed','error_code',sqlstate,'error',left(sqlerrm,500),'inventory_changed',false);
 end;
end $$;
revoke all on function public.mme_inventory_register_device(uuid,uuid,text,text,text,text,text,numeric,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_attach_fulfillment_device(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_post_fulfillment_serialized(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_register_device(uuid,uuid,text,text,text,text,text,numeric,uuid) to service_role;
grant execute on function public.mme_inventory_attach_fulfillment_device(uuid,uuid,uuid) to service_role;
grant execute on function public.mme_inventory_post_fulfillment_serialized(uuid,uuid) to service_role;
do $$declare t text;begin foreach t in array array['mme_inventory_device_assets','mme_inventory_device_events','mme_warehouse_fulfillment_device_manifest'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
commit; or (select sum((substr(new.imei_1, length(new.imei_1)-g, 1)::integer * case when g%2=1 then 2 else 1 end / 10 + (substr(new.imei_1,length(new.imei_1)-g,1)::integer * case when g%2=1 then 2 else 1 end)%10) from generate_series(0,length(new.imei_1)-1) g)%10<>0) then raise exception 'invalid_imei_1'; end if;
 if new.imei_2 is not null and (new.imei_2 !~ '^[0-9]{14,16}
create table if not exists public.mme_inventory_device_events(
 device_event_id uuid primary key default gen_random_uuid(),
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 event_type text not null check(event_type in('registered','condition_updated','location_changed','reserved','reservation_released','sold','returned','repair_started','repair_completed','blacklisted','unblacklisted','marked_missing','recovered','retired','warranty_updated')),
 from_status text,
 to_status text,
 from_location_id uuid references public.mme_inventory_locations(location_id) on delete restrict,
 to_location_id uuid references public.mme_inventory_locations(location_id) on delete restrict,
 source_reference text,
 event_detail text,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_inventory_device_events_asset_idx on public.mme_inventory_device_events(device_asset_id,created_at desc);
create table if not exists public.mme_warehouse_fulfillment_device_manifest(
 manifest_id uuid primary key default gen_random_uuid(),
 fulfillment_job_line_id uuid not null references public.mme_warehouse_fulfillment_job_lines(fulfillment_job_line_id) on delete restrict,
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 scanned_by_auth_user_id uuid not null,
 scanned_at timestamptz not null default now(),
 unique(fulfillment_job_line_id,device_asset_id),
 unique(device_asset_id)
);
create or replace function public.mme_inventory_register_device(p_item uuid,p_location uuid,p_serial text,p_imei1 text,p_imei2 text,p_grade text,p_acquisition_reference text,p_cost numeric,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.mme_inventory_items%rowtype; a public.mme_inventory_device_assets%rowtype; code text;
begin
 if p_actor is null or p_item is null or p_location is null then raise exception 'device_item_location_actor_required'; end if;
 select * into i from public.mme_inventory_items where inventory_item_id=p_item;
 if not found then raise exception 'inventory_item_not_found'; end if;
 if not coalesce(i.track_serial,false) and not coalesce(i.track_imei,false) then raise exception 'item_not_configured_for_device_tracking'; end if;
 if coalesce(i.track_serial,false) and nullif(trim(coalesce(p_serial,'')),'') is null then raise exception 'serial_number_required'; end if;
 if coalesce(i.track_imei,false) and nullif(trim(coalesce(p_imei1,'')),'') is null then raise exception 'imei_required'; end if;
 if p_imei1 is not null and p_imei1 !~ '^[0-9]{14,16}$' then raise exception 'invalid_imei_1'; end if;
 if p_imei2 is not null and p_imei2 !~ '^[0-9]{14,16}$' then raise exception 'invalid_imei_2'; end if;
 code:='MME-'||replace(gen_random_uuid()::text,'-','');
 insert into public.mme_inventory_device_assets(inventory_item_id,location_id,serial_number,imei_1,imei_2,condition_grade,acquisition_reference,cost_basis,barcode_value,registered_by_auth_user_id)
 values(p_item,p_location,nullif(trim(p_serial),''),nullif(trim(p_imei1),''),nullif(trim(p_imei2),''),coalesce(p_grade,'ungraded'),p_acquisition_reference,p_cost,code,p_actor) returning * into a;
 insert into public.mme_inventory_device_events(device_asset_id,event_type,to_status,to_location_id,event_detail,actor_auth_user_id)
 values(a.device_asset_id,'registered','available',p_location,'Device registered with unique serial/IMEI identifiers.',p_actor);
 return jsonb_build_object('device_asset_id',a.device_asset_id,'barcode_value',a.barcode_value,'asset_status',a.asset_status);
end $$;
create or replace function public.mme_inventory_attach_fulfillment_device(p_line uuid,p_device uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l public.mme_warehouse_fulfillment_job_lines%rowtype; a public.mme_inventory_device_assets%rowtype; j public.mme_warehouse_fulfillment_jobs%rowtype;
begin
 select * into l from public.mme_warehouse_fulfillment_job_lines where fulfillment_job_line_id=p_line for update;
 if not found then raise exception 'fulfillment_line_not_found'; end if;
 select * into j from public.mme_warehouse_fulfillment_jobs where fulfillment_job_id=l.fulfillment_job_id for update;
 if j.fulfillment_status in('shipped','cancelled') or j.inventory_posting_status='posted' then raise exception 'fulfillment_manifest_locked'; end if;
 select * into a from public.mme_inventory_device_assets where device_asset_id=p_device for update;
 if not found then raise exception 'device_asset_not_found'; end if;
 if a.inventory_item_id<>l.inventory_item_id or a.location_id<>l.source_location_id then raise exception 'device_item_or_location_mismatch'; end if;
 if a.asset_status not in('available','reserved') then raise exception 'device_not_available_for_fulfillment'; end if;
 insert into public.mme_warehouse_fulfillment_device_manifest(fulfillment_job_line_id,device_asset_id,scanned_by_auth_user_id) values(p_line,p_device,p_actor);
 insert into public.mme_inventory_device_events(device_asset_id,event_type,from_status,to_status,source_reference,event_detail,actor_auth_user_id)
 values(p_device,'reserved',a.asset_status,'reserved',j.source_reference,'Device scanned into fulfillment manifest.',p_actor);
 update public.mme_inventory_device_assets set asset_status='reserved',updated_at=now() where device_asset_id=p_device;
 return jsonb_build_object('manifest_id',(select manifest_id from public.mme_warehouse_fulfillment_device_manifest where fulfillment_job_line_id=p_line and device_asset_id=p_device),'device_asset_id',p_device,'asset_status','reserved');
end $$;
create or replace function public.mme_inventory_post_fulfillment_serialized(p_job uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare j public.mme_warehouse_fulfillment_jobs%rowtype; q public.mme_warehouse_inventory_posting_queue%rowtype; l record; b public.mme_inventory_stock_balances%rowtype; a public.mme_inventory_device_assets%rowtype; before_qty integer; after_qty integer; n integer:=0; total integer:=0; units integer; movement_ref text;
begin
 if p_job is null or p_actor is null then raise exception 'posting_job_and_actor_required'; end if;
 select * into j from public.mme_warehouse_fulfillment_jobs where fulfillment_job_id=p_job for update;
 if not found then raise exception 'fulfillment_job_not_found'; end if;
 select * into q from public.mme_warehouse_inventory_posting_queue where fulfillment_job_id=p_job for update;
 if not found then raise exception 'posting_queue_not_found'; end if;
 if q.posting_status='posted' or j.inventory_posting_status='posted' then return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','idempotent_replay',true,'inventory_changed',false); end if;
 if j.fulfillment_status in('cancelled','shipped') or (j.fulfillment_status='blocked' and j.inventory_posting_status<>'failed') then raise exception 'fulfillment_job_not_postable'; end if;
 if j.source_type<>'customer_order' then raise exception 'source_type_requires_specialized_inventory_workflow'; end if;
 if q.posting_status not in('pending','failed','processing') then raise exception 'posting_queue_not_retryable'; end if;
 update public.mme_warehouse_inventory_posting_queue set posting_status='processing',attempt_count=attempt_count+1,last_attempt_at=now(),updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
 update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='processing',updated_at=now() where fulfillment_job_id=p_job;
 begin
  if not exists(select 1 from public.mme_warehouse_fulfillment_job_lines where fulfillment_job_id=p_job) then raise exception 'fulfillment_has_no_lines'; end if;
  for l in select fl.*,i.sku,i.track_serial,i.track_imei from public.mme_warehouse_fulfillment_job_lines fl join public.mme_inventory_items i on i.inventory_item_id=fl.inventory_item_id where fl.fulfillment_job_id=p_job order by fl.inventory_item_id,fl.source_location_id,fl.fulfillment_job_line_id loop
   select * into b from public.mme_inventory_stock_balances where inventory_item_id=l.inventory_item_id and location_id=l.source_location_id for update;
   if not found then raise exception 'inventory_balance_not_initialized_for_sku_%',l.sku; end if;
   before_qty:=b.quantity_on_hand;
   if before_qty-b.quantity_reserved<l.fulfilled_quantity then raise exception 'insufficient_available_stock_for_sku_%',l.sku; end if;
   if coalesce(l.track_serial,false) or coalesce(l.track_imei,false) then
    select count(*) into units from public.mme_warehouse_fulfillment_device_manifest m join public.mme_inventory_device_assets d on d.device_asset_id=m.device_asset_id where m.fulfillment_job_line_id=l.fulfillment_job_line_id and d.asset_status='reserved';
    if units<>l.fulfilled_quantity then raise exception 'serialized_manifest_quantity_mismatch_for_sku_%',l.sku; end if;
    for a in select d.* from public.mme_warehouse_fulfillment_device_manifest m join public.mme_inventory_device_assets d on d.device_asset_id=m.device_asset_id where m.fulfillment_job_line_id=l.fulfillment_job_line_id order by d.device_asset_id for update of d loop
     if a.asset_status<>'reserved' or a.location_id<>l.source_location_id then raise exception 'serialized_device_state_or_location_mismatch'; end if;
     update public.mme_inventory_device_assets set asset_status='sold',updated_at=now() where device_asset_id=a.device_asset_id;
     insert into public.mme_inventory_device_events(device_asset_id,event_type,from_status,to_status,source_reference,event_detail,actor_auth_user_id)
     values(a.device_asset_id,'sold','reserved','sold',j.source_reference,'Serialized device sold through fulfillment posting.',p_actor);
    end loop;
   end if;
   after_qty:=before_qty-l.fulfilled_quantity;
   update public.mme_inventory_stock_balances set quantity_on_hand=after_qty,version=version+1,updated_at=now() where stock_balance_id=b.stock_balance_id;
   insert into public.mme_inventory_reservations(fulfillment_job_id,inventory_item_id,location_id,quantity,reservation_status,idempotency_key,finalized_at,actor_auth_user_id)
   values(p_job,l.inventory_item_id,l.source_location_id,l.fulfilled_quantity,'consumed','fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,now(),p_actor);
   insert into public.mme_inventory_movements(movement_number,inventory_item_id,location_id,movement_type,quantity_delta,quantity_before,quantity_after,source_type,source_reference,fulfillment_job_id,idempotency_key,actor_auth_user_id)
   values('FUL-'||replace(gen_random_uuid()::text,'-',''),l.inventory_item_id,l.source_location_id,'fulfillment_sale',-l.fulfilled_quantity,before_qty,after_qty,j.source_type,j.source_reference,p_job,'fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,p_actor) returning movement_number into movement_ref;
   n:=n+1;total:=total+l.fulfilled_quantity;
  end loop;
  update public.mme_warehouse_inventory_posting_queue set posting_status='posted',posted_movement_reference='fulfillment:'||p_job::text,updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='posted',fulfillment_status='inventory_posted',inventory_posted_at=now(),failure_code=null,failure_detail=null,updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'inventory_posted',format('Atomically posted %s inventory movement lines totaling %s units.',n,total),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','movement_lines',n,'units_posted',total,'inventory_changed',true,'idempotent_replay',false);
 exception when others then
  update public.mme_warehouse_inventory_posting_queue set posting_status='failed',error_code=sqlstate,error_detail=left(sqlerrm,500),updated_at=now() where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='failed',fulfillment_status='blocked',failure_code=sqlstate,failure_detail=left(sqlerrm,500),updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'posting_failed',left(sqlerrm,500),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','failed','error_code',sqlstate,'error',left(sqlerrm,500),'inventory_changed',false);
 end;
end $$;
revoke all on function public.mme_inventory_register_device(uuid,uuid,text,text,text,text,text,numeric,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_attach_fulfillment_device(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_post_fulfillment_serialized(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_register_device(uuid,uuid,text,text,text,text,text,numeric,uuid) to service_role;
grant execute on function public.mme_inventory_attach_fulfillment_device(uuid,uuid,uuid) to service_role;
grant execute on function public.mme_inventory_post_fulfillment_serialized(uuid,uuid) to service_role;
do $$declare t text;begin foreach t in array array['mme_inventory_device_assets','mme_inventory_device_events','mme_warehouse_fulfillment_device_manifest'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
commit; or (select sum((substr(new.imei_2, length(new.imei_2)-g, 1)::integer * case when g%2=1 then 2 else 1 end / 10 + (substr(new.imei_2,length(new.imei_2)-g,1)::integer * case when g%2=1 then 2 else 1 end)%10) from generate_series(0,length(new.imei_2)-1) g)%10<>0) then raise exception 'invalid_imei_2'; end if;
 if new.imei_1 is not null and new.imei_2 is not null and new.imei_1=new.imei_2 then raise exception 'duplicate_dual_sim_imei'; end if;
 if exists(select 1 from public.mme_inventory_device_assets d where d.device_asset_id<>coalesce(new.device_asset_id,'00000000-0000-0000-0000-000000000000'::uuid) and ((new.imei_1 is not null and new.imei_1 in(d.imei_1,d.imei_2)) or (new.imei_2 is not null and new.imei_2 in(d.imei_1,d.imei_2)))) then raise exception 'imei_already_registered'; end if;
 return new;
end $;
drop trigger if exists mme_inventory_device_imei_validate on public.mme_inventory_device_assets;
create trigger mme_inventory_device_imei_validate before insert or update of imei_1,imei_2 on public.mme_inventory_device_assets for each row execute function public.mme_inventory_validate_device_identifiers();
create table if not exists public.mme_inventory_device_events(
 device_event_id uuid primary key default gen_random_uuid(),
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 event_type text not null check(event_type in('registered','condition_updated','location_changed','reserved','reservation_released','sold','returned','repair_started','repair_completed','blacklisted','unblacklisted','marked_missing','recovered','retired','warranty_updated')),
 from_status text,
 to_status text,
 from_location_id uuid references public.mme_inventory_locations(location_id) on delete restrict,
 to_location_id uuid references public.mme_inventory_locations(location_id) on delete restrict,
 source_reference text,
 event_detail text,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_inventory_device_events_asset_idx on public.mme_inventory_device_events(device_asset_id,created_at desc);
create table if not exists public.mme_warehouse_fulfillment_device_manifest(
 manifest_id uuid primary key default gen_random_uuid(),
 fulfillment_job_line_id uuid not null references public.mme_warehouse_fulfillment_job_lines(fulfillment_job_line_id) on delete restrict,
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 scanned_by_auth_user_id uuid not null,
 scanned_at timestamptz not null default now(),
 unique(fulfillment_job_line_id,device_asset_id),
 unique(device_asset_id)
);
create or replace function public.mme_inventory_register_device(p_item uuid,p_location uuid,p_serial text,p_imei1 text,p_imei2 text,p_grade text,p_acquisition_reference text,p_cost numeric,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.mme_inventory_items%rowtype; a public.mme_inventory_device_assets%rowtype; code text;
begin
 if p_actor is null or p_item is null or p_location is null then raise exception 'device_item_location_actor_required'; end if;
 select * into i from public.mme_inventory_items where inventory_item_id=p_item;
 if not found then raise exception 'inventory_item_not_found'; end if;
 if not coalesce(i.track_serial,false) and not coalesce(i.track_imei,false) then raise exception 'item_not_configured_for_device_tracking'; end if;
 if coalesce(i.track_serial,false) and nullif(trim(coalesce(p_serial,'')),'') is null then raise exception 'serial_number_required'; end if;
 if coalesce(i.track_imei,false) and nullif(trim(coalesce(p_imei1,'')),'') is null then raise exception 'imei_required'; end if;
 if p_imei1 is not null and p_imei1 !~ '^[0-9]{14,16}$' then raise exception 'invalid_imei_1'; end if;
 if p_imei2 is not null and p_imei2 !~ '^[0-9]{14,16}$' then raise exception 'invalid_imei_2'; end if;
 code:='MME-'||replace(gen_random_uuid()::text,'-','');
 insert into public.mme_inventory_device_assets(inventory_item_id,location_id,serial_number,imei_1,imei_2,condition_grade,acquisition_reference,cost_basis,barcode_value,registered_by_auth_user_id)
 values(p_item,p_location,nullif(trim(p_serial),''),nullif(trim(p_imei1),''),nullif(trim(p_imei2),''),coalesce(p_grade,'ungraded'),p_acquisition_reference,p_cost,code,p_actor) returning * into a;
 insert into public.mme_inventory_device_events(device_asset_id,event_type,to_status,to_location_id,event_detail,actor_auth_user_id)
 values(a.device_asset_id,'registered','available',p_location,'Device registered with unique serial/IMEI identifiers.',p_actor);
 return jsonb_build_object('device_asset_id',a.device_asset_id,'barcode_value',a.barcode_value,'asset_status',a.asset_status);
end $$;
create or replace function public.mme_inventory_attach_fulfillment_device(p_line uuid,p_device uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l public.mme_warehouse_fulfillment_job_lines%rowtype; a public.mme_inventory_device_assets%rowtype; j public.mme_warehouse_fulfillment_jobs%rowtype;
begin
 select * into l from public.mme_warehouse_fulfillment_job_lines where fulfillment_job_line_id=p_line for update;
 if not found then raise exception 'fulfillment_line_not_found'; end if;
 select * into j from public.mme_warehouse_fulfillment_jobs where fulfillment_job_id=l.fulfillment_job_id for update;
 if j.fulfillment_status in('shipped','cancelled') or j.inventory_posting_status='posted' then raise exception 'fulfillment_manifest_locked'; end if;
 select * into a from public.mme_inventory_device_assets where device_asset_id=p_device for update;
 if not found then raise exception 'device_asset_not_found'; end if;
 if a.inventory_item_id<>l.inventory_item_id or a.location_id<>l.source_location_id then raise exception 'device_item_or_location_mismatch'; end if;
 if a.asset_status not in('available','reserved') then raise exception 'device_not_available_for_fulfillment'; end if;
 insert into public.mme_warehouse_fulfillment_device_manifest(fulfillment_job_line_id,device_asset_id,scanned_by_auth_user_id) values(p_line,p_device,p_actor);
 insert into public.mme_inventory_device_events(device_asset_id,event_type,from_status,to_status,source_reference,event_detail,actor_auth_user_id)
 values(p_device,'reserved',a.asset_status,'reserved',j.source_reference,'Device scanned into fulfillment manifest.',p_actor);
 update public.mme_inventory_device_assets set asset_status='reserved',updated_at=now() where device_asset_id=p_device;
 return jsonb_build_object('manifest_id',(select manifest_id from public.mme_warehouse_fulfillment_device_manifest where fulfillment_job_line_id=p_line and device_asset_id=p_device),'device_asset_id',p_device,'asset_status','reserved');
end $$;
create or replace function public.mme_inventory_post_fulfillment_serialized(p_job uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare j public.mme_warehouse_fulfillment_jobs%rowtype; q public.mme_warehouse_inventory_posting_queue%rowtype; l record; b public.mme_inventory_stock_balances%rowtype; a public.mme_inventory_device_assets%rowtype; before_qty integer; after_qty integer; n integer:=0; total integer:=0; units integer; movement_ref text;
begin
 if p_job is null or p_actor is null then raise exception 'posting_job_and_actor_required'; end if;
 select * into j from public.mme_warehouse_fulfillment_jobs where fulfillment_job_id=p_job for update;
 if not found then raise exception 'fulfillment_job_not_found'; end if;
 select * into q from public.mme_warehouse_inventory_posting_queue where fulfillment_job_id=p_job for update;
 if not found then raise exception 'posting_queue_not_found'; end if;
 if q.posting_status='posted' or j.inventory_posting_status='posted' then return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','idempotent_replay',true,'inventory_changed',false); end if;
 if j.fulfillment_status in('cancelled','shipped') or (j.fulfillment_status='blocked' and j.inventory_posting_status<>'failed') then raise exception 'fulfillment_job_not_postable'; end if;
 if j.source_type<>'customer_order' then raise exception 'source_type_requires_specialized_inventory_workflow'; end if;
 if q.posting_status not in('pending','failed','processing') then raise exception 'posting_queue_not_retryable'; end if;
 update public.mme_warehouse_inventory_posting_queue set posting_status='processing',attempt_count=attempt_count+1,last_attempt_at=now(),updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
 update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='processing',updated_at=now() where fulfillment_job_id=p_job;
 begin
  if not exists(select 1 from public.mme_warehouse_fulfillment_job_lines where fulfillment_job_id=p_job) then raise exception 'fulfillment_has_no_lines'; end if;
  for l in select fl.*,i.sku,i.track_serial,i.track_imei from public.mme_warehouse_fulfillment_job_lines fl join public.mme_inventory_items i on i.inventory_item_id=fl.inventory_item_id where fl.fulfillment_job_id=p_job order by fl.inventory_item_id,fl.source_location_id,fl.fulfillment_job_line_id loop
   select * into b from public.mme_inventory_stock_balances where inventory_item_id=l.inventory_item_id and location_id=l.source_location_id for update;
   if not found then raise exception 'inventory_balance_not_initialized_for_sku_%',l.sku; end if;
   before_qty:=b.quantity_on_hand;
   if before_qty-b.quantity_reserved<l.fulfilled_quantity then raise exception 'insufficient_available_stock_for_sku_%',l.sku; end if;
   if coalesce(l.track_serial,false) or coalesce(l.track_imei,false) then
    select count(*) into units from public.mme_warehouse_fulfillment_device_manifest m join public.mme_inventory_device_assets d on d.device_asset_id=m.device_asset_id where m.fulfillment_job_line_id=l.fulfillment_job_line_id and d.asset_status='reserved';
    if units<>l.fulfilled_quantity then raise exception 'serialized_manifest_quantity_mismatch_for_sku_%',l.sku; end if;
    for a in select d.* from public.mme_warehouse_fulfillment_device_manifest m join public.mme_inventory_device_assets d on d.device_asset_id=m.device_asset_id where m.fulfillment_job_line_id=l.fulfillment_job_line_id order by d.device_asset_id for update of d loop
     if a.asset_status<>'reserved' or a.location_id<>l.source_location_id then raise exception 'serialized_device_state_or_location_mismatch'; end if;
     update public.mme_inventory_device_assets set asset_status='sold',updated_at=now() where device_asset_id=a.device_asset_id;
     insert into public.mme_inventory_device_events(device_asset_id,event_type,from_status,to_status,source_reference,event_detail,actor_auth_user_id)
     values(a.device_asset_id,'sold','reserved','sold',j.source_reference,'Serialized device sold through fulfillment posting.',p_actor);
    end loop;
   end if;
   after_qty:=before_qty-l.fulfilled_quantity;
   update public.mme_inventory_stock_balances set quantity_on_hand=after_qty,version=version+1,updated_at=now() where stock_balance_id=b.stock_balance_id;
   insert into public.mme_inventory_reservations(fulfillment_job_id,inventory_item_id,location_id,quantity,reservation_status,idempotency_key,finalized_at,actor_auth_user_id)
   values(p_job,l.inventory_item_id,l.source_location_id,l.fulfilled_quantity,'consumed','fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,now(),p_actor);
   insert into public.mme_inventory_movements(movement_number,inventory_item_id,location_id,movement_type,quantity_delta,quantity_before,quantity_after,source_type,source_reference,fulfillment_job_id,idempotency_key,actor_auth_user_id)
   values('FUL-'||replace(gen_random_uuid()::text,'-',''),l.inventory_item_id,l.source_location_id,'fulfillment_sale',-l.fulfilled_quantity,before_qty,after_qty,j.source_type,j.source_reference,p_job,'fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,p_actor) returning movement_number into movement_ref;
   n:=n+1;total:=total+l.fulfilled_quantity;
  end loop;
  update public.mme_warehouse_inventory_posting_queue set posting_status='posted',posted_movement_reference='fulfillment:'||p_job::text,updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='posted',fulfillment_status='inventory_posted',inventory_posted_at=now(),failure_code=null,failure_detail=null,updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'inventory_posted',format('Atomically posted %s inventory movement lines totaling %s units.',n,total),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','movement_lines',n,'units_posted',total,'inventory_changed',true,'idempotent_replay',false);
 exception when others then
  update public.mme_warehouse_inventory_posting_queue set posting_status='failed',error_code=sqlstate,error_detail=left(sqlerrm,500),updated_at=now() where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='failed',fulfillment_status='blocked',failure_code=sqlstate,failure_detail=left(sqlerrm,500),updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'posting_failed',left(sqlerrm,500),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','failed','error_code',sqlstate,'error',left(sqlerrm,500),'inventory_changed',false);
 end;
end $$;
revoke all on function public.mme_inventory_register_device(uuid,uuid,text,text,text,text,text,numeric,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_attach_fulfillment_device(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_post_fulfillment_serialized(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_register_device(uuid,uuid,text,text,text,text,text,numeric,uuid) to service_role;
grant execute on function public.mme_inventory_attach_fulfillment_device(uuid,uuid,uuid) to service_role;
grant execute on function public.mme_inventory_post_fulfillment_serialized(uuid,uuid) to service_role;
do $$declare t text;begin foreach t in array array['mme_inventory_device_assets','mme_inventory_device_events','mme_warehouse_fulfillment_device_manifest'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
commit;