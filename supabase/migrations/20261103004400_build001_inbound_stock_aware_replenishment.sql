-- Build 001: net committed incoming purchase-order quantities against replenishment needs.
-- Drafts and unissued POs are not treated as inbound supply.
create or replace view public.mme_inventory_inbound_commitments_v
with (security_invoker=true) as
select pol.product_id,pol.location_id,
 sum(greatest(pol.ordered_quantity-pol.received_quantity,0))::integer as inbound_open_quantity,
 count(distinct po.id)::integer as open_purchase_order_count,
 min(po.expected_delivery_at) as next_expected_delivery_at
from public.mme_purchase_order_lines pol
join public.mme_purchase_orders po on po.id=pol.purchase_order_id
where po.status in ('issued','acknowledged','partially_received')
 and pol.ordered_quantity>pol.received_quantity
group by pol.product_id,pol.location_id;
revoke all on public.mme_inventory_inbound_commitments_v from public,anon,authenticated;
grant select on public.mme_inventory_inbound_commitments_v to service_role;

create or replace function public.mme_create_replenishment_draft(
 p_proposal_reference text,p_location_id uuid,p_actor_identity_id uuid,
 p_rationale text default 'Forecast-driven replenishment recommendation',
 p_max_lines integer default 100
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_proposal uuid; v_forecast record; v_quote record; v_qty integer;
 v_net_need integer; v_inbound integer; v_cost bigint; v_total numeric:=0;
 v_line_count integer:=0; v_snapshot jsonb;
begin
 if p_proposal_reference is null or length(btrim(p_proposal_reference)) not between 3 and 100
  or p_location_id is null or p_actor_identity_id is null
  or p_max_lines is null or p_max_lines not between 1 and 100
  or p_rationale is null or length(btrim(p_rationale)) not between 5 and 1000 then
  raise exception 'Invalid replenishment draft request' using errcode='22023';
 end if;
 perform 1 from public.mme_store_locations where id=p_location_id and active=true;
 if not found then raise exception 'Active replenishment location not found' using errcode='P0002'; end if;

 insert into public.mme_purchase_proposals(proposal_reference,status,location_id,rationale,created_by_identity_id)
 values(btrim(p_proposal_reference),'draft',p_location_id,btrim(p_rationale),p_actor_identity_id)
 returning id into v_proposal;

 for v_forecast in
  select f.product_id,f.suggested_purchase_quantity,f.estimated_unit_cost_cents,
   f.average_daily_units,f.days_of_stock,f.seasonal_multiplier,
   p.serialized,p.title,p.sku,d.average_unit_cost_cents,
   coalesce(ic.inbound_open_quantity,0)::integer as inbound_open_quantity,
   ic.open_purchase_order_count,ic.next_expected_delivery_at
  from public.mme_get_inventory_forecast(p_location_id,null,true,500,0) f
  join public.mme_products p on p.id=f.product_id and p.active=true
  join public.mme_inventory_dashboard_v d on d.product_id=f.product_id and d.location_id=p_location_id
  left join public.mme_inventory_inbound_commitments_v ic
   on ic.product_id=f.product_id and ic.location_id=p_location_id
  where f.suggested_purchase_quantity>coalesce(ic.inbound_open_quantity,0)
   and p.serialized=false
  order by f.projected_cash_required_cents desc nulls last,f.sku
  limit p_max_lines
 loop
  v_inbound:=v_forecast.inbound_open_quantity;
  v_net_need:=greatest(v_forecast.suggested_purchase_quantity-v_inbound,0);
  select q.quote_id,q.supplier_id,q.supplier_name,q.unit_cost_cents,q.minimum_order_quantity,
   q.quoted_lead_time_days,q.quote_reference,q.valid_until,q.supplier_sku
  into v_quote
  from public.mme_supplier_quote_comparison_v q
  where q.product_id=v_forecast.product_id
  order by q.unit_cost_cents asc,
   coalesce(q.quoted_lead_time_days,q.fallback_lead_time_days,365) asc,q.recorded_at desc
  limit 1;

  if found then
   v_qty:=greatest(v_net_need,coalesce(v_quote.minimum_order_quantity,1));
   v_cost:=v_quote.unit_cost_cents;
   v_snapshot:=jsonb_build_object('supplier_name',v_quote.supplier_name,
    'supplier_sku',v_quote.supplier_sku,'quote_reference',v_quote.quote_reference,
    'quoted_lead_time_days',v_quote.quoted_lead_time_days,'valid_until',v_quote.valid_until,
    'quote_recorded_at',now(),'selection_method','lowest_valid_unit_cost_then_lead_time',
    'forecast_suggested_quantity',v_forecast.suggested_purchase_quantity,
    'committed_inbound_quantity',v_inbound,'net_replenishment_need',v_net_need,
    'open_purchase_order_count',v_forecast.open_purchase_order_count,
    'next_expected_delivery_at',v_forecast.next_expected_delivery_at);
  else
   v_qty:=v_net_need;
   v_cost:=coalesce(v_forecast.estimated_unit_cost_cents,v_forecast.average_unit_cost_cents,0);
   v_snapshot:=jsonb_build_object('selection_method','no_valid_supplier_quote',
    'requires_manual_supplier_quote',true,
    'forecast_suggested_quantity',v_forecast.suggested_purchase_quantity,
    'committed_inbound_quantity',v_inbound,'net_replenishment_need',v_net_need,
    'open_purchase_order_count',v_forecast.open_purchase_order_count,
    'next_expected_delivery_at',v_forecast.next_expected_delivery_at);
  end if;

  insert into public.mme_purchase_proposal_lines(proposal_id,product_id,location_id,
   suggested_quantity,estimated_unit_cost_cents,average_daily_units,days_of_stock,
   seasonal_multiplier,supplier_snapshot,recommended_supplier_id,supplier_quote_history_id,
   supplier_minimum_order_quantity,supplier_quote_snapshot)
  values(v_proposal,v_forecast.product_id,p_location_id,v_qty,v_cost,
   v_forecast.average_daily_units,v_forecast.days_of_stock,v_forecast.seasonal_multiplier,
   case when v_quote.supplier_id is not null then v_quote.supplier_name else 'Quote required' end,
   v_quote.supplier_id,v_quote.quote_id,v_quote.minimum_order_quantity,v_snapshot);
  v_total:=v_total+v_qty::numeric*v_cost;
  v_line_count:=v_line_count+1;
 end loop;

 if v_line_count=0 then
  raise exception 'No forecast-enabled aggregate products require replenishment after committed inbound stock is applied' using errcode='P0001';
 end if;
 if v_total>9000000000000000 then
  raise exception 'Replenishment draft exceeds supported amount' using errcode='22003';
 end if;
 update public.mme_purchase_proposals set projected_total_cents=v_total::bigint,updated_at=now()
 where id=v_proposal;
 return v_proposal;
end; $$;

revoke all on function public.mme_create_replenishment_draft(text,uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.mme_create_replenishment_draft(text,uuid,uuid,text,integer) to service_role;
comment on view public.mme_inventory_inbound_commitments_v is
 'Unreceived quantities from issued, acknowledged and partially received POs only; excludes drafts, unissued and cancelled orders.';
comment on function public.mme_create_replenishment_draft(text,uuid,uuid,text,integer) is
 'Creates CEO-reviewable replenishment drafts net of committed incoming quantities; applies valid supplier quotes and MOQ. Never submits or issues a PO.';
