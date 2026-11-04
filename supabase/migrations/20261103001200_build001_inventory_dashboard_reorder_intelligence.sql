-- Build 001: inventory command dashboard and reorder intelligence.
-- Read access is restricted to trusted server services. Role checks and CEO approval
-- are enforced by the application service before invoking privileged routines.

create table public.mme_inventory_reorder_rules (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  minimum_available_quantity integer not null default 0 check (minimum_available_quantity>=0),
  target_available_quantity integer not null check (target_available_quantity>=1),
  lead_time_days integer not null default 7 check (lead_time_days between 0 and 365),
  preferred_supplier text,
  enabled boolean not null default true,
  updated_by_identity_id uuid not null,
  approved_by_identity_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id,location_id),
  check(target_available_quantity>=minimum_available_quantity)
);

create index mme_inventory_reorder_rules_enabled_idx
  on public.mme_inventory_reorder_rules(location_id,enabled);

alter table public.mme_inventory_reorder_rules enable row level security;
revoke all on public.mme_inventory_reorder_rules from anon,authenticated;
grant all on public.mme_inventory_reorder_rules to service_role;

-- Unified dashboard rows. Serialized devices are counted from the unit ledger;
-- aggregate inventory value is explicitly based on average unit cost only.
create or replace view public.mme_inventory_dashboard_v
with (security_invoker=true) as
select
  p.id as product_id,
  p.sku,
  p.title,
  p.category_key,
  p.condition_grade,
  p.serialized,
  l.id as location_id,
  l.location_code,
  l.display_name as location_name,
  coalesce(b.on_hand_quantity,0) as aggregate_on_hand,
  coalesce(b.reserved_quantity,0) as aggregate_reserved,
  coalesce(b.on_hand_quantity-b.reserved_quantity,0) as aggregate_available,
  coalesce(b.average_unit_cost_cents,0) as average_unit_cost_cents,
  coalesce(b.on_hand_quantity::bigint*b.average_unit_cost_cents,0) as aggregate_inventory_value_cents,
  coalesce(s.serialized_on_hand,0) as serialized_on_hand,
  coalesce(s.serialized_reserved,0) as serialized_reserved,
  coalesce(s.serialized_sold,0) as serialized_sold,
  coalesce(s.serialized_repair_quarantine,0) as serialized_repair_quarantine,
  coalesce(r.minimum_available_quantity,0) as minimum_available_quantity,
  coalesce(r.target_available_quantity,0) as target_available_quantity,
  coalesce(r.lead_time_days,7) as lead_time_days,
  r.preferred_supplier,
  coalesce(r.enabled,false) as reorder_enabled,
  case when r.enabled and coalesce(b.on_hand_quantity-b.reserved_quantity,0)<=r.minimum_available_quantity
       then greatest(r.target_available_quantity-coalesce(b.on_hand_quantity-b.reserved_quantity,0),0)
       else 0 end as suggested_reorder_quantity,
  case when r.enabled and coalesce(b.on_hand_quantity-b.reserved_quantity,0)<=r.minimum_available_quantity
       then 'reorder' when r.enabled then 'healthy' else 'not_configured' end as reorder_status,
  greatest(b.updated_at, s.last_updated_at, r.updated_at) as inventory_updated_at
from public.mme_products p
cross join public.mme_store_locations l
left join public.mme_inventory_balances b on b.product_id=p.id and b.location_id=l.id
left join lateral (
  select
    count(*) filter(where unit_status='in_stock')::integer as serialized_on_hand,
    count(*) filter(where unit_status='reserved')::integer as serialized_reserved,
    count(*) filter(where unit_status='sold')::integer as serialized_sold,
    count(*) filter(where unit_status in ('repair','quarantine'))::integer as serialized_repair_quarantine,
    max(updated_at) as last_updated_at
  from public.mme_serialized_units u
  where u.product_id=p.id and u.location_id=l.id
) s on true
left join public.mme_inventory_reorder_rules r on r.product_id=p.id and r.location_id=l.id
where p.active=true and l.active=true;

revoke all on public.mme_inventory_dashboard_v from public,anon,authenticated;
grant select on public.mme_inventory_dashboard_v to service_role;

