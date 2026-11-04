-- Build 001: demand forecasting and CEO-controlled purchasing proposals.
-- Forecasts are decision support. This migration does not place supplier orders.

create table public.mme_inventory_forecast_rules (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  lookback_days integer not null default 90 check (lookback_days between 7 and 365),
  target_coverage_days integer not null default 30 check (target_coverage_days between 1 and 180),
  safety_stock_days integer not null default 7 check (safety_stock_days between 0 and 90),
  seasonal_multiplier numeric(6,3) not null default 1.000 check (seasonal_multiplier between 0.250 and 4.000),
  seasonal_basis text not null default 'manual' check (seasonal_basis in ('manual','prior_year','campaign','event')),
  enabled boolean not null default true,
  updated_by_identity_id uuid not null,
  approved_by_identity_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id,location_id)
);

create table public.mme_purchase_proposals (
  id uuid primary key default gen_random_uuid(),
  proposal_reference text not null unique,
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected','cancelled')),
  location_id uuid references public.mme_store_locations(id) on delete restrict,
  projected_total_cents bigint not null default 0 check (projected_total_cents>=0),
  currency text not null default 'USD' check (currency='USD'),
  rationale text not null,
  created_by_identity_id uuid not null,
  submitted_at timestamptz,
  decided_by_identity_id uuid,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status in ('approved','rejected') and decided_at is not null and decided_by_identity_id is not null)
      or (status not in ('approved','rejected')))
);

