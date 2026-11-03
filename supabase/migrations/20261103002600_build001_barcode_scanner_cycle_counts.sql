-- Build 001: scanner lookup, serialized-unit label binding, and auditable cycle counts.
-- Scanner requests are executed by a trusted server after authenticating the employee
-- and checking location/role permissions. This migration does not expose browser credentials.

alter table public.mme_label_print_job_items
 add column serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
 add column serial_number_snapshot text,
 add column imei_last4_snapshot text;
create unique index mme_label_job_items_serial_unit_unique
 on public.mme_label_print_job_items(job_id,serialized_unit_id)
 where serialized_unit_id is not null;

create table public.mme_inventory_scan_events (
 id uuid primary key default gen_random_uuid(),
 scan_value text not null check(length(btrim(scan_value)) between 1 and 160),
 scan_type text not null check(scan_type in ('sku','barcode','serial','imei','unknown')),
 result_type text not null check(result_type in ('aggregate_product','serialized_unit','not_found','ambiguous')),
 product_id uuid references public.mme_products(id) on delete restrict,
 serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
 location_id uuid references public.mme_store_locations(id) on delete restrict,
 actor_identity_id uuid not null,
 device_reference text,
 created_at timestamptz not null default now(),
 check((result_type='aggregate_product' and product_id is not null and serialized_unit_id is null)
  or (result_type='serialized_unit' and product_id is not null and serialized_unit_id is not null)
  or (result_type in ('not_found','ambiguous') and product_id is null and serialized_unit_id is null))
);
create index mme_inventory_scan_events_recent_idx on public.mme_inventory_scan_events(actor_identity_id,created_at desc);
create index mme_inventory_scan_events_product_idx on public.mme_inventory_scan_events(product_id,created_at desc) where product_id is not null;
alter table public.mme_inventory_scan_events enable row level security;
revoke all on public.mme_inventory_scan_events from public,anon,authenticated;
grant all on public.mme_inventory_scan_events to service_role;

