-- Build 001: supplier quote comparison and forecast-driven replenishment drafts.
-- Draft generation is advisory only. It never submits a proposal or places a supplier order.

alter table public.mme_purchase_proposal_lines
 add column recommended_supplier_id uuid references public.mme_suppliers(id) on delete restrict,
 add column supplier_quote_history_id uuid references public.mme_supplier_price_history(id) on delete restrict,
 add column supplier_minimum_order_quantity integer check(supplier_minimum_order_quantity is null or supplier_minimum_order_quantity>0),
 add column supplier_quote_snapshot jsonb not null default '{}'::jsonb
  check(jsonb_typeof(supplier_quote_snapshot)='object');

create index mme_purchase_proposal_lines_supplier_idx
 on public.mme_purchase_proposal_lines(recommended_supplier_id)
 where recommended_supplier_id is not null;

create or replace view public.mme_supplier_quote_comparison_v
with (security_invoker=true) as
select h.id as quote_id,h.product_id,h.supplier_id,s.supplier_code,s.display_name as supplier_name,
 h.supplier_sku,h.unit_cost_cents,h.currency,h.minimum_order_quantity,h.quoted_lead_time_days,
 h.quote_reference,h.valid_until,h.recorded_at,
 coalesce(s.default_lead_time_days,365) as fallback_lead_time_days,
 s.payment_terms,s.status as supplier_status,
 row_number() over(partition by h.product_id order by h.unit_cost_cents asc,
  coalesce(h.quoted_lead_time_days,s.default_lead_time_days,365) asc,h.recorded_at desc) as cost_rank,
 row_number() over(partition by h.product_id order by
  coalesce(h.quoted_lead_time_days,s.default_lead_time_days,365) asc,
  h.unit_cost_cents asc,h.recorded_at desc) as speed_rank
from public.mme_supplier_price_history h
join public.mme_suppliers s on s.id=h.supplier_id
where s.status='active' and h.currency='USD'
 and (h.valid_until is null or h.valid_until>=now());

revoke all on public.mme_supplier_quote_comparison_v from public,anon,authenticated;
grant select on public.mme_supplier_quote_comparison_v to service_role;

create or replace function public.mme_create_replenishment_draft(
 p_proposal_reference text,p_location_id uuid,p_actor_identity_id uuid,
 p_rationale text default 'Forecast-driven replenishment recommendation',
 p_max_lines integer default 100
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_proposal uuid; v_forecast record; v_quote record; v_qty integer;
 v_cost bigint; v_total numeric:=0; v_line_count integer:=0; v_snapshot jsonb;
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
   p.serialized,p.title,p.sku,d.average_unit_cost_cents
  from public.mme_get_inventory_forecast(p_location_id,null,true,500,0) f
  join public.mme_products p on p.id=f.product_id and p.active=true
  join public.mme_inventory_dashboard_v d on d.product_id=f.product_id and d.location_id=p_location_id
  where f.suggested_purchase_quantity>0 and p.serialized=false
  order by f.projected_cash_required_cents desc nulls last,f.sku
  limit p_max_lines
 loop
  select q.quote_id,q.supplier_id,q.supplier_name,q.unit_cost_cents,q.minimum_order_quantity,
   q.quoted_lead_time_days,q.quote_reference,q.valid_until,q.supplier_sku
  into v_quote
  from public.mme_supplier_quote_comparison_v q
  where q.product_id=v_forecast.product_id
  order by q.unit_cost_cents asc,
   coalesce(q.quoted_lead_time_days,q.fallback_lead_time_days,365) asc,q.recorded_at desc
  limit 1;

  if found then
   v_qty:=greatest(v_forecast.suggested_purchase_quantity,v_quote.minimum_order_quantity);
   v_cost:=v_quote.unit_cost_cents;
   v_snapshot:=jsonb_build_object('supplier_name',v_quote.supplier_name,
    'supplier_sku',v_quote.supplier_sku,'quote_reference',v_quote.quote_reference,
    'quoted_lead_time_days',v_quote.quoted_lead_time_days,'valid_until',v_quote.valid_until,
    'quote_recorded_at',now(),'selection_method','lowest_valid_unit_cost_then_lead_time');
  else
   v_qty:=v_forecast.suggested_purchase_quantity;
   v_cost:=coalesce(v_forecast.estimated_unit_cost_cents,v_forecast.average_unit_cost_cents,0);
   v_snapshot:=jsonb_build_object('selection_method','no_valid_supplier_quote',
    'requires_manual_supplier_quote',true);
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
  raise exception 'No forecast-enabled aggregate products require replenishment' using errcode='P0001';
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

comment on view public.mme_supplier_quote_comparison_v is
 'Current valid USD supplier quotes ranked by unit cost and lead time; excludes inactive suppliers.';
comment on function public.mme_create_replenishment_draft(text,uuid,uuid,text,integer) is
 'Creates an editable draft from forecast-enabled aggregate products, applying valid supplier MOQ and quote snapshots. Does not submit, approve or issue a PO.';