create or replace function public.mme_get_inventory_dashboard(
  p_location_id uuid default null,
  p_search text default null,
  p_low_stock_only boolean default false,
  p_limit integer default 200,
  p_offset integer default 0
) returns table(
  product_id uuid,sku text,title text,category_key text,condition_grade text,serialized boolean,
  location_id uuid,location_code text,location_name text,
  aggregate_on_hand integer,aggregate_reserved integer,aggregate_available integer,
  average_unit_cost_cents bigint,aggregate_inventory_value_cents bigint,
  serialized_on_hand integer,serialized_reserved integer,serialized_sold integer,
  serialized_repair_quarantine integer,minimum_available_quantity integer,
  target_available_quantity integer,lead_time_days integer,preferred_supplier text,
  reorder_enabled boolean,suggested_reorder_quantity integer,reorder_status text,
  inventory_updated_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
  if p_limit is null or p_limit<1 or p_limit>500 or p_offset is null or p_offset<0
     or p_search is not null and length(p_search)>120 then
    raise exception 'Invalid inventory dashboard query' using errcode='22023';
  end if;
  return query
  select d.product_id,d.sku,d.title,d.category_key,d.condition_grade,d.serialized,
    d.location_id,d.location_code,d.location_name,
    d.aggregate_on_hand,d.aggregate_reserved,d.aggregate_available,
    d.average_unit_cost_cents,d.aggregate_inventory_value_cents,
    d.serialized_on_hand,d.serialized_reserved,d.serialized_sold,d.serialized_repair_quarantine,
    d.minimum_available_quantity,d.target_available_quantity,d.lead_time_days,d.preferred_supplier,
    d.reorder_enabled,d.suggested_reorder_quantity,d.reorder_status,d.inventory_updated_at
  from public.mme_inventory_dashboard_v d
  where (p_location_id is null or d.location_id=p_location_id)
    and (p_search is null or d.sku ilike '%'||btrim(p_search)||'%' or d.title ilike '%'||btrim(p_search)||'%')
    and (not p_low_stock_only or d.reorder_status='reorder')
  order by case d.reorder_status when 'reorder' then 0 when 'not_configured' then 1 else 2 end,
    d.title,d.location_name
  limit p_limit offset p_offset;
end; $$;

create or replace function public.mme_set_inventory_reorder_rule(
  p_product_id uuid,p_location_id uuid,p_minimum integer,p_target integer,
  p_lead_time_days integer,p_preferred_supplier text,p_enabled boolean,
  p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_serialized boolean;
begin
  if p_product_id is null or p_location_id is null or p_minimum is null or p_minimum<0
     or p_target is null or p_target<1 or p_target<p_minimum
     or p_lead_time_days is null or p_lead_time_days not between 0 and 365
     or p_actor_identity_id is null or p_enabled is null
     or p_preferred_supplier is not null and length(p_preferred_supplier)>160 then
    raise exception 'Invalid reorder rule' using errcode='22023';
  end if;
  select serialized into v_serialized from public.mme_products where id=p_product_id and active=true for update;
  if not found then raise exception 'Active product not found' using errcode='P0002'; end if;
  perform 1 from public.mme_store_locations where id=p_location_id and active=true;
  if not found then raise exception 'Active location not found' using errcode='P0002'; end if;

  insert into public.mme_inventory_reorder_rules(
    product_id,location_id,minimum_available_quantity,target_available_quantity,
    lead_time_days,preferred_supplier,enabled,updated_by_identity_id,approved_by_identity_id
  ) values (
    p_product_id,p_location_id,p_minimum,p_target,p_lead_time_days,p_preferred_supplier,
    p_enabled,p_actor_identity_id,p_approved_by_identity_id
  ) on conflict(product_id,location_id) do update set
    minimum_available_quantity=excluded.minimum_available_quantity,
    target_available_quantity=excluded.target_available_quantity,
    lead_time_days=excluded.lead_time_days,
    preferred_supplier=excluded.preferred_supplier,
    enabled=excluded.enabled,
    updated_by_identity_id=excluded.updated_by_identity_id,
    approved_by_identity_id=excluded.approved_by_identity_id,
    updated_at=now()
  returning id into v_id;
  return v_id;
end; $$;

revoke all on function public.mme_get_inventory_dashboard(uuid,text,boolean,integer,integer) from public,anon,authenticated;
revoke all on function public.mme_set_inventory_reorder_rule(uuid,uuid,integer,integer,integer,text,boolean,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_get_inventory_dashboard(uuid,text,boolean,integer,integer) to service_role;
grant execute on function public.mme_set_inventory_reorder_rule(uuid,uuid,integer,integer,integer,text,boolean,uuid,uuid) to service_role;

comment on table public.mme_inventory_reorder_rules is
  'Location-specific low-stock thresholds and replenishment targets, changed only through trusted approval-aware services.';
comment on view public.mme_inventory_dashboard_v is
  'Unified aggregate and serialized inventory metrics. Aggregate inventory value excludes serialized units.';