create table public.mme_cycle_count_sessions (
 id uuid primary key default gen_random_uuid(),
 count_reference text not null unique,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 status text not null default 'open' check(status in ('open','review','approved','posted','cancelled')),
 count_scope text not null default 'all' check(count_scope in ('all','selected_products','serialized_only','aggregate_only')),
 opened_by_identity_id uuid not null,
 reviewed_by_identity_id uuid,
 approved_by_identity_id uuid,
 posted_by_identity_id uuid,
 opened_at timestamptz not null default now(),
 reviewed_at timestamptz,
 approved_at timestamptz,
 posted_at timestamptz,
 notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(status not in ('approved','posted') or (approved_by_identity_id is not null and approved_at is not null)),
 check(status<>'posted' or (posted_by_identity_id is not null and posted_at is not null))
);
create table public.mme_cycle_count_lines (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.mme_cycle_count_sessions(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
 expected_quantity integer not null check(expected_quantity>=0),
 counted_quantity integer not null default 0 check(counted_quantity>=0),
 scan_count integer not null default 0 check(scan_count>=0),
 variance_quantity integer generated always as (counted_quantity-expected_quantity) stored,
 status text not null default 'counting' check(status in ('counting','counted','exception','approved','posted')),
 last_scanned_by_identity_id uuid,
 last_scanned_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((serialized_unit_id is null) or (expected_quantity<=1 and counted_quantity<=1)),
 unique(session_id,product_id,serialized_unit_id)
);
create index mme_cycle_count_lines_session_idx on public.mme_cycle_count_lines(session_id,status);
create table public.mme_cycle_count_events (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.mme_cycle_count_sessions(id) on delete restrict,
 line_id uuid references public.mme_cycle_count_lines(id) on delete restrict,
 event_type text not null check(event_type in ('count_opened','item_scanned','line_adjusted','count_submitted','count_approved','count_posted','count_cancelled')),
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 actor_identity_id uuid not null,
 created_at timestamptz not null default now()
);
create index mme_cycle_count_events_history_idx on public.mme_cycle_count_events(session_id,created_at);
alter table public.mme_cycle_count_sessions enable row level security;
alter table public.mme_cycle_count_lines enable row level security;
alter table public.mme_cycle_count_events enable row level security;
revoke all on public.mme_cycle_count_sessions,public.mme_cycle_count_lines,public.mme_cycle_count_events from public,anon,authenticated;
grant all on public.mme_cycle_count_sessions,public.mme_cycle_count_lines,public.mme_cycle_count_events to service_role;

create or replace function public.mme_resolve_inventory_scan(
 p_scan_value text,p_location_id uuid,p_actor_identity_id uuid,p_device_reference text default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_product public.mme_products%rowtype; v_unit public.mme_serialized_units%rowtype;
 v_matches integer:=0; v_scan_type text:='unknown'; v_result text:='not_found'; v_location uuid;
begin
 if p_scan_value is null or length(btrim(p_scan_value)) not between 1 and 160 or
  p_scan_value<>btrim(p_scan_value) or p_actor_identity_id is null then
  raise exception 'Invalid scanner input' using errcode='22023';
 end if;
 if p_location_id is not null then
  perform 1 from public.mme_store_locations where id=p_location_id and active=true;
  if not found then raise exception 'Active scan location not found' using errcode='P0002'; end if;
 end if;
 select count(*) into v_matches from public.mme_serialized_units u
 where u.serial_number=p_scan_value or u.imei=p_scan_value;
 if v_matches=1 then
  select * into v_unit from public.mme_serialized_units u
  where u.serial_number=p_scan_value or u.imei=p_scan_value limit 1;
  select * into v_product from public.mme_products where id=v_unit.product_id;
  v_scan_type:=case when v_unit.imei=p_scan_value then 'imei' else 'serial' end;
  v_result:='serialized_unit'; v_location:=v_unit.location_id;
 elsif v_matches>1 then
  v_scan_type:='serial';v_result:='ambiguous';
 else
  select count(*) into v_matches from public.mme_products p
   where p.active=true and (p.sku=p_scan_value or ('MME:'||p.sku)=p_scan_value);
  if v_matches=1 then
   select * into v_product from public.mme_products p
    where p.active=true and (p.sku=p_scan_value or ('MME:'||p.sku)=p_scan_value) limit 1;
   v_scan_type:=case when p_scan_value like 'MME:%' then 'barcode' else 'sku' end;
   v_result:='aggregate_product'; v_location:=p_location_id;
  elsif v_matches>1 then
   v_scan_type:='barcode';v_result:='ambiguous';
  end if;
 end if;
 insert into public.mme_inventory_scan_events(scan_value,scan_type,result_type,product_id,
  serialized_unit_id,location_id,actor_identity_id,device_reference)
 values(p_scan_value,v_scan_type,v_result,
  case when v_result in ('aggregate_product','serialized_unit') then v_product.id end,
  case when v_result='serialized_unit' then v_unit.id end,
  case when v_result='serialized_unit' then v_unit.location_id else p_location_id end,
  p_actor_identity_id,left(p_device_reference,100));
 return jsonb_build_object('result',v_result,'scan_type',v_scan_type,
  'product_id',case when v_result in ('aggregate_product','serialized_unit') then v_product.id end,
  'product_title',case when v_result in ('aggregate_product','serialized_unit') then v_product.title end,
  'sku',case when v_result in ('aggregate_product','serialized_unit') then v_product.sku end,
  'serialized_unit_id',case when v_result='serialized_unit' then v_unit.id end,
  'serial_number',case when v_result='serialized_unit' then v_unit.serial_number end,
  'imei_last4',case when v_result='serialized_unit' and v_unit.imei is not null then right(v_unit.imei,4) end,
  'unit_status',case when v_result='serialized_unit' then v_unit.unit_status end,
  'location_id',case when v_result in ('aggregate_product','serialized_unit') then v_location end);
end; $$;

create or replace function public.mme_open_cycle_count(
 p_count_reference text,p_location_id uuid,p_scope text,p_actor_identity_id uuid,p_product_ids uuid[] default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_session uuid; v_product record;
begin
 if p_count_reference is null or length(btrim(p_count_reference)) not between 3 and 80
  or p_location_id is null or p_actor_identity_id is null
  or p_scope not in ('all','selected_products','serialized_only','aggregate_only')
  or p_scope='selected_products' and coalesce(array_length(p_product_ids,1),0)=0 then
  raise exception 'Invalid cycle count request' using errcode='22023';
 end if;
 perform 1 from public.mme_store_locations where id=p_location_id and active=true;
 if not found then raise exception 'Active count location not found' using errcode='P0002'; end if;
 insert into public.mme_cycle_count_sessions(count_reference,location_id,count_scope,opened_by_identity_id)
 values(upper(btrim(p_count_reference)),p_location_id,p_scope,p_actor_identity_id) returning id into v_session;
 for v_product in
  select p.id,p.serialized,coalesce(b.on_hand_quantity,0) as qty
  from public.mme_products p left join public.mme_inventory_balances b
   on b.product_id=p.id and b.location_id=p_location_id
  where p.active=true and
   (p_scope<>'selected_products' or p.id=any(p_product_ids)) and
   (p_scope<>'serialized_only' or p.serialized) and
   (p_scope<>'aggregate_only' or not p.serialized)
  order by p.sku
 loop
  if v_product.serialized then
   insert into public.mme_cycle_count_lines(session_id,product_id,serialized_unit_id,expected_quantity,counted_quantity,status)
   select v_session,v_product.id,u.id,1,0,'counting'
   from public.mme_serialized_units u where u.product_id=v_product.id
    and u.location_id=p_location_id and u.unit_status in ('in_stock','reserved','repair','quarantine');
  else
   insert into public.mme_cycle_count_lines(session_id,product_id,expected_quantity,counted_quantity,status)
   values(v_session,v_product.id,v_product.qty,0,'counting');
  end if;
 end loop;
 insert into public.mme_cycle_count_events(session_id,event_type,event_data,actor_identity_id)
 values(v_session,'count_opened',jsonb_build_object('location_id',p_location_id,'scope',p_scope),p_actor_identity_id);
 return v_session;
end; $$;

create or replace function public.mme_record_cycle_count_scan(
 p_session_id uuid,p_scan_value text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_session public.mme_cycle_count_sessions%rowtype; v_scan jsonb; v_line uuid;
 v_product uuid; v_unit uuid; v_count integer;
begin
 if p_session_id is null or p_scan_value is null or p_actor_identity_id is null then
  raise exception 'Invalid cycle count scan' using errcode='22023';
 end if;
 select * into v_session from public.mme_cycle_count_sessions where id=p_session_id for update;
 if not found or v_session.status<>'open' then raise exception 'Cycle count is not open' using errcode='23514'; end if;
 v_scan:=public.mme_resolve_inventory_scan(p_scan_value,v_session.location_id,p_actor_identity_id,'cycle-count');
 if v_scan->>'result' not in ('aggregate_product','serialized_unit') then
  raise exception 'Scan did not resolve to an inventory item' using errcode='P0002';
 end if;
 v_product:=(v_scan->>'product_id')::uuid;
 v_unit:=case when v_scan->>'serialized_unit_id' is not null then (v_scan->>'serialized_unit_id')::uuid end;
 if v_scan->>'location_id' is distinct from v_session.location_id::text then
  raise exception 'Scanned serialized unit is assigned to another location' using errcode='23514';
 end if;
 if v_unit is not null then
  update public.mme_cycle_count_lines set counted_quantity=1,scan_count=scan_count+1,
   status='counted',last_scanned_by_identity_id=p_actor_identity_id,last_scanned_at=now(),updated_at=now()
  where session_id=p_session_id and product_id=v_product and serialized_unit_id=v_unit returning id into v_line;
 else
  update public.mme_cycle_count_lines set counted_quantity=counted_quantity+1,scan_count=scan_count+1,
   status='counted',last_scanned_by_identity_id=p_actor_identity_id,last_scanned_at=now(),updated_at=now()
  where session_id=p_session_id and product_id=v_product and serialized_unit_id is null returning id into v_line;
 end if;
 if v_line is null then raise exception 'Item is not included in this cycle count' using errcode='P0002'; end if;
 select counted_quantity into v_count from public.mme_cycle_count_lines where id=v_line;
 insert into public.mme_cycle_count_events(session_id,line_id,event_type,event_data,actor_identity_id)
 values(p_session_id,v_line,'item_scanned',jsonb_build_object('scan_value',p_scan_value,'counted_quantity',v_count),p_actor_identity_id);
 return v_line;
end; $$;

create or replace function public.mme_submit_cycle_count(
 p_session_id uuid,p_actor_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if p_session_id is null or p_actor_identity_id is null then raise exception 'Invalid cycle count submission' using errcode='22023'; end if;
 update public.mme_cycle_count_sessions set status='review',reviewed_by_identity_id=p_actor_identity_id,
  reviewed_at=now(),updated_at=now() where id=p_session_id and status='open';
 if not found then return false; end if;
 insert into public.mme_cycle_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,'count_submitted','{}'::jsonb,p_actor_identity_id);
 return true;
end; $$;

revoke all on function public.mme_resolve_inventory_scan(text,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_open_cycle_count(text,uuid,text,uuid,uuid[]) from public,anon,authenticated;
revoke all on function public.mme_record_cycle_count_scan(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_submit_cycle_count(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_resolve_inventory_scan(text,uuid,uuid,text) to service_role;
grant execute on function public.mme_open_cycle_count(text,uuid,text,uuid,uuid[]) to service_role;
grant execute on function public.mme_record_cycle_count_scan(uuid,text,uuid) to service_role;
grant execute on function public.mme_submit_cycle_count(uuid,uuid) to service_role;

comment on table public.mme_inventory_scan_events is 'Auditable SKU, barcode, serial and IMEI scanner lookups.';
comment on table public.mme_cycle_count_sessions is 'Location-scoped physical inventory counts with review before posting.';
comment on table public.mme_cycle_count_lines is 'Expected versus scanned counts, including one row per serialized device.';
