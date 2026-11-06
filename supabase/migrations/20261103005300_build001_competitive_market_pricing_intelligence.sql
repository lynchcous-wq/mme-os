-- Build 001: sourced competitor observations and condition-matched market positioning; no automatic repricing.
create table public.mme_market_price_observations (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.mme_products(id) on delete restrict,
 condition_grade text not null,
 observed_price_cents bigint not null check(observed_price_cents>0),
 currency_code text not null default 'USD' check(currency_code='USD'),
 seller_label text not null check(length(btrim(seller_label)) between 1 and 160),
 source_url text not null check(source_url ~ '^https?://'),
 source_listing_ref text,
 match_confidence numeric(5,2) not null check(match_confidence between 0 and 100),
 observed_at timestamptz not null,
 captured_at timestamptz not null default now(),
 source_type text not null check(source_type in ('manual','approved_feed','marketplace_export')),
 verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected')),
 verified_by_identity_id uuid,
 verified_at timestamptz,
 notes text,
 check(observed_at<=captured_at+interval '5 minutes')
);
create index mme_market_observations_product_condition_time_idx
 on public.mme_market_price_observations(product_id,condition_grade,observed_at desc)
 where verification_status='verified';
alter table public.mme_market_price_observations enable row level security;
revoke all on public.mme_market_price_observations from public,anon,authenticated;
grant all on public.mme_market_price_observations to service_role;

create or replace function public.mme_record_market_price_observation(
 p_product_id uuid,p_condition_grade text,p_observed_price_cents bigint,p_seller_label text,
 p_source_url text,p_match_confidence numeric,p_observed_at timestamptz,
 p_source_type text,p_actor_identity_id uuid,p_source_listing_ref text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if p_product_id is null or p_actor_identity_id is null or p_condition_grade is null
  or p_observed_price_cents is null or p_observed_price_cents<=0
  or p_seller_label is null or length(btrim(p_seller_label)) not between 1 and 160
  or p_source_url is null or p_source_url !~ '^https?://'
  or p_match_confidence is null or p_match_confidence not between 0 and 100
  or p_observed_at is null or p_observed_at>now()+interval '5 minutes'
  or p_source_type not in ('manual','approved_feed','marketplace_export') then
  raise exception 'Invalid market price observation' using errcode='22023';
 end if;
 if not exists(select 1 from public.mme_products where id=p_product_id and active=true) then
  raise exception 'Active product not found' using errcode='P0002';
 end if;
 insert into public.mme_market_price_observations(product_id,condition_grade,observed_price_cents,
  seller_label,source_url,source_listing_ref,match_confidence,observed_at,source_type,notes)
 values(p_product_id,left(btrim(p_condition_grade),60),p_observed_price_cents,
  btrim(p_seller_label),p_source_url,left(p_source_listing_ref,240),p_match_confidence,
  p_observed_at,p_source_type,'Awaiting independent source and product-match verification.')
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_verify_market_price_observation(
 p_observation_id uuid,p_verifier_identity_id uuid,p_approve boolean,p_note text default null
) returns boolean language plpgsql security definer set search_path='' as $$
declare v public.mme_market_price_observations%rowtype;
begin
 if p_observation_id is null or p_verifier_identity_id is null or p_approve is null then
  raise exception 'Invalid market observation decision' using errcode='22023'; end if;
 select * into v from public.mme_market_price_observations where id=p_observation_id for update;
 if not found or v.verification_status<>'pending' then return false; end if;
 if v.verified_by_identity_id=p_verifier_identity_id then
  raise exception 'Observer cannot verify own market evidence' using errcode='42501'; end if;
 update public.mme_market_price_observations set
  verification_status=case when p_approve then 'verified' else 'rejected' end,
  verified_by_identity_id=p_verifier_identity_id,verified_at=now(),
  notes=coalesce(left(p_note,1000),notes)
 where id=p_observation_id;
 return true;
end; $$;

create or replace view public.mme_market_price_position_v
with (security_invoker=true) as
with comparable as (
 select o.product_id,o.condition_grade,count(*)::bigint as verified_observation_count,
  percentile_cont(0.5) within group(order by o.observed_price_cents)::numeric as market_median_price_cents,
  min(o.observed_price_cents)::bigint as market_low_price_cents,
  max(o.observed_price_cents)::bigint as market_high_price_cents,
  max(o.observed_at) as latest_observation_at,
  count(*) filter(where o.observed_at>=now()-interval '30 days')::bigint as observations_30d
 from public.mme_market_price_observations o
 where o.verification_status='verified' and o.match_confidence>=90
  and o.observed_at>=now()-interval '90 days'
 group by o.product_id,o.condition_grade
)
select p.id as product_id,p.sku,p.title,p.condition_grade,p.unit_price_cents as mme_current_price_cents,
 c.verified_observation_count,c.market_median_price_cents,c.market_low_price_cents,
 c.market_high_price_cents,c.latest_observation_at,c.observations_30d,
 round(100.0*(p.unit_price_cents-c.market_median_price_cents)/nullif(c.market_median_price_cents,0),2) as mme_price_vs_market_median_percent,
 case when c.latest_observation_at<now()-interval '30 days' then 'stale'
  when c.verified_observation_count<3 then 'insufficient_comparables'
  when p.unit_price_cents>c.market_median_price_cents*1.10 then 'above_market'
  when p.unit_price_cents<c.market_median_price_cents*0.90 then 'below_market'
  else 'near_market' end as price_position,
 now() as calculated_at
from comparable c join public.mme_products p on p.id=c.product_id
 and lower(p.condition_grade)=lower(c.condition_grade) and p.active=true;

revoke all on function public.mme_record_market_price_observation(uuid,text,bigint,text,text,numeric,timestamptz,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_verify_market_price_observation(uuid,uuid,boolean,text) from public,anon,authenticated;
revoke all on public.mme_market_price_position_v from public,anon,authenticated;
grant execute on function public.mme_record_market_price_observation(uuid,text,bigint,text,text,numeric,timestamptz,text,uuid,text) to service_role;
grant execute on function public.mme_verify_market_price_observation(uuid,uuid,boolean,text) to service_role;
grant select on public.mme_market_price_position_v to service_role;
comment on view public.mme_market_price_position_v is 'Condition-matched market position from independently verified observations with at least 90% match confidence and age no more than 90 days. Fewer than three comparables or evidence older than 30 days is explicitly flagged. Informational only; does not change MME price.';
