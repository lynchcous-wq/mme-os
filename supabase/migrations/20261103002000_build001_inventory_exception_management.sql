-- Build 001: inventory exception intelligence and auditable management triage.
-- Trusted service evaluates signals and creates exceptions; UI reads through authorized API only.

create table public.mme_inventory_exception_rules (
 id uuid primary key default gen_random_uuid(),
 rule_key text not null unique,
 display_name text not null,
 description text,
 severity text not null default 'medium' check(severity in ('low','medium','high','critical')),
 enabled boolean not null default true,
 threshold_config jsonb not null default '{}'::jsonb check(jsonb_typeof(threshold_config)='object'),
 created_by_identity_id uuid not null,
 updated_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.mme_inventory_exceptions (
 id uuid primary key default gen_random_uuid(),
 exception_reference text not null unique,
 rule_id uuid references public.mme_inventory_exception_rules(id) on delete restrict,
 exception_type text not null check(exception_type in (
  'low_stock','unmatched_scan','receiving_variance','stocktake_variance',
  'inventory_adjustment','damage_report','quarantine','stale_inventory',
  'serialized_unit_mismatch','duplicate_identifier','manual_review'
 )),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','acknowledged','investigating','resolved','dismissed')),
 location_id uuid references public.mme_store_locations(id) on delete restrict,
 product_id uuid references public.mme_products(id) on delete restrict,
 source_type text,
 source_id uuid,
 deduplication_key text,
 summary text not null check(length(btrim(summary)) between 3 and 240),
 details jsonb not null default '{}'::jsonb check(jsonb_typeof(details)='object'),
 detected_at timestamptz not null default now(),
 acknowledged_by_identity_id uuid,
 acknowledged_at timestamptz,
 assigned_to_identity_id uuid,
 resolution_code text,
 resolution_note text,
 resolved_by_identity_id uuid,
 resolved_at timestamptz,
 created_by_identity_id uuid,
 updated_at timestamptz not null default now(),
 check ((status not in ('resolved','dismissed')) or (resolved_by_identity_id is not null and resolved_at is not null)),
 check ((status not in ('acknowledged','investigating','resolved','dismissed')) or (acknowledged_by_identity_id is not null and acknowledged_at is not null))
);

create unique index mme_inventory_exceptions_active_dedupe_idx
 on public.mme_inventory_exceptions(deduplication_key)
 where deduplication_key is not null and status in ('open','acknowledged','investigating');
create index mme_inventory_exceptions_queue_idx
 on public.mme_inventory_exceptions(status,severity,detected_at desc);
create index mme_inventory_exceptions_product_idx
 on public.mme_inventory_exceptions(product_id,detected_at desc) where product_id is not null;
create index mme_inventory_exceptions_location_idx
 on public.mme_inventory_exceptions(location_id,status,detected_at desc);

create table public.mme_inventory_exception_events (
 id uuid primary key default gen_random_uuid(),
 exception_id uuid not null references public.mme_inventory_exceptions(id) on delete restrict,
 event_type text not null check(event_type in ('created','deduplicated','acknowledged','assigned','investigating','resolved','dismissed','note_added','severity_changed')),
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 actor_identity_id uuid not null,
 created_at timestamptz not null default now()
);
create index mme_inventory_exception_events_history_idx
 on public.mme_inventory_exception_events(exception_id,created_at);

alter table public.mme_inventory_exception_rules enable row level security;
alter table public.mme_inventory_exceptions enable row level security;
alter table public.mme_inventory_exception_events enable row level security;
revoke all on public.mme_inventory_exception_rules,public.mme_inventory_exceptions,public.mme_inventory_exception_events from anon,authenticated;
grant all on public.mme_inventory_exception_rules,public.mme_inventory_exceptions,public.mme_inventory_exception_events to service_role;

create or replace function public.mme_raise_inventory_exception(
 p_exception_reference text,p_rule_key text,p_exception_type text,p_severity text,
 p_location_id uuid,p_product_id uuid,p_source_type text,p_source_id uuid,
 p_deduplication_key text,p_summary text,p_details jsonb,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_rule_id uuid; v_exception_id uuid; v_existing_status text;
begin
 if p_exception_reference is null or length(btrim(p_exception_reference)) not between 3 and 80
  or p_exception_type not in ('low_stock','unmatched_scan','receiving_variance','stocktake_variance','inventory_adjustment','damage_report','quarantine','stale_inventory','serialized_unit_mismatch','duplicate_identifier','manual_review')
  or p_severity not in ('low','medium','high','critical')
  or p_summary is null or length(btrim(p_summary)) not between 3 and 240
  or p_details is null or jsonb_typeof(p_details)<>'object'
  or p_actor_identity_id is null
  or p_source_type is not null and length(p_source_type)>80
  or p_deduplication_key is not null and length(p_deduplication_key)>240 then
  raise exception 'Invalid inventory exception' using errcode='22023';
 end if;
 if p_location_id is not null and not exists(select 1 from public.mme_store_locations where id=p_location_id) then
  raise exception 'Unknown inventory location' using errcode='P0002';
 end if;
 if p_product_id is not null and not exists(select 1 from public.mme_products where id=p_product_id) then
  raise exception 'Unknown inventory product' using errcode='P0002';
 end if;
 if p_rule_key is not null then
  select id into v_rule_id from public.mme_inventory_exception_rules where rule_key=p_rule_key and enabled=true;
  if not found then raise exception 'Exception rule is missing or disabled' using errcode='P0002'; end if;
 end if;
 if p_deduplication_key is not null then
  select id,status into v_exception_id,v_existing_status from public.mme_inventory_exceptions
   where deduplication_key=p_deduplication_key and status in ('open','acknowledged','investigating')
   for update;
  if found then
   update public.mme_inventory_exceptions set
    severity=case when array_position(array['low','medium','high','critical'],p_severity)>
                         array_position(array['low','medium','high','critical'],severity) then p_severity else severity end,
    details=p_details,updated_at=now()
   where id=v_exception_id;
   insert into public.mme_inventory_exception_events(exception_id,event_type,event_data,actor_identity_id)
   values(v_exception_id,'deduplicated',jsonb_build_object('latest_summary',btrim(p_summary),'source_type',p_source_type,'source_id',p_source_id),p_actor_identity_id);
   return v_exception_id;
  end if;
 end if;
 insert into public.mme_inventory_exceptions(
  exception_reference,rule_id,exception_type,severity,location_id,product_id,
  source_type,source_id,deduplication_key,summary,details,created_by_identity_id
 ) values (
  upper(btrim(p_exception_reference)),v_rule_id,p_exception_type,p_severity,p_location_id,p_product_id,
  p_source_type,p_source_id,p_deduplication_key,btrim(p_summary),p_details,p_actor_identity_id
 ) returning id into v_exception_id;
 insert into public.mme_inventory_exception_events(exception_id,event_type,event_data,actor_identity_id)
 values(v_exception_id,'created',jsonb_build_object('type',p_exception_type,'severity',p_severity,'source_type',p_source_type,'source_id',p_source_id),p_actor_identity_id);
 return v_exception_id;
end; $$;

create or replace function public.mme_update_inventory_exception(
 p_exception_id uuid,p_action text,p_actor_identity_id uuid,p_assigned_to_identity_id uuid,
 p_resolution_code text,p_resolution_note text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_status text; v_event text;
begin
 if p_exception_id is null or p_action not in ('acknowledge','investigate','assign','resolve','dismiss','reopen')
  or p_actor_identity_id is null then
  raise exception 'Invalid inventory exception action' using errcode='22023';
 end if;
 select status into v_status from public.mme_inventory_exceptions where id=p_exception_id for update;
 if not found then return false; end if;
 if p_action='acknowledge' and v_status='open' then
  update public.mme_inventory_exceptions set status='acknowledged',acknowledged_by_identity_id=p_actor_identity_id,acknowledged_at=now(),updated_at=now() where id=p_exception_id;
  v_event:='acknowledged';
 elsif p_action='investigate' and v_status in ('open','acknowledged') then
  update public.mme_inventory_exceptions set status='investigating',
   acknowledged_by_identity_id=coalesce(acknowledged_by_identity_id,p_actor_identity_id),
   acknowledged_at=coalesce(acknowledged_at,now()),updated_at=now() where id=p_exception_id;
  v_event:='investigating';
 elsif p_action='assign' and v_status in ('open','acknowledged','investigating') and p_assigned_to_identity_id is not null then
  update public.mme_inventory_exceptions set assigned_to_identity_id=p_assigned_to_identity_id,updated_at=now() where id=p_exception_id;
  v_event:='assigned';
 elsif p_action in ('resolve','dismiss') and v_status in ('open','acknowledged','investigating')
  and p_resolution_code is not null and length(btrim(p_resolution_code)) between 2 and 80
  and p_resolution_note is not null and length(btrim(p_resolution_note)) between 3 and 1000 then
  update public.mme_inventory_exceptions set status=case when p_action='resolve' then 'resolved' else 'dismissed' end,
   acknowledged_by_identity_id=coalesce(acknowledged_by_identity_id,p_actor_identity_id),
   acknowledged_at=coalesce(acknowledged_at,now()),
   resolution_code=btrim(p_resolution_code),resolution_note=btrim(p_resolution_note),
   resolved_by_identity_id=p_actor_identity_id,resolved_at=now(),updated_at=now()
   where id=p_exception_id;
  v_event:=case when p_action='resolve' then 'resolved' else 'dismissed' end;
 elsif p_action='reopen' and v_status in ('resolved','dismissed') then
  update public.mme_inventory_exceptions set status='open',resolution_code=null,resolution_note=null,
   resolved_by_identity_id=null,resolved_at=null,updated_at=now() where id=p_exception_id;
  v_event:='created';
 else
  return false;
 end if;
 insert into public.mme_inventory_exception_events(exception_id,event_type,event_data,actor_identity_id)
 values(p_exception_id,v_event,jsonb_build_object('action',p_action,'assigned_to',p_assigned_to_identity_id,
  'resolution_code',p_resolution_code,'resolution_note',p_resolution_note),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_get_inventory_exception_queue(
 p_location_id uuid default null,p_status text default null,p_severity text default null,
 p_exception_type text default null,p_limit integer default 100,p_offset integer default 0
) returns table(
 exception_id uuid,exception_reference text,exception_type text,severity text,status text,
 location_id uuid,product_id uuid,sku text,product_title text,source_type text,source_id uuid,
 summary text,details jsonb,detected_at timestamptz,assigned_to_identity_id uuid,
 acknowledged_by_identity_id uuid,resolution_code text,resolved_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_limit is null or p_limit<1 or p_limit>500 or p_offset is null or p_offset<0
  or p_status is not null and p_status not in ('open','acknowledged','investigating','resolved','dismissed')
  or p_severity is not null and p_severity not in ('low','medium','high','critical')
  or p_exception_type is not null and p_exception_type not in ('low_stock','unmatched_scan','receiving_variance','stocktake_variance','inventory_adjustment','damage_report','quarantine','stale_inventory','serialized_unit_mismatch','duplicate_identifier','manual_review') then
  raise exception 'Invalid exception queue filters' using errcode='22023';
 end if;
 return query
 select e.id,e.exception_reference,e.exception_type,e.severity,e.status,e.location_id,e.product_id,
  p.sku,p.title,e.source_type,e.source_id,e.summary,e.details,e.detected_at,e.assigned_to_identity_id,
  e.acknowledged_by_identity_id,e.resolution_code,e.resolved_at
 from public.mme_inventory_exceptions e left join public.mme_products p on p.id=e.product_id
 where (p_location_id is null or e.location_id=p_location_id)
  and (p_status is null or e.status=p_status)
  and (p_severity is null or e.severity=p_severity)
  and (p_exception_type is null or e.exception_type=p_exception_type)
 order by case e.status when 'open' then 0 when 'acknowledged' then 1 when 'investigating' then 2 else 3 end,
  case e.severity when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end,e.detected_at desc
 limit p_limit offset p_offset;
end; $$;

revoke all on function public.mme_raise_inventory_exception(text,text,text,text,uuid,uuid,text,uuid,text,text,jsonb,uuid) from public,anon,authenticated;
revoke all on function public.mme_update_inventory_exception(uuid,text,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_get_inventory_exception_queue(uuid,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.mme_raise_inventory_exception(text,text,text,text,uuid,uuid,text,uuid,text,text,jsonb,uuid) to service_role;
grant execute on function public.mme_update_inventory_exception(uuid,text,uuid,uuid,text,text) to service_role;
grant execute on function public.mme_get_inventory_exception_queue(uuid,text,text,text,integer,integer) to service_role;

comment on table public.mme_inventory_exceptions is 'Auditable inventory anomaly queue; event detection and role authorization are performed by trusted MME services.';
