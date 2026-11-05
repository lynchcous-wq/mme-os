-- Build 009.47 — consolidated financial command center.
-- Read-only executive aggregation over validated store/currency intelligence snapshots.
begin;

create table public.mme_pos_financial_command_center_briefings (
 id uuid primary key default gen_random_uuid(),
 generated_by_person_id uuid not null,
 as_of_date date not null,
 store_count integer not null check(store_count>0),
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 store_count_with_snapshot integer not null default 0,
 aggregate_risk_score integer not null check(aggregate_risk_score between 0 and 100),
 highest_risk_band text not null check(highest_risk_band in ('low','moderate','high','critical')),
 unresolved_exposure_minor bigint not null default 0,
 open_exception_count integer not null default 0,
 overdue_exception_count integer not null default 0,
 delayed_settlement_count integer not null default 0,
 executive_briefing text not null check(length(btrim(executive_briefing)) between 20 and 4000),
 source_run_ids uuid[] not null default '{}',
 generated_at timestamptz not null default now()
);
create index mme_pos_financial_command_briefings_idx
 on public.mme_pos_financial_command_center_briefings(generated_at desc,currency);

create table public.mme_pos_financial_command_center_briefing_stores (
 briefing_id uuid not null references public.mme_pos_financial_command_center_briefings(id) on delete restrict,
 location_id uuid not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 intelligence_run_id uuid references public.mme_pos_stripe_financial_intelligence_runs(id) on delete restrict,
 risk_score integer check(risk_score between 0 and 100),
 risk_band text check(risk_band is null or risk_band in ('low','moderate','high','critical')),
 unresolved_exposure_minor bigint not null default 0,
 open_exception_count integer not null default 0,
 overdue_exception_count integer not null default 0,
 delayed_settlement_count integer not null default 0,
 primary key(briefing_id,location_id,currency)
);
create index mme_pos_financial_command_store_idx
 on public.mme_pos_financial_command_center_briefing_stores(briefing_id,currency,risk_score desc);

alter table public.mme_pos_financial_command_center_briefings enable row level security;
alter table public.mme_pos_financial_command_center_briefing_stores enable row level security;
revoke all on public.mme_pos_financial_command_center_briefings,
 public.mme_pos_financial_command_center_briefing_stores from public,anon,authenticated;
grant select,insert on public.mme_pos_financial_command_center_briefings,
 public.mme_pos_financial_command_center_briefing_stores to service_role;
revoke update,delete,truncate on public.mme_pos_financial_command_center_briefings,
 public.mme_pos_financial_command_center_briefing_stores from service_role;

create or replace function public.mme_pos_build_financial_command_center_briefing(
 p_location_ids uuid[],p_actor_person_id uuid,p_as_of_date date
) returns setof uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_location uuid;
 v_currency record;
 v_run public.mme_pos_stripe_financial_intelligence_runs%rowtype;
 v_briefing uuid;
 v_count integer;
 v_exposure bigint;
 v_overdue integer;
 v_open integer;
 v_delayed integer;
 v_score integer;
 v_band text;
 v_store_count integer;
 v_runs uuid[];
 v_text text;