create table public.mme_purchase_proposal_lines (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.mme_purchase_proposals(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  suggested_quantity integer not null check (suggested_quantity>0),
  estimated_unit_cost_cents bigint not null check (estimated_unit_cost_cents>=0),
  estimated_line_total_cents bigint generated always as (suggested_quantity::bigint*estimated_unit_cost_cents) stored,
  average_daily_units numeric(12,4) not null check (average_daily_units>=0),
  days_of_stock numeric(12,2),
  seasonal_multiplier numeric(6,3) not null check (seasonal_multiplier between 0.250 and 4.000),
  supplier_snapshot text,
  created_at timestamptz not null default now(),
  unique(proposal_id,product_id,location_id)
);

create index mme_inventory_forecast_rules_enabled_idx
  on public.mme_inventory_forecast_rules(location_id,enabled);
create index mme_purchase_proposals_status_created_idx
  on public.mme_purchase_proposals(status,created_at desc);
create index mme_purchase_proposal_lines_product_idx
  on public.mme_purchase_proposal_lines(product_id,location_id);

alter table public.mme_inventory_forecast_rules enable row level security;
alter table public.mme_purchase_proposals enable row level security;
alter table public.mme_purchase_proposal_lines enable row level security;
revoke all on public.mme_inventory_forecast_rules from anon,authenticated;
revoke all on public.mme_purchase_proposals from anon,authenticated;
revoke all on public.mme_purchase_proposal_lines from anon,authenticated;
grant all on public.mme_inventory_forecast_rules to service_role;
grant all on public.mme_purchase_proposals to service_role;
grant all on public.mme_purchase_proposal_lines to service_role;

create or replace function public.mme_get_inventory_forecast(
  p_location_id uuid default null,
  p_product_id uuid default null,
  p_low_stock_only boolean default false,
  p_limit integer default 200,
  p_offset integer default 0
) returns table(
  product_id uuid,sku text,title text,location_id uuid,location_name text,
  available_quantity integer,average_daily_units numeric,
  projected_daily_units numeric,days_of_stock numeric,
  lead_time_days integer,target_coverage_days integer,safety_stock_days integer,
  suggested_purchase_quantity integer,estimated_unit_cost_cents bigint,
  projected_cash_required_cents bigint,seasonal_multiplier numeric,
  forecast_lookback_days integer,demand_sample_days integer,
  forecast_confidence text,preferred_supplier text
) language plpgsql stable security definer set search_path=''
as $$
begin
  if p_limit is null or p_limit<1 or p_limit>500 or p_offset is null or p_offset<0 then
    raise exception 'Invalid forecast query' using errcode='22023';
  end if;
  return query
  with base as (
    select d.product_id,d.sku,d.title,d.location_id,d.location_name,d.aggregate_available,
      d.average_unit_cost_cents,d.lead_time_days,d.target_available_quantity,d.preferred_supplier,
      coalesce(fr.lookback_days,90) as lookback_days,
      coalesce(fr.target_coverage_days,30) as target_days,
      coalesce(fr.safety_stock_days,7) as safety_days,
      coalesce(fr.seasonal_multiplier,1.000)::numeric as seasonal_factor,
      coalesce(fr.enabled,false) as forecast_enabled
    from public.mme_inventory_dashboard_v d
    left join public.mme_inventory_forecast_rules fr
      on fr.product_id=d.product_id and fr.location_id=d.location_id
    where (p_location_id is null or d.location_id=p_location_id)
      and (p_product_id is null or d.product_id=p_product_id)
  ), demand as (
    select b.*,coalesce(x.units,0)::numeric as units_sold,
      coalesce(x.sample_days,0)::integer as sample_days
    from base b
    left join lateral (
      select sum(ol.quantity)::numeric as units,
        count(distinct (o.created_at at time zone 'UTC')::date)::integer as sample_days
      from public.mme_order_lines ol
      join public.mme_orders o on o.id=ol.order_id
      where ol.product_id=b.product_id and ol.location_id=b.location_id
        and o.status='paid'
        and o.created_at>=now()-make_interval(days=>b.lookback_days)
        and o.created_at<now()
    ) x on true
  ), calc as (
    select d.*,
      case when d.units_sold>0
        then d.units_sold/d.lookback_days else 0::numeric end as avg_daily,
      case when d.units_sold>0
        then (d.units_sold/d.lookback_days)*d.seasonal_factor else 0::numeric end as projected_daily
    from demand d
  )
  select c.product_id,c.sku,c.title,c.location_id,c.location_name,c.aggregate_available,
    round(c.avg_daily,4),round(c.projected_daily,4),
    case when c.projected_daily>0 then round(c.aggregate_available/c.projected_daily,2) else null end,
    c.lead_time_days,c.target_days,c.safety_days,
    case when c.forecast_enabled and c.projected_daily>0
      then greatest(ceil(c.projected_daily*(c.lead_time_days+c.target_days+c.safety_days))-c.aggregate_available,0)::integer
      else 0 end,
    c.average_unit_cost_cents,
    case when c.forecast_enabled and c.projected_daily>0
      then greatest(ceil(c.projected_daily*(c.lead_time_days+c.target_days+c.safety_days))-c.aggregate_available,0)::bigint*c.average_unit_cost_cents
      else 0 end,
    c.seasonal_factor,c.lookback_days,c.sample_days,
    case when c.sample_days>=30 then 'high' when c.sample_days>=7 then 'medium'
         when c.sample_days>0 then 'low' else 'insufficient_data' end,
    c.preferred_supplier
  from calc c
  where (not p_low_stock_only or (c.forecast_enabled and c.projected_daily>0
    and c.aggregate_available/c.projected_daily<=c.lead_time_days+c.safety_days))
  order by case when c.forecast_enabled and c.projected_daily>0
    then c.aggregate_available/c.projected_daily else 999999 end,c.title,c.location_name
  limit p_limit offset p_offset;
end; $$;

create or replace function public.mme_set_inventory_forecast_rule(
  p_product_id uuid,p_location_id uuid,p_lookback_days integer,
  p_target_coverage_days integer,p_safety_stock_days integer,
  p_seasonal_multiplier numeric,p_seasonal_basis text,p_enabled boolean,
  p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if p_product_id is null or p_location_id is null
    or p_lookback_days not between 7 and 365
    or p_target_coverage_days not between 1 and 180
    or p_safety_stock_days not between 0 and 90
    or p_seasonal_multiplier not between 0.250 and 4.000
    or p_seasonal_basis not in ('manual','prior_year','campaign','event')
    or p_enabled is null or p_actor_identity_id is null then
    raise exception 'Invalid forecast rule' using errcode='22023';
  end if;
  perform 1 from public.mme_products where id=p_product_id and active=true for update;
  if not found then raise exception 'Active product not found' using errcode='P0002'; end if;
  perform 1 from public.mme_store_locations where id=p_location_id and active=true;
  if not found then raise exception 'Active location not found' using errcode='P0002'; end if;
  insert into public.mme_inventory_forecast_rules(
    product_id,location_id,lookback_days,target_coverage_days,safety_stock_days,
    seasonal_multiplier,seasonal_basis,enabled,updated_by_identity_id,approved_by_identity_id
  ) values(
    p_product_id,p_location_id,p_lookback_days,p_target_coverage_days,p_safety_stock_days,
    p_seasonal_multiplier,p_seasonal_basis,p_enabled,p_actor_identity_id,p_approved_by_identity_id
  ) on conflict(product_id,location_id) do update set
    lookback_days=excluded.lookback_days,target_coverage_days=excluded.target_coverage_days,
    safety_stock_days=excluded.safety_stock_days,seasonal_multiplier=excluded.seasonal_multiplier,
    seasonal_basis=excluded.seasonal_basis,enabled=excluded.enabled,
    updated_by_identity_id=excluded.updated_by_identity_id,
    approved_by_identity_id=excluded.approved_by_identity_id,updated_at=now()
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.mme_create_purchase_proposal(
  p_reference text,p_location_id uuid,p_rationale text,
  p_actor_identity_id uuid,p_lines jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_line record; v_total numeric:=0;
begin
  if p_reference is null or length(btrim(p_reference))<3 or length(p_reference)>100
    or p_rationale is null or length(btrim(p_rationale))<5
    or p_actor_identity_id is null or p_lines is null
    or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0
    or jsonb_array_length(p_lines)>100 then
    raise exception 'Invalid purchase proposal' using errcode='22023';
  end if;
  if p_location_id is not null and not exists(select 1 from public.mme_store_locations where id=p_location_id and active=true) then
    raise exception 'Active proposal location not found' using errcode='P0002';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid,location_id uuid,quantity integer,estimated_unit_cost_cents bigint)
    where x.product_id is null or x.location_id is null or x.quantity is null or x.quantity<1 or x.quantity>10000
      or x.estimated_unit_cost_cents is null or x.estimated_unit_cost_cents<0)
    or exists(select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid,location_id uuid,quantity integer,estimated_unit_cost_cents bigint)
      group by x.product_id,x.location_id having count(*)>1) then
    raise exception 'Invalid or duplicate proposal line' using errcode='22023';
  end if;
  insert into public.mme_purchase_proposals(proposal_reference,location_id,rationale,created_by_identity_id)
    values(btrim(p_reference),p_location_id,btrim(p_rationale),p_actor_identity_id) returning id into v_id;
  for v_line in
    select x.product_id,x.location_id,x.quantity,x.estimated_unit_cost_cents
    from jsonb_to_recordset(p_lines) as x(product_id uuid,location_id uuid,quantity integer,estimated_unit_cost_cents bigint)
    order by x.product_id,x.location_id
  loop
    perform 1 from public.mme_products where id=v_line.product_id and active=true for update;
    if not found then raise exception 'Proposal product unavailable' using errcode='P0002'; end if;
    perform 1 from public.mme_store_locations where id=v_line.location_id and active=true;
    if not found then raise exception 'Proposal location unavailable' using errcode='P0002'; end if;
    insert into public.mme_purchase_proposal_lines(
      proposal_id,product_id,location_id,suggested_quantity,estimated_unit_cost_cents,
      average_daily_units,days_of_stock,seasonal_multiplier
    )
    select v_id,v_line.product_id,v_line.location_id,v_line.quantity,v_line.estimated_unit_cost_cents,
      f.average_daily_units,f.days_of_stock,f.seasonal_multiplier
    from public.mme_get_inventory_forecast(v_line.location_id,v_line.product_id,false,1,0) f;
    if not found then
      insert into public.mme_purchase_proposal_lines(
        proposal_id,product_id,location_id,suggested_quantity,estimated_unit_cost_cents,
        average_daily_units,seasonal_multiplier
      ) values(v_id,v_line.product_id,v_line.location_id,v_line.quantity,v_line.estimated_unit_cost_cents,0,1.000);
    end if;
  end loop;
  select coalesce(sum(estimated_line_total_cents),0) into v_total
    from public.mme_purchase_proposal_lines where proposal_id=v_id;
  if v_total>9000000000000000 then raise exception 'Purchase proposal exceeds supported amount' using errcode='22003'; end if;
  update public.mme_purchase_proposals set projected_total_cents=v_total where id=v_id;
  return v_id;
