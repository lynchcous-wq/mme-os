-- Build 001: financial inventory valuation and pricing opportunity reporting.
-- Cost basis is the existing weighted-average inventory balance cost; retail value is separate.

create or replace function public.mme_get_inventory_financial_summary(
 p_location_id uuid default null,
 p_category_key text default null
) returns table(
 product_count bigint,
 aggregate_units bigint,
 aggregate_cost_value_cents bigint,
 aggregate_retail_value_cents bigint,
 potential_gross_profit_cents bigint,
 weighted_average_cost_cents bigint,
 weighted_average_retail_price_cents bigint,
 products_below_cost bigint,
 zero_cost_unit_count bigint,
 valuation_as_of timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_location_id is not null and not exists(
  select 1 from public.mme_store_locations where id=p_location_id and active=true
 ) then raise exception 'Active location not found' using errcode='P0002'; end if;
 return query
 with aggregate_rows as (
  select p.id,p.unit_price_cents,b.on_hand_quantity,b.average_unit_cost_cents
  from public.mme_inventory_balances b
  join public.mme_products p on p.id=b.product_id
  join public.mme_store_locations l on l.id=b.location_id
  where p.active=true and l.active=true and p.serialized=false
   and b.on_hand_quantity>0
   and (p_location_id is null or b.location_id=p_location_id)
   and (p_category_key is null or p.category_key=p_category_key)
 ), totals as (
  select count(distinct id)::bigint as sku_count,
   coalesce(sum(on_hand_quantity),0)::bigint as units,
   coalesce(sum(on_hand_quantity::numeric*average_unit_cost_cents),0)::numeric as cost_value,
   coalesce(sum(on_hand_quantity::numeric*unit_price_cents),0)::numeric as retail_value,
   coalesce(sum(on_hand_quantity::numeric*(unit_price_cents-average_unit_cost_cents)),0)::numeric as potential_profit,
   coalesce(sum(on_hand_quantity::numeric*average_unit_cost_cents),0)::numeric as cost_weight,
   coalesce(sum(on_hand_quantity::numeric*unit_price_cents),0)::numeric as retail_weight,
   count(*) filter(where unit_price_cents<average_unit_cost_cents)::bigint as below_cost,
   coalesce(sum(on_hand_quantity) filter(where average_unit_cost_cents=0),0)::bigint as zero_cost_units
  from aggregate_rows
 )
 select t.sku_count,t.units,
  case when t.cost_value>9000000000000000 then null else t.cost_value::bigint end,
  case when t.retail_value>9000000000000000 then null else t.retail_value::bigint end,
  case when t.potential_profit between -9000000000000000 and 9000000000000000 then t.potential_profit::bigint else null end,
  case when t.units=0 then 0 else round(t.cost_weight/t.units)::bigint end,
  case when t.units=0 then 0 else round(t.retail_weight/t.units)::bigint end,
  t.below_cost,t.zero_cost_units,now()
 from totals t;
end; $$;

create or replace function public.mme_get_inventory_financial_detail(
 p_location_id uuid default null,
 p_category_key text default null,
 p_search text default null,
 p_sort text default 'cost_value_desc',
 p_limit integer default 100,
 p_offset integer default 0
) returns table(
 product_id uuid,sku text,product_title text,category_key text,condition_grade text,
 location_id uuid,location_code text,on_hand_quantity integer,reserved_quantity integer,
 available_quantity integer,average_unit_cost_cents bigint,retail_price_cents bigint,
 inventory_cost_value_cents bigint,inventory_retail_value_cents bigint,
 potential_gross_profit_cents bigint,potential_margin_percent numeric,
 below_cost boolean,zero_cost boolean,oldest_receipt_event_at timestamptz,
 aging_basis text
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_limit is null or p_limit<1 or p_limit>500 or p_offset is null or p_offset<0
  or p_search is not null and length(p_search)>120
  or p_sort not in ('cost_value_desc','retail_value_desc','margin_asc','oldest_receipt_asc','sku_asc') then
  raise exception 'Invalid inventory financial query' using errcode='22023';
 end if;
 return query
 select p.id,p.sku,p.title,p.category_key,p.condition_grade,l.id,l.location_code,
  b.on_hand_quantity,b.reserved_quantity,b.on_hand_quantity-b.reserved_quantity,
  b.average_unit_cost_cents,p.unit_price_cents,
  (b.on_hand_quantity::bigint*b.average_unit_cost_cents),
  (b.on_hand_quantity::bigint*p.unit_price_cents),
  (b.on_hand_quantity::bigint*(p.unit_price_cents-b.average_unit_cost_cents)),
  case when p.unit_price_cents=0 then null
   else round(100.0*(p.unit_price_cents-b.average_unit_cost_cents)/p.unit_price_cents,2) end,
  p.unit_price_cents<b.average_unit_cost_cents,b.average_unit_cost_cents=0,
  (select min(m.created_at) from public.mme_inventory_movements m
   where m.product_id=p.id and m.location_id=l.id and m.movement_type='receipt'),
  'Oldest recorded receipt event; not remaining-unit FIFO age'
 from public.mme_inventory_balances b
 join public.mme_products p on p.id=b.product_id
 join public.mme_store_locations l on l.id=b.location_id
 where p.active=true and l.active=true and p.serialized=false and b.on_hand_quantity>0
  and (p_location_id is null or l.id=p_location_id)
  and (p_category_key is null or p.category_key=p_category_key)
  and (p_search is null or p.sku ilike '%'||btrim(p_search)||'%' or p.title ilike '%'||btrim(p_search)||'%')
 order by
  case when p_sort='cost_value_desc' then b.on_hand_quantity::numeric*b.average_unit_cost_cents end desc nulls last,
  case when p_sort='retail_value_desc' then b.on_hand_quantity::numeric*p.unit_price_cents end desc nulls last,
  case when p_sort='margin_asc' then case when p.unit_price_cents=0 then null else 100.0*(p.unit_price_cents-b.average_unit_cost_cents)/p.unit_price_cents end end asc nulls last,
  case when p_sort='oldest_receipt_asc' then (select min(m.created_at) from public.mme_inventory_movements m where m.product_id=p.id and m.location_id=l.id and m.movement_type='receipt') end asc nulls last,
  case when p_sort='sku_asc' then p.sku end asc nulls last,
  p.sku,l.location_code
 limit p_limit offset p_offset;
end; $$;

revoke all on function public.mme_get_inventory_financial_summary(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_get_inventory_financial_detail(uuid,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.mme_get_inventory_financial_summary(uuid,text) to service_role;
grant execute on function public.mme_get_inventory_financial_detail(uuid,text,text,text,integer,integer) to service_role;

comment on function public.mme_get_inventory_financial_summary(uuid,text) is
 'Aggregate inventory weighted-average cost valuation and separate current-price retail opportunity; excludes serialized units.';
comment on function public.mme_get_inventory_financial_detail(uuid,text,text,text,integer,integer) is
 'Product/location financial detail. Oldest receipt timestamp is a receipt-event proxy, not FIFO remaining-unit age or an accounting aging schedule.';
