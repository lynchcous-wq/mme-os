-- Build 001: supplier procurement intelligence with independently aggregated operational metrics.
create or replace view public.mme_supplier_procurement_intelligence_v
with (security_invoker=true) as
with delivery as (
 select d.supplier_id,count(*)::bigint as delivery_count,
  count(*) filter(where d.delivery_status='received')::bigint as completed_deliveries,
  count(*) filter(where d.delivery_status in ('delayed','disputed'))::bigint as delayed_or_disputed_count,
  coalesce(sum(d.units_expected),0)::bigint as units_expected,
  coalesce(sum(d.units_received),0)::bigint as units_received,
  coalesce(sum(d.units_damaged),0)::bigint as units_damaged,
  round(100.0*sum(d.units_received) filter(where d.delivery_status='received')/
   nullif(sum(d.units_expected) filter(where d.delivery_status='received'),0),2) as completion_rate_percent,
  round(100.0*(sum(d.units_received)-sum(d.units_damaged))/nullif(sum(d.units_received),0),2) as non_damaged_rate_percent,
  round(avg(extract(epoch from (d.received_at-d.expected_at))/86400.0)
   filter(where d.received_at is not null and d.expected_at is not null),2) as avg_days_vs_expected,
  count(*) filter(where d.received_at is not null and d.expected_at is not null)::bigint as schedule_observation_count
 from public.mme_supplier_deliveries d group by d.supplier_id
), quotes as (
 select h.supplier_id,count(*)::bigint as quote_count,
  count(distinct h.product_id)::bigint as quoted_product_count,
  min(h.unit_cost_cents)::bigint as lowest_quoted_unit_cost_cents,
  max(h.unit_cost_cents)::bigint as highest_quoted_unit_cost_cents,
  round(avg(h.unit_cost_cents),2) as average_quoted_unit_cost_cents,
  max(h.recorded_at) as latest_quote_at,
  count(*) filter(where h.recorded_at>=now()-interval '90 days')::bigint as quotes_90d
 from public.mme_supplier_price_history h
 where h.currency='USD' group by h.supplier_id
), invoice as (
 select po.supplier_id,count(i.id)::bigint as invoice_count,
  count(i.id) filter(where i.match_status='matched')::bigint as matched_invoice_count,
  count(i.id) filter(where i.match_status='variance')::bigint as variance_invoice_count,
  count(i.id) filter(where i.match_status='disputed')::bigint as disputed_invoice_count,
  count(i.id) filter(where i.match_status='pending')::bigint as pending_invoice_count,
  coalesce(sum(i.total_cents) filter(where i.match_status='variance'),0)::numeric as variance_invoice_total_cents
 from public.mme_supplier_invoices i join public.mme_purchase_orders po on po.id=i.purchase_order_id
 group by po.supplier_id
), purchase as (
 select po.supplier_id,count(*)::bigint as purchase_order_count,
  count(*) filter(where po.status='received')::bigint as received_po_count,
  coalesce(sum(po.total_cents),0)::numeric as ordered_total_cents,
  max(po.created_at) as latest_purchase_order_at
 from public.mme_purchase_orders po group by po.supplier_id
)
select s.id as supplier_id,s.supplier_code,s.display_name,s.status,
 coalesce(d.delivery_count,0) as delivery_count,
 coalesce(d.completed_deliveries,0) as completed_deliveries,
 coalesce(d.delayed_or_disputed_count,0) as delayed_or_disputed_count,
 coalesce(d.units_expected,0) as units_expected,
 coalesce(d.units_received,0) as units_received,
 coalesce(d.units_damaged,0) as units_damaged,
 d.completion_rate_percent,d.non_damaged_rate_percent,d.avg_days_vs_expected,
 coalesce(d.schedule_observation_count,0) as schedule_observation_count,
 coalesce(q.quote_count,0) as quote_count,coalesce(q.quoted_product_count,0) as quoted_product_count,
 q.lowest_quoted_unit_cost_cents,q.highest_quoted_unit_cost_cents,
 q.average_quoted_unit_cost_cents,q.latest_quote_at,coalesce(q.quotes_90d,0) as quotes_90d,
 coalesce(i.invoice_count,0) as invoice_count,coalesce(i.matched_invoice_count,0) as matched_invoice_count,
 coalesce(i.variance_invoice_count,0) as variance_invoice_count,
 coalesce(i.disputed_invoice_count,0) as disputed_invoice_count,
 coalesce(i.pending_invoice_count,0) as pending_invoice_count,
 coalesce(i.variance_invoice_total_cents,0) as variance_invoice_total_cents,
 coalesce(p.purchase_order_count,0) as purchase_order_count,
 coalesce(p.received_po_count,0) as received_po_count,
 coalesce(p.ordered_total_cents,0) as ordered_total_cents,p.latest_purchase_order_at,
 case when coalesce(i.invoice_count,0)=0 then null
  else round(100.0*i.matched_invoice_count/i.invoice_count,2) end as invoice_match_rate_percent,
 case when coalesce(i.invoice_count,0)=0 then 'no_invoice_history'
  when i.pending_invoice_count>0 then 'pending_review'
  when i.variance_invoice_count+i.disputed_invoice_count>0 then 'attention_required'
  else 'clear' end as invoice_control_status,
 now() as calculated_at
from public.mme_suppliers s
left join delivery d on d.supplier_id=s.id
left join quotes q on q.supplier_id=s.id
left join invoice i on i.supplier_id=s.id
left join purchase p on p.supplier_id=s.id;

create or replace view public.mme_supplier_quote_cost_trend_v
with (security_invoker=true) as
select h.supplier_id,s.supplier_code,s.display_name,h.product_id,p.sku,p.title,
 count(*)::bigint as quote_observation_count,
 min(h.unit_cost_cents)::bigint as lowest_quote_cents,
 max(h.unit_cost_cents)::bigint as highest_quote_cents,
 round(avg(h.unit_cost_cents),2) as average_quote_cents,
 (array_agg(h.unit_cost_cents order by h.recorded_at desc))[1] as latest_quote_cents,
 (array_agg(h.recorded_at order by h.recorded_at desc))[1] as latest_quote_at,
 (array_agg(h.unit_cost_cents order by h.recorded_at asc))[1] as earliest_quote_cents,
 (array_agg(h.recorded_at order by h.recorded_at asc))[1] as earliest_quote_at,
 case when count(*)<2 then null else round(100.0*(
  (array_agg(h.unit_cost_cents order by h.recorded_at desc))[1]-
  (array_agg(h.unit_cost_cents order by h.recorded_at asc))[1]
 )/nullif((array_agg(h.unit_cost_cents order by h.recorded_at asc))[1],0),2) end as first_to_latest_change_percent
from public.mme_supplier_price_history h
join public.mme_suppliers s on s.id=h.supplier_id
join public.mme_products p on p.id=h.product_id
where h.currency='USD'
group by h.supplier_id,s.supplier_code,s.display_name,h.product_id,p.sku,p.title;

revoke all on public.mme_supplier_procurement_intelligence_v,public.mme_supplier_quote_cost_trend_v from public,anon,authenticated;
grant select on public.mme_supplier_procurement_intelligence_v,public.mme_supplier_quote_cost_trend_v to service_role;

comment on view public.mme_supplier_procurement_intelligence_v is
 'Supplier-level delivery, quality, quote coverage, invoice matching and purchasing activity. Metrics with no source observations are null or explicitly zero-count; no composite supplier rating is inferred.';
comment on view public.mme_supplier_quote_cost_trend_v is
 'Per-supplier and per-product historical quote range and first-to-latest percentage change. Historical quotes are not guaranteed current offers.';
