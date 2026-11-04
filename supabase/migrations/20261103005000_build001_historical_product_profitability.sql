-- Build 001: preserve aggregate unit cost at order-line creation for historical sales analysis.
alter table public.mme_order_lines
 add column if not exists cost_basis_unit_cents bigint,
 add column if not exists cost_basis_captured_at timestamptz,
 add column if not exists cost_basis_status text not null default 'pending'
  check(cost_basis_status in ('captured','missing','not_applicable'));

create or replace function public.mme_snapshot_order_line_cost_basis()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_cost bigint;
begin
 if new.serialized_unit_id is not null then
  new.cost_basis_status:='not_applicable';
  new.cost_basis_unit_cents:=null;
  new.cost_basis_captured_at:=now();
  return new;
 end if;
 select b.average_unit_cost_cents into v_cost
 from public.mme_inventory_balances b
 where b.product_id=new.product_id and b.location_id=new.location_id
 for update;
 if found and v_cost is not null and v_cost>=0 then
  new.cost_basis_unit_cents:=v_cost;
  new.cost_basis_status:='captured';
 else
  new.cost_basis_unit_cents:=null;
  new.cost_basis_status:='missing';
 end if;
 new.cost_basis_captured_at:=now();
 return new;
end; $$;

drop trigger if exists mme_order_line_cost_basis_snapshot on public.mme_order_lines;
create trigger mme_order_line_cost_basis_snapshot
 before insert on public.mme_order_lines
 for each row execute function public.mme_snapshot_order_line_cost_basis();

create or replace view public.mme_paid_product_performance_v
with (security_invoker=true) as
select ol.product_id,ol.location_id,ol.sku_snapshot,ol.title_snapshot,
 ol.condition_snapshot,count(distinct ol.order_id)::bigint as paid_order_count,
 sum(ol.quantity)::bigint as paid_units,
 sum(ol.line_total_cents::numeric)::numeric as gross_line_revenue_cents,
 (sum(ol.quantity::numeric*ol.cost_basis_unit_cents)
  filter (where ol.cost_basis_status='captured'))::numeric as captured_cost_of_goods_cents,
 (sum(ol.quantity)::bigint
  filter (where ol.cost_basis_status='missing')) as units_missing_cost_basis,
 (sum(ol.quantity)::bigint
  filter (where ol.cost_basis_status='captured')) as units_with_cost_basis,
 case when sum(ol.quantity::numeric*ol.cost_basis_unit_cents)
  filter (where ol.cost_basis_status='captured') is null then null
  else (sum(ol.line_total_cents::numeric)
   filter (where ol.cost_basis_status='captured'))
   -(sum(ol.quantity::numeric*ol.cost_basis_unit_cents)
   filter (where ol.cost_basis_status='captured')) end as gross_profit_before_order_discounts_refunds_cents,
 case when (sum(ol.line_total_cents::numeric)
   filter (where ol.cost_basis_status='captured'))=0 then null
  else round(100.0*(
   (sum(ol.line_total_cents::numeric) filter (where ol.cost_basis_status='captured'))
   -(sum(ol.quantity::numeric*ol.cost_basis_unit_cents) filter (where ol.cost_basis_status='captured'))
  )/(sum(ol.line_total_cents::numeric) filter (where ol.cost_basis_status='captured')),2) end as gross_margin_before_order_discounts_refunds_percent,
 min(ol.created_at) as first_paid_order_line_at,max(ol.created_at) as last_paid_order_line_at
from public.mme_order_lines ol
join public.mme_orders o on o.id=ol.order_id
where o.status='paid' and ol.serialized_unit_id is null
group by ol.product_id,ol.location_id,ol.sku_snapshot,ol.title_snapshot,ol.condition_snapshot;

revoke all on function public.mme_snapshot_order_line_cost_basis() from public,anon,authenticated;
revoke all on table public.mme_paid_product_performance_v from public,anon,authenticated;
grant select on public.mme_paid_product_performance_v to service_role;

comment on column public.mme_order_lines.cost_basis_unit_cents is 'Weighted-average inventory cost per unit captured at order-line creation; null when no reliable balance cost existed.';
comment on view public.mme_paid_product_performance_v is 'Paid aggregate product performance using historical order-line cost snapshots. Revenue and margin are before order-level discounts, refunds, tax, payment fees and overhead; missing cost-basis units are disclosed and excluded from margin.';