end; $$;

create or replace function public.mme_submit_purchase_proposal(
  p_proposal_id uuid,p_actor_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
  if p_proposal_id is null or p_actor_identity_id is null then raise exception 'Invalid submission' using errcode='22023'; end if;
  update public.mme_purchase_proposals set status='submitted',submitted_at=now(),
    updated_at=now() where id=p_proposal_id and status='draft';
  return found;
end; $$;

create or replace function public.mme_decide_purchase_proposal(
  p_proposal_id uuid,p_decision text,p_actor_identity_id uuid,p_decision_note text
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
  if p_proposal_id is null or p_decision not in ('approved','rejected')
    or p_actor_identity_id is null or p_decision_note is null or length(btrim(p_decision_note))<3 then
    raise exception 'Invalid purchase proposal decision' using errcode='22023';
  end if;
  update public.mme_purchase_proposals set status=p_decision,decided_by_identity_id=p_actor_identity_id,
    decided_at=now(),decision_note=btrim(p_decision_note),updated_at=now()
   where id=p_proposal_id and status='submitted';
  return found;
end; $$;

revoke all on function public.mme_get_inventory_forecast(uuid,uuid,boolean,integer,integer) from public,anon,authenticated;
revoke all on function public.mme_set_inventory_forecast_rule(uuid,uuid,integer,integer,integer,numeric,text,boolean,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_create_purchase_proposal(text,uuid,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.mme_submit_purchase_proposal(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_decide_purchase_proposal(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_get_inventory_forecast(uuid,uuid,boolean,integer,integer) to service_role;
grant execute on function public.mme_set_inventory_forecast_rule(uuid,uuid,integer,integer,integer,numeric,text,boolean,uuid,uuid) to service_role;
grant execute on function public.mme_create_purchase_proposal(text,uuid,text,uuid,jsonb) to service_role;
grant execute on function public.mme_submit_purchase_proposal(uuid,uuid) to service_role;
grant execute on function public.mme_decide_purchase_proposal(uuid,text,uuid,text) to service_role;

comment on table public.mme_inventory_forecast_rules is
  'Per product/location demand lookback, coverage, safety stock and explicitly sourced seasonal multiplier.';
comment on table public.mme_purchase_proposals is
  'Draft/submitted/CEO-approved purchasing proposals. Approval does not place a supplier order.';
