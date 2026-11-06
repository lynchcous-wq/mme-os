-- Build 009.56 — inventory intelligence, market research and demand forecasting.
begin;
create table public.mme_inventory_product_fingerprints (
 fingerprint_id uuid primary key default gen_random_uuid(),
 sku_reference text not null unique,
 manufacturer text, model_number text, model_name text,
 storage_capacity text, memory_capacity text, screen_size text,
 connectivity text, condition_class text not null check(condition_class in ('new','open_box','refurbished','used','parts_only')),
 identity_confidence numeric(5,2) not null check(identity_confidence between 0 and 100),
 identity_evidence jsonb not null default '{}'::jsonb,
 verified_by uuid, verified_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.mme_inventory_market_observations (
 observation_id uuid primary key default gen_random_uuid(),
 fingerprint_id uuid not null references public.mme_inventory_product_fingerprints(fingerprint_id) on delete restrict,
 source_name text not null, source_url text, source_listing_reference text,
 observed_price numeric(14,2) not null check(observed_price>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 observed_condition text not null check(observed_condition in ('new','open_box','refurbished','used','parts_only')),
 availability_status text not null check(availability_status in ('available','out_of_stock','unknown')),
 shipping_cost numeric(14,2) not null default 0 check(shipping_cost>=0),
 source_confidence numeric(5,2) not null check(source_confidence between 0 and 100),
 observed_at timestamptz not null, expires_at timestamptz,
 evidence_reference text, recorded_by uuid not null, created_at timestamptz not null default now()
);
create index mme_inventory_market_observations_lookup_idx on public.mme_inventory_market_observations(fingerprint_id,currency_code,observed_at desc);
create table public.mme_inventory_demand_snapshots (
 demand_snapshot_id uuid primary key default gen_random_uuid(),
 sku_reference text not null,
 location_reference text not null,
 window_start date not null, window_end date not null,
 units_sold integer not null check(units_sold>=0),
 units_returned integer not null default 0 check(units_returned>=0),
 units_on_hand integer not null check(units_on_hand>=0),
 units_reserved integer not null default 0 check(units_reserved>=0),
 units_inbound integer not null default 0 check(units_inbound>=0),
 unit_cost numeric(14,2) not null check(unit_cost>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 captured_by uuid not null, captured_at timestamptz not null default now(),
 check(window_end>window_start), check(units_reserved<=units_on_hand)
);
create index mme_inventory_demand_snapshots_sku_idx on public.mme_inventory_demand_snapshots(sku_reference,location_reference,window_end desc);
create table public.mme_inventory_demand_forecasts (
 forecast_id uuid primary key default gen_random_uuid(),
 sku_reference text not null, location_reference text not null,
 source_snapshot_id uuid not null references public.mme_inventory_demand_snapshots(demand_snapshot_id) on delete restrict,
 daily_net_velocity numeric(14,4) not null check(daily_net_velocity>=0),
 days_of_cover numeric(14,2), forecast_horizon_days integer not null check(forecast_horizon_days between 1 and 365),
 forecast_units numeric(14,2) not null check(forecast_units>=0),
 suggested_reorder_quantity integer not null check(suggested_reorder_quantity>=0),
 confidence numeric(5,2) not null check(confidence between 0 and 100),
 forecast_method text not null check(forecast_method in ('simple_velocity','weighted_velocity')),
 generated_at timestamptz not null default now()
);
create index mme_inventory_demand_forecasts_sku_idx on public.mme_inventory_demand_forecasts(sku_reference,location_reference,generated_at desc);
create table public.mme_inventory_procurement_recommendations (
 recommendation_id uuid primary key default gen_random_uuid(),
 forecast_id uuid not null references public.mme_inventory_demand_forecasts(forecast_id) on delete restrict,
 sku_reference text not null, location_reference text not null,
 recommended_quantity integer not null check(recommended_quantity>=0),
 estimated_unit_cost numeric(14,2) not null check(estimated_unit_cost>=0),
 estimated_total_cost numeric(14,2) not null check(estimated_total_cost>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 recommendation_reason jsonb not null default '{}'::jsonb,
 approval_status text not null default 'pending' check(approval_status in ('pending','approved','rejected','expired')),
 requested_by uuid not null, approved_by uuid, approved_at timestamptz,
 created_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>requested_by)
);
create table public.mme_inventory_intelligence_alerts (
 alert_id uuid primary key default gen_random_uuid(),
 sku_reference text not null, location_reference text,
 alert_type text not null check(alert_type in ('low_stock','slow_moving','excess_stock','market_price_shift','low_market_confidence','reorder_suggested')),
 severity text not null check(severity in ('info','warning','critical')),
 alert_payload jsonb not null default '{}'::jsonb,
 alert_status text not null default 'open' check(alert_status in ('open','acknowledged','resolved','suppressed')),
 deduplication_key text not null unique,
 created_at timestamptz not null default now(), resolved_at timestamptz
);
create table public.mme_inventory_intelligence_audit (
 audit_id bigint generated always as identity primary key,
 actor_user_id uuid not null, entity_type text not null, entity_id uuid,
 action text not null, prior_state jsonb not null default '{}'::jsonb,
 new_state jsonb not null default '{}'::jsonb, reason text,
 created_at timestamptz not null default now()
);
alter table public.mme_inventory_product_fingerprints enable row level security;
alter table public.mme_inventory_market_observations enable row level security;
alter table public.mme_inventory_demand_snapshots enable row level security;
alter table public.mme_inventory_demand_forecasts enable row level security;
alter table public.mme_inventory_procurement_recommendations enable row level security;
alter table public.mme_inventory_intelligence_alerts enable row level security;
alter table public.mme_inventory_intelligence_audit enable row level security;
revoke all on public.mme_inventory_product_fingerprints,public.mme_inventory_market_observations,
 public.mme_inventory_demand_snapshots,public.mme_inventory_demand_forecasts,
 public.mme_inventory_procurement_recommendations,public.mme_inventory_intelligence_alerts,
 public.mme_inventory_intelligence_audit from public,anon,authenticated;
grant select,insert,update on public.mme_inventory_product_fingerprints,public.mme_inventory_market_observations,
 public.mme_inventory_demand_snapshots,public.mme_inventory_demand_forecasts,
 public.mme_inventory_procurement_recommendations,public.mme_inventory_intelligence_alerts to service_role;
grant select,insert on public.mme_inventory_intelligence_audit to service_role;
revoke update,delete,truncate on public.mme_inventory_intelligence_audit from public,anon,authenticated,service_role;

create or replace function public.mme_inventory_intelligence_record_market_observation(
 p_fingerprint_id uuid,p_source_name text,p_source_url text,p_listing_reference text,
 p_price numeric,p_currency text,p_condition text,p_availability text,p_shipping numeric,
 p_confidence numeric,p_observed_at timestamptz,p_expires_at timestamptz,p_actor uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid;
begin
 if not exists(select 1 from public.mme_inventory_product_fingerprints where fingerprint_id=p_fingerprint_id and identity_confidence>=90 and verified_at is not null) then
  raise exception 'Verified product identity with confidence >= 90 required' using errcode='55000'; end if;
 if p_price<0 or p_shipping<0 or p_confidence not between 0 and 100 or p_currency !~ '^[A-Z]{3}$' or p_observed_at>now()+interval '5 minutes' or p_expires_at<=p_observed_at then
  raise exception 'Invalid market observation values or timestamps' using errcode='22023'; end if;
 insert into public.mme_inventory_market_observations(fingerprint_id,source_name,source_url,source_listing_reference,observed_price,currency_code,observed_condition,availability_status,shipping_cost,source_confidence,observed_at,expires_at,recorded_by)
 values(p_fingerprint_id,left(p_source_name,200),p_source_url,p_listing_reference,p_price,p_currency,p_condition,p_availability,p_shipping,p_confidence,p_observed_at,p_expires_at,p_actor)
 returning observation_id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_inventory_intelligence_generate_forecast(
 p_snapshot_id uuid,p_horizon_days integer,p_actor uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare s public.mme_inventory_demand_snapshots%rowtype; v_days numeric; v_velocity numeric; v_cover numeric; v_forecast numeric; v_reorder integer; v_conf numeric; v_id uuid;
begin
 select * into s from public.mme_inventory_demand_snapshots where demand_snapshot_id=p_snapshot_id;
 if not found or p_horizon_days not between 1 and 365 then raise exception 'Demand snapshot and valid horizon required' using errcode='22023'; end if;
 v_days:=s.window_end-s.window_start;
 v_velocity:=greatest((s.units_sold-s.units_returned)::numeric/greatest(v_days,1),0);
 v_cover:=case when v_velocity=0 then null else greatest(s.units_on_hand-s.units_reserved,0)/v_velocity end;
 v_forecast:=round(v_velocity*p_horizon_days,2);
 v_reorder:=greatest(ceil(v_forecast-(s.units_on_hand-s.units_reserved)-s.units_inbound)::integer,0);
 v_conf:=least(95,greatest(20,50+least(v_days,45)));
 insert into public.mme_inventory_demand_forecasts(sku_reference,location_reference,source_snapshot_id,daily_net_velocity,days_of_cover,forecast_horizon_days,forecast_units,suggested_reorder_quantity,confidence,forecast_method)
 values(s.sku_reference,s.location_reference,s.demand_snapshot_id,v_velocity,v_cover,p_horizon_days,v_forecast,v_reorder,v_conf,'simple_velocity') returning forecast_id into v_id;
 if v_reorder>0 then
  insert into public.mme_inventory_intelligence_alerts(sku_reference,location_reference,alert_type,severity,alert_payload,deduplication_key)
  values(s.sku_reference,s.location_reference,'reorder_suggested',case when v_cover is not null and v_cover<7 then 'critical' else 'warning' end,
  jsonb_build_object('suggested_quantity',v_reorder,'days_of_cover',v_cover,'forecast_id',v_id),
  'reorder:'||s.sku_reference||':'||s.location_reference||':'||s.window_end::text) on conflict(deduplication_key) do nothing;
 end if;
 insert into public.mme_inventory_intelligence_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'forecast',v_id,'forecast_generated',jsonb_build_object('daily_velocity',v_velocity,'days_of_cover',v_cover,'reorder_quantity',v_reorder));
 return v_id;
end; $$;

create or replace function public.mme_inventory_intelligence_create_procurement_recommendation(
 p_forecast_id uuid,p_requested_by uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare f public.mme_inventory_demand_forecasts%rowtype; s public.mme_inventory_demand_snapshots%rowtype; v_id uuid;
begin
 select * into f from public.mme_inventory_demand_forecasts where forecast_id=p_forecast_id;
 if not found or p_requested_by is null then raise exception 'Forecast and requester required' using errcode='22023'; end if;
 select * into s from public.mme_inventory_demand_snapshots where demand_snapshot_id=f.source_snapshot_id;
 insert into public.mme_inventory_procurement_recommendations(forecast_id,sku_reference,location_reference,recommended_quantity,estimated_unit_cost,estimated_total_cost,currency_code,recommendation_reason,requested_by)
 values(f.forecast_id,f.sku_reference,f.location_reference,f.suggested_reorder_quantity,s.unit_cost,
 f.suggested_reorder_quantity*s.unit_cost,s.currency_code,jsonb_build_object('forecast_confidence',f.confidence,'daily_velocity',f.daily_net_velocity,'days_of_cover',f.days_of_cover),p_requested_by)
 returning recommendation_id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_inventory_intelligence_approve_procurement(p_recommendation_id uuid,p_approver uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_inventory_procurement_recommendations%rowtype;
begin
 select * into r from public.mme_inventory_procurement_recommendations where recommendation_id=p_recommendation_id for update;
 if not found or r.approval_status<>'pending' or p_approver is null or p_approver=r.requested_by then
  raise exception 'Pending recommendation requires independent approval' using errcode='55000'; end if;
 update public.mme_inventory_procurement_recommendations set approval_status='approved',approved_by=p_approver,approved_at=now() where recommendation_id=p_recommendation_id;
 insert into public.mme_inventory_intelligence_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_approver,'procurement_recommendation',p_recommendation_id,'procurement_approved',jsonb_build_object('quantity',r.recommended_quantity,'estimated_total',r.estimated_total_cost));
end; $$;

revoke all on function public.mme_inventory_intelligence_record_market_observation(uuid,text,text,text,numeric,text,text,text,numeric,numeric,timestamptz,timestamptz,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_intelligence_generate_forecast(uuid,integer,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_intelligence_create_procurement_recommendation(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_intelligence_approve_procurement(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_intelligence_record_market_observation(uuid,text,text,text,numeric,text,text,text,numeric,numeric,timestamptz,timestamptz,uuid) to service_role;
grant execute on function public.mme_inventory_intelligence_generate_forecast(uuid,integer,uuid) to service_role;
grant execute on function public.mme_inventory_intelligence_create_procurement_recommendation(uuid,uuid) to service_role;
grant execute on function public.mme_inventory_intelligence_approve_procurement(uuid,uuid) to service_role;
commit;