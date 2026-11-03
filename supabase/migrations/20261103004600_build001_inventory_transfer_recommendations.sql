-- Build 001: recommend internal stock transfers before external replenishment.
-- Recommendations are advisory only; approved requests still use the existing two-person workflow.
create or replace function public.mme_get_inventory_transfer_recommendations(
 p_product_id uuid default null,
 p_destination_location_id uuid default null,
 p_limit integer default 100,
 p_offset integer default 0
) returns table(
 product_id uuid,sku text,product_title text,
 source_location_id uuid,source_location_name text,
 destination_location_id uuid,destination_location_name text,
 source_available_quantity integer,source_target_quantity integer,
 destination_available_quantity integer,destination_net_replenishment_need integer,
 recommended_transfer_quantity integer,
 average_unit_cost_cents bigint,estimated_transfer_value_cents bigint,
 destination_average_daily_units numeric,destination_days_of_stock numeric,
 destination_forecast_confidence text,
 recommendation_reason text
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_limit is null or p_limit<1 or p_limit>500 or p_offset is null or p_offset<0 then
  raise exception 'Invalid transfer recommendation query' using errcode='22023';
 end if;
 return query
 with inbound as (
  select product_id,location_id,inbound_open_quantity
  from public.mme_inventory_inbound_commitments_v
 ), forecasts as (
  select f.product_id,f.location_id,f.suggested_purchase_quantity,
   f.average_daily_units,f.days_of_stock,f.forecast_confidence
  from public.mme_get_inventory_forecast(null,p_product_id,false,500,0) f
 ), candidates as (
  select d.product_id,d.sku,d.title,
   s.location_id as source_id,s.location_name as source_name,
   d.location_id as dest_id,d.location_name as dest_name,
   s.aggregate_available as source_available,
   s.target_available_quantity as source_target,
   d.aggregate_available as dest_available,
   greatest(coalesce(f.suggested_purchase_quantity,0)-coalesce(i.inbound_open_quantity,0),0)::integer as net_need,
   s.average_unit_cost_cents as unit_cost,
   coalesce(f.average_daily_units,0) as daily_units,
   f.days_of_stock,f.forecast_confidence,
   greatest(s.aggregate_available-s.target_available_quantity,0)::integer as donor_surplus
  from public.mme_inventory_dashboard_v d
  join public.mme_inventory_dashboard_v s
   on s.product_id=d.product_id and s.location_id<>d.location_id
  join public.mme_products p on p.id=d.product_id and p.active=true and p.serialized=false
  left join forecasts f on f.product_id=d.product_id and f.location_id=d.location_id
  left join inbound i on i.product_id=d.product_id and i.location_id=d.location_id
  where d.aggregate_available>0
   and s.aggregate_available>s.target_available_quantity
   and (p_product_id is null or d.product_id=p_product_id)
   and (p_destination_location_id is null or d.location_id=p_destination_location_id)
 )
 select c.product_id,c.sku,c.title,c.source_id,c.source_name,c.dest_id,c.dest_name,
  c.source_available,c.source_target,c.dest_available,c.net_need,
  least(c.donor_surplus,c.net_need)::integer,
  c.unit_cost,(least(c.donor_surplus,c.net_need)::bigint*c.unit_cost)::bigint,
  c.daily_units,c.days_of_stock,c.forecast_confidence,
  'Source location has stock above its target; destination has forecast need remaining after committed inbound purchase orders'
 from candidates c
 where c.donor_surplus>0 and c.net_need>0
 order by (least(c.donor_surplus,c.net_need)::bigint*c.unit_cost) desc,
  c.net_need desc,c.sku,c.source_name,c.dest_name
 limit p_limit offset p_offset;
end; $$;

revoke all on function public.mme_get_inventory_transfer_recommendations(uuid,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.mme_get_inventory_transfer_recommendations(uuid,uuid,integer,integer) to service_role;
comment on function public.mme_get_inventory_transfer_recommendations(uuid,uuid,integer,integer) is
 'Advisory aggregate-stock transfer candidates: source surplus above configured target, destination forecast need net of committed inbound POs. Does not move stock or create approvals.';
