-- Build 001: normalize loss-prevention signals and provide auditable shrinkage pattern summaries.
create table public.mme_inventory_shrinkage_signals (
 id uuid primary key default gen_random_uuid(),
 source_type text not null check(source_type in ('cycle_count_variance','receiving_variance','inventory_adjustment','damage_inspection','return_inspection','pos_void','pos_refund','serialized_mismatch','manual_review')),
 source_id uuid not null,
 location_id uuid references public.mme_store_locations(id) on delete restrict,
 product_id uuid references public.mme_products(id) on delete restrict,
 signal_status text not null default 'open' check(signal_status in ('open','reviewed','dismissed','linked_to_case')),
 severity text not null check(severity in ('low','medium','high','critical')),
 quantity_delta integer,
 estimated_loss_cents bigint check(estimated_loss_cents is null or estimated_loss_cents>=0),
 evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object'),
 observed_at timestamptz not null default now(),
 recorded_by_identity_id uuid not null,
 reviewed_by_identity_id uuid,
 reviewed_at timestamptz,
 review_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(source_type,source_id)
);
create index mme_shrinkage_signals_pattern_idx
 on public.mme_inventory_shrinkage_signals(location_id,product_id,observed_at desc);
create index mme_shrinkage_signals_open_idx
 on public.mme_inventory_shrinkage_signals(severity,observed_at desc) where signal_status='open';
alter table public.mme_inventory_shrinkage_signals enable row level security;
revoke all on public.mme_inventory_shrinkage_signals from public,anon,authenticated;
grant all on public.mme_inventory_shrinkage_signals to service_role;

create or replace function public.mme_record_inventory_shrinkage_signal(
 p_source_type text,p_source_id uuid,p_location_id uuid,p_product_id uuid,
 p_severity text,p_quantity_delta integer,p_estimated_loss_cents bigint,
 p_evidence jsonb,p_observed_at timestamptz,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if p_source_type not in ('cycle_count_variance','receiving_variance','inventory_adjustment','damage_inspection','return_inspection','pos_void','pos_refund','serialized_mismatch','manual_review')
  or p_source_id is null or p_severity not in ('low','medium','high','critical')
  or p_estimated_loss_cents is not null and p_estimated_loss_cents<0
  or p_evidence is null or jsonb_typeof(p_evidence)<>'object'
  or pg_column_size(p_evidence)>16384 or p_actor_identity_id is null then
  raise exception 'Invalid shrinkage signal' using errcode='22023';
 end if;
 if p_location_id is not null and not exists(select 1 from public.mme_store_locations where id=p_location_id) then
  raise exception 'Unknown shrinkage location' using errcode='P0002'; end if;
 if p_product_id is not null and not exists(select 1 from public.mme_products where id=p_product_id) then
  raise exception 'Unknown shrinkage product' using errcode='P0002'; end if;
 insert into public.mme_inventory_shrinkage_signals(source_type,source_id,location_id,product_id,
  severity,quantity_delta,estimated_loss_cents,evidence,observed_at,recorded_by_identity_id)
 values(p_source_type,p_source_id,p_location_id,p_product_id,p_severity,p_quantity_delta,
  p_estimated_loss_cents,p_evidence,coalesce(p_observed_at,now()),p_actor_identity_id)
 on conflict(source_type,source_id) do update set
  severity=case when array_position(array['low','medium','high','critical'],excluded.severity)>
   array_position(array['low','medium','high','critical'],mme_inventory_shrinkage_signals.severity)
   then excluded.severity else mme_inventory_shrinkage_signals.severity end,
  evidence=excluded.evidence,updated_at=now()
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_review_inventory_shrinkage_signal(
 p_signal_id uuid,p_actor_identity_id uuid,p_decision text,p_note text
) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_signal_id is null or p_actor_identity_id is null or p_decision not in ('reviewed','dismissed')
  or p_note is null or length(btrim(p_note)) not between 5 and 1000 then
  raise exception 'Invalid shrinkage signal review' using errcode='22023'; end if;
 update public.mme_inventory_shrinkage_signals set signal_status=p_decision,
  reviewed_by_identity_id=p_actor_identity_id,reviewed_at=now(),review_note=btrim(p_note),updated_at=now()
 where id=p_signal_id and signal_status='open';
 return found;
end; $$;

create or replace view public.mme_inventory_shrinkage_patterns_v
with (security_invoker=true) as
select location_id,product_id,count(*)::integer as signal_count,
 count(*) filter(where severity in ('high','critical'))::integer as high_severity_signal_count,
 count(distinct source_type)::integer as distinct_signal_sources,
 sum(coalesce(estimated_loss_cents,0))::bigint as estimated_loss_cents,
 min(observed_at) as first_observed_at,max(observed_at) as last_observed_at
from public.mme_inventory_shrinkage_signals
where observed_at>=now()-interval '30 days' and signal_status<>'dismissed'
group by location_id,product_id
having count(*)>=2;
revoke all on public.mme_inventory_shrinkage_patterns_v from public,anon,authenticated;
grant select on public.mme_inventory_shrinkage_patterns_v to service_role;

revoke all on function public.mme_record_inventory_shrinkage_signal(text,uuid,uuid,uuid,text,integer,bigint,jsonb,timestamp with time zone,uuid) from public,anon,authenticated;
revoke all on function public.mme_review_inventory_shrinkage_signal(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_record_inventory_shrinkage_signal(text,uuid,uuid,uuid,text,integer,bigint,jsonb,timestamp with time zone,uuid) to service_role;
grant execute on function public.mme_review_inventory_shrinkage_signal(uuid,uuid,text,text) to service_role;
comment on table public.mme_inventory_shrinkage_signals is 'Source-linked inventory loss prevention signals; evidence remains auditable and does not itself adjust stock.';
comment on view public.mme_inventory_shrinkage_patterns_v is '30-day recurring signal summaries by location and product; requires two or more signals and is an investigative indicator, not a fraud finding.';
