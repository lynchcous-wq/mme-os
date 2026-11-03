-- Build 001: consolidated executive inventory snapshot, including serialized cost basis.
-- Service-only read API. Authorization and location scope are enforced by trusted MME backend.

create or replace function public.mme_get_inventory_executive_snapshot(
 p_location_id uuid default null
) returns table(
 location_id uuid,
 location_code text,
 location_name text,
 active_sku_count bigint,
 aggregate_on_hand bigint,
 aggregate_reserved bigint,
 aggregate_available bigint,
 aggregate_cost_value_cents bigint,
 aggregate_retail_value_cents bigint,
 serialized_in_stock bigint,
 serialized_reserved bigint,
 serialized_repair_quarantine bigint,
 serialized_cost_value_cents bigint,
 total_inventory_cost_value_cents bigint,
 reorder_alert_count bigint,
 unconfigured_reorder_count bigint,
 open_exception_count bigint,
 critical_exception_count bigint,
 open_receiving_sessions bigint,
 open_cycle_count_sessions bigint,
 pending_purchase_proposals bigint,
 zero_cost_aggregate_units bigint,
 below_cost_sku_count bigint,
 snapshot_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_location_id is not null and not exists(
  select 1 from public.mme_store_locations where id=p_location_id and active=true
 ) then raise exception 'Active inventory location not found' using errcode='P0002'; end if;

 return query
 with locations as (
  select l.id,l.location_code,l.display_name from public.mme_store_locations l
  where l.active=true and (p_location_id is null or l.id=p_location_id)
 ), aggregate_metrics as (
  select d.location_id,count(distinct d.product_id)::bigint sku_count,
   coalesce(sum(d.aggregate_on_hand),0)::bigint on_hand,
   coalesce(sum(d.aggregate_reserved),0)::bigint reserved,
   coalesce(sum(d.aggregate_available),0)::bigint available,
   coalesce(sum(d.aggregate_inventory_value_cents::numeric),0)::numeric cost_value,
   coalesce(sum((d.aggregate_on_hand::numeric*(p.unit_price_cents))),0)::numeric retail_value,
   coalesce(sum(d.aggregate_on_hand) filter(where d.average_unit_cost_cents=0),0)::bigint zero_cost,
   count(*) filter(where d.aggregate_on_hand>0 and p.unit_price_cents<d.average_unit_cost_cents)::bigint below_cost,
   count(*) filter(where d.reorder_status='reorder')::bigint reorder_count,
   count(*) filter(where d.reorder_status='not_configured')::bigint unconfigured_count
  from public.mme_inventory_dashboard_v d
  join public.mme_products p on p.id=d.product_id
  group by d.location_id
 ), serialized_metrics as (
  select u.location_id,
   count(*) filter(where u.unit_status='in_stock')::bigint in_stock,
   count(*) filter(where u.unit_status='reserved')::bigint reserved,
   count(*) filter(where u.unit_status in ('repair','quarantine'))::bigint repair_quarantine,
   coalesce(sum(c.landed_cost_cents) filter(where u.unit_status in ('in_stock','reserved','repair','quarantine')),0)::numeric cost_value
  from public.mme_serialized_units u
  left join public.mme_serialized_unit_costs c on c.unit_id=u.id
  group by u.location_id
 ), exceptions as (
  select e.location_id,count(*) filter(where e.status in ('open','acknowledged','investigating'))::bigint open_count,
   count(*) filter(where e.status in ('open','acknowledged','investigating') and e.severity='critical')::bigint critical_count
  from public.mme_inventory_exceptions e group by e.location_id
 ), receiving as (
  select s.location_id,count(*)::bigint session_count
  from public.mme_receiving_station_sessions s where s.session_status in ('open','submitted')
  group by s.location_id
 ), cycle_counts as (
  select s.location_id,count(*)::bigint session_count
  from public.mme_cycle_count_sessions s where s.status in ('open','review','approved')
  group by s.location_id
 ), proposals as (
  select p.location_id,count(*)::bigint proposal_count
  from public.mme_purchase_proposals p where p.status in ('draft','submitted')
  group by p.location_id
 )
 select l.id,l.location_code,l.display_name,
  coalesce(a.sku_count,0),coalesce(a.on_hand,0),coalesce(a.reserved,0),coalesce(a.available,0),
  case when coalesce(a.cost_value,0)>9000000000000000 then null else coalesce(a.cost_value,0)::bigint end,
  case when coalesce(a.retail_value,0)>9000000000000000 then null else coalesce(a.retail_value,0)::bigint end,
  coalesce(s.in_stock,0),coalesce(s.reserved,0),coalesce(s.repair_quarantine,0),
  case when coalesce(s.cost_value,0)>9000000000000000 then null else coalesce(s.cost_value,0)::bigint end,
  case when coalesce(a.cost_value,0)+coalesce(s.cost_value,0)>9000000000000000 then null
   else (coalesce(a.cost_value,0)+coalesce(s.cost_value,0))::bigint end,
  coalesce(a.reorder_count,0),coalesce(a.unconfigured_count,0),
  coalesce(e.open_count,0),coalesce(e.critical_count,0),
  coalesce(r.session_count,0),coalesce(cc.session_count,0),coalesce(pp.proposal_count,0),
  coalesce(a.zero_cost,0),coalesce(a.below_cost,0),now()
 from locations l
 left join aggregate_metrics a on a.location_id=l.id
 left join serialized_metrics s on s.location_id=l.id
 left join exceptions e on e.location_id=l.id
 left join receiving r on r.location_id=l.id
 left join cycle_counts cc on cc.location_id=l.id
 left join proposals pp on pp.location_id=l.id
 order by l.location_code;
end; $$;

revoke all on function public.mme_get_inventory_executive_snapshot(uuid) from public,anon,authenticated;
grant execute on function public.mme_get_inventory_executive_snapshot(uuid) to service_role;

comment on function public.mme_get_inventory_executive_snapshot(uuid) is
 'One-row-per-location executive inventory snapshot combining aggregate and serialized landed cost, reorder health, exceptions and work queues. Null monetary totals indicate overflow and must not be rendered as zero.';
