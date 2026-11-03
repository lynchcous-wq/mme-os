-- Build 001: paid aggregate-product sales velocity and current stock cover by location.
create or replace view public.mme_inventory_sales_velocity_v
with (security_invoker=true) as
with sales as (
 select ol.product_id,ol.location_id,
  sum(ol.quantity) filter(where ol.created_at>=now()-interval '30 days')::bigint as units_sold_30d,
  sum(ol.quantity) filter(where ol.created_at>=now()-interval '60 days')::bigint as units_sold_60d,
  sum(ol.quantity) filter(where ol.created_at>=now()-interval '90 days')::bigint as units_sold_90d,
  sum(ol.line_total_cents::numeric) filter(where ol.created_at>=now()-interval '30 days')::numeric as revenue_30d_cents,
  sum(ol.line_total_cents::numeric) filter(where ol.created_at>=now()-interval '60 days')::numeric as revenue_60d_cents,
  sum(ol.quantity::numeric*ol.cost_basis_unit_cents)
   filter(where ol.created_at>=now()-interval '30 days' and ol.cost_basis_status='captured')::numeric as cogs_30d_cents,
  sum(ol.quantity) filter(where ol.created_at>=now()-interval '30 days' and ol.cost_basis_status='missing')::bigint as units_missing_cost_30d
 from public.mme_order_lines ol
 join public.mme_orders o on o.id=ol.order_id
 where o.status='paid' and ol.serialized_unit_id is null
  and ol.created_at>=now()-interval '90 days'
 group by ol.product_id,ol.location_id
)
select p.id as product_id,p.sku,p.title,p.category_key,p.condition_grade,
 l.id as location_id,l.location_code,
 b.on_hand_quantity,b.reserved_quantity,(b.on_hand_quantity-b.reserved_quantity) as available_quantity,
 coalesce(s.units_sold_30d,0)::bigint as units_sold_30d,
 coalesce(s.units_sold_60d,0)::bigint as units_sold_60d,
 coalesce(s.units_sold_90d,0)::bigint as units_sold_90d,
 coalesce(s.revenue_30d_cents,0)::numeric as revenue_30d_cents,
 coalesce(s.revenue_60d_cents,0)::numeric as revenue_60d_cents,
 s.cogs_30d_cents,
 coalesce(s.units_missing_cost_30d,0)::bigint as units_missing_cost_30d,
 round(coalesce(s.units_sold_30d,0)::numeric/30.0,3) as average_daily_units_30d,
 case when coalesce(s.units_sold_30d,0)=0 then null
  else round((b.on_hand_quantity-b.reserved_quantity)::numeric/(s.units_sold_30d::numeric/30.0),1) end as days_of_available_stock_at_30d_velocity,
 case when coalesce(s.units_sold_60d,0)=0 then null
  else round((s.units_sold_30d::numeric*2/s.units_sold_60d::numeric)*100,1) end as recent_30d_vs_prior_60d_run_rate_percent,
 now() as calculated_at
from public.mme_inventory_balances b
join public.mme_products p on p.id=b.product_id and p.active=true and p.serialized=false
join public.mme_store_locations l on l.id=b.location_id and l.active=true
left join sales s on s.product_id=p.id and s.location_id=l.id;

revoke all on public.mme_inventory_sales_velocity_v from public,anon,authenticated;
grant select on public.mme_inventory_sales_velocity_v to service_role;
comment on view public.mme_inventory_sales_velocity_v is
 'Paid aggregate-product sales velocity for rolling 30/60/90-day windows, joined to current available stock. Uses order-line creation time as the sales-window timestamp; excludes serialized units. Days cover is a run-rate estimate, not a demand forecast or guaranteed stockout date. Revenue is before order-level discounts, refunds, tax, fees and overhead.';