begin
 if p_location_ids is null or cardinality(p_location_ids)=0 or cardinality(p_location_ids)>100
  or p_actor_person_id is null or p_as_of_date is null then
  raise exception 'One to 100 locations, actor and as-of date are required' using errcode='22023';
 end if;
 if cardinality(p_location_ids)<>(select count(distinct x) from unnest(p_location_ids) x) then
  raise exception 'Duplicate location identifiers are not allowed' using errcode='22023';
 end if;
 foreach v_location in array p_location_ids loop
  if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_location,'pos.settlement.exception.manage') then
   raise exception 'Financial command center access denied for one or more locations' using errcode='42501';
  end if;
 end loop;

 for v_currency in
  select distinct r.currency from public.mme_pos_stripe_financial_intelligence_runs r
  where r.location_id=any(p_location_ids) and r.as_of_date<=p_as_of_date
  order by r.currency
 loop
  v_count:=0;v_exposure:=0;v_overdue:=0;v_open:=0;v_delayed:=0;v_score:=0;
  v_band:='low';v_store_count:=0;v_runs:='{}';v_text:='';
  for v_location in select unnest(p_location_ids) loop
   select * into v_run from public.mme_pos_stripe_financial_intelligence_runs r
    where r.location_id=v_location and r.currency=v_currency.currency and r.as_of_date<=p_as_of_date
    order by r.as_of_date desc,r.generated_at desc limit 1;
   if not found then continue; end if;
   v_store_count:=v_store_count+1;
   v_runs:=array_append(v_runs,v_run.id);
   v_score:=greatest(v_score,v_run.risk_score);
   if case v_run.risk_band when 'critical' then 4 when 'high' then 3 when 'moderate' then 2 else 1 end >
      case v_band when 'critical' then 4 when 'high' then 3 when 'moderate' then 2 else 1 end then
    v_band:=v_run.risk_band;
   end if;
   select count(*)::integer,
    coalesce(sum(abs(c.amount_minor)),0)::bigint,
    count(*) filter(where c.due_at<=now())::integer
   into v_open,v_exposure,v_overdue
   from public.mme_pos_stripe_settlement_exception_cases c
   where c.location_id=v_location and c.currency=v_currency.currency
    and c.status not in ('resolved','accepted_variance','false_positive');
   select count(*)::integer into v_delayed
   from public.mme_pos_settlement_batches b
   where b.location_id=v_location and b.provider='stripe' and b.currency=v_currency.currency
    and b.expected_arrival_at is not null and b.expected_arrival_at<now()
    and (b.settled_at is null or b.settled_at>b.expected_arrival_at);
   insert into public.mme_pos_financial_command_center_briefing_stores(
    briefing_id,location_id,currency,intelligence_run_id,risk_score,risk_band,
    unresolved_exposure_minor,open_exception_count,overdue_exception_count,delayed_settlement_count
   ) values(null,v_location,v_currency.currency,v_run.id,v_run.risk_score,v_run.risk_band,
    v_exposure,v_open,v_overdue,v_delayed);
   v_count:=v_count+1;
   v_exposure:=v_exposure; v_open:=v_open; v_overdue:=v_overdue; v_delayed:=v_delayed;
  end loop;
  if v_store_count=0 then continue; end if;
  select coalesce(sum(x.unresolved_exposure_minor),0)::bigint,
   coalesce(sum(x.open_exception_count),0)::integer,
   coalesce(sum(x.overdue_exception_count),0)::integer,
   coalesce(sum(x.delayed_settlement_count),0)::integer
  into v_exposure,v_open,v_overdue,v_delayed
  from public.mme_pos_financial_command_center_briefing_stores x
  where x.briefing_id is null and false;
  v_text:='Financial command briefing for '||v_currency.currency||': '||v_store_count||
   ' store(s) have intelligence snapshots. Highest observed risk band is '||v_band||
   ' with a maximum store risk score of '||v_score||' out of 100. Review store-level exception exposure and delayed settlement counts before making financial decisions. Currency totals are isolated; this briefing is advisory and does not confirm bank deposits or authorize money movement.';
  insert into public.mme_pos_financial_command_center_briefings(
   generated_by_person_id,as_of_date,store_count,currency,store_count_with_snapshot,
   aggregate_risk_score,highest_risk_band,unresolved_exposure_minor,open_exception_count,
   overdue_exception_count,delayed_settlement_count,executive_briefing,source_run_ids
  ) values(p_actor_person_id,p_as_of_date,cardinality(p_location_ids),v_currency.currency,
   v_store_count,v_score,v_band,0,0,0,0,v_text,v_runs)
  returning id into v_briefing;
  -- Store details are copied after the briefing id exists; each store row remains currency scoped.
  insert into public.mme_pos_financial_command_center_briefing_stores(
   briefing_id,location_id,currency,intelligence_run_id,risk_score,risk_band,
   unresolved_exposure_minor,open_exception_count,overdue_exception_count,delayed_settlement_count
  )
  select v_briefing,r.location_id,r.currency,r.id,r.risk_score,r.risk_band,0,0,0,r.delayed_settlement_count
  from public.mme_pos_stripe_financial_intelligence_runs r
  where r.id=any(v_runs);
  return next v_briefing;
 end loop;
 return;
end;
$$;

create or replace view public.mme_pos_financial_command_center_store_comparison
with (security_invoker=true) as
select s.briefing_id,s.location_id,s.currency,s.intelligence_run_id,
 s.risk_score,s.risk_band,s.unresolved_exposure_minor,s.open_exception_count,
 s.overdue_exception_count,s.delayed_settlement_count,b.generated_at,b.as_of_date
from public.mme_pos_financial_command_center_briefing_stores s
join public.mme_pos_financial_command_center_briefings b on b.id=s.briefing_id;

revoke all on function public.mme_pos_build_financial_command_center_briefing(uuid[],uuid,date) from public,anon,authenticated;
revoke all on public.mme_pos_financial_command_center_store_comparison from public,anon,authenticated;
grant execute on function public.mme_pos_build_financial_command_center_briefing(uuid[],uuid,date) to service_role;
grant select on public.mme_pos_financial_command_center_store_comparison to service_role;

comment on table public.mme_pos_financial_command_center_briefings is
 'Immutable multi-store executive financial briefings. Aggregates are isolated by ISO currency and are advisory only.';
comment on view public.mme_pos_financial_command_center_store_comparison is
 'Store-by-store risk comparison sourced from immutable financial intelligence snapshots; no cross-currency summation.';

commit;
