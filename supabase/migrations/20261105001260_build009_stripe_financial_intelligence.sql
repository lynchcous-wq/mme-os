-- Build 009.46 — explainable Stripe financial risk intelligence.
-- Deterministic, evidence-linked risk scoring; no autonomous financial actions.
begin;

create table public.mme_pos_stripe_financial_intelligence_runs (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 as_of_date date not null,
 window_start date not null,
 window_end date not null,
 baseline_start date not null,
 baseline_end date not null,
 model_key text not null check(model_key='explainable_rules_v1'),
 source_exception_count integer not null default 0,
 source_settlement_batch_count integer not null default 0,
 risk_score integer not null check(risk_score between 0 and 100),
 risk_band text not null check(risk_band in ('low','moderate','high','critical')),
 refund_exception_rate_bps integer not null check(refund_exception_rate_bps between 0 and 10000),
 unresolved_exposure_minor bigint not null default 0,
 delayed_settlement_count integer not null default 0,
 baseline_delayed_settlement_count integer not null default 0,
 generated_by_person_id uuid not null,
 generated_at timestamptz not null default now()
);
create index mme_pos_stripe_fin_intelligence_run_idx
 on public.mme_pos_stripe_financial_intelligence_runs(location_id,currency,generated_at desc);

create table public.mme_pos_stripe_financial_intelligence_signals (
 id uuid primary key default gen_random_uuid(),
 run_id uuid not null references public.mme_pos_stripe_financial_intelligence_runs(id) on delete restrict,
 signal_code text not null,
 severity text not null check(severity in ('info','low','medium','high','critical')),
 observed_value numeric not null,
 baseline_value numeric,
 unit text not null,
 explanation text not null check(length(btrim(explanation)) between 8 and 1200),
 evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object'),
 created_at timestamptz not null default now(),
 unique(run_id,signal_code)
);
create index mme_pos_stripe_fin_intelligence_signal_idx
 on public.mme_pos_stripe_financial_intelligence_signals(run_id,severity);

create table public.mme_pos_stripe_financial_intelligence_recommendations (
 id uuid primary key default gen_random_uuid(),
 run_id uuid not null references public.mme_pos_stripe_financial_intelligence_runs(id) on delete restrict,
 recommendation_code text not null,
 priority text not null check(priority in ('low','medium','high','critical')),
 title text not null check(length(btrim(title)) between 5 and 180),
 recommendation text not null check(length(btrim(recommendation)) between 10 and 1500),
 rationale text not null check(length(btrim(rationale)) between 10 and 1500),
 requires_human_approval boolean not null default true,
 created_at timestamptz not null default now(),
 unique(run_id,recommendation_code)
);

create table public.mme_pos_stripe_financial_intelligence_decisions (
 id uuid primary key default gen_random_uuid(),
 recommendation_id uuid not null references public.mme_pos_stripe_financial_intelligence_recommendations(id) on delete restrict,
 actor_person_id uuid not null,
 action text not null check(action in ('acknowledge','assign','resolve','dismiss')),
 assignee_person_id uuid,
 reason text not null check(length(btrim(reason)) between 8 and 1500),
 evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object'),
 occurred_at timestamptz not null default now(),
 check((action='assign' and assignee_person_id is not null) or (action<>'assign' and assignee_person_id is null))
);
create index mme_pos_stripe_fin_intelligence_decisions_idx
 on public.mme_pos_stripe_financial_intelligence_decisions(recommendation_id,occurred_at desc);

alter table public.mme_pos_stripe_financial_intelligence_runs enable row level security;
alter table public.mme_pos_stripe_financial_intelligence_signals enable row level security;
alter table public.mme_pos_stripe_financial_intelligence_recommendations enable row level security;
alter table public.mme_pos_stripe_financial_intelligence_decisions enable row level security;
revoke all on public.mme_pos_stripe_financial_intelligence_runs,
 public.mme_pos_stripe_financial_intelligence_signals,
 public.mme_pos_stripe_financial_intelligence_recommendations,
 public.mme_pos_stripe_financial_intelligence_decisions from public,anon,authenticated;
grant select,insert on public.mme_pos_stripe_financial_intelligence_runs,
 public.mme_pos_stripe_financial_intelligence_signals,
 public.mme_pos_stripe_financial_intelligence_recommendations to service_role;
grant select,insert on public.mme_pos_stripe_financial_intelligence_decisions to service_role;
revoke update,delete,truncate on public.mme_pos_stripe_financial_intelligence_runs,
 public.mme_pos_stripe_financial_intelligence_signals,
 public.mme_pos_stripe_financial_intelligence_recommendations,
 public.mme_pos_stripe_financial_intelligence_decisions from service_role;

create or replace function public.mme_pos_build_stripe_financial_intelligence(
 p_location_id uuid,p_actor_person_id uuid,p_as_of_date date,p_currency text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_run uuid;
 v_current_exceptions integer:=0;
 v_baseline_exceptions integer:=0;
 v_current_batches integer:=0;
 v_delayed integer:=0;
 v_baseline_delayed integer:=0;
 v_open_exposure bigint:=0;
 v_refund_lines integer:=0;
 v_matched_refunds integer:=0;
 v_exception_rate integer:=0;
 v_score integer:=0;
 v_band text;
 v_signal uuid;
begin
 if p_location_id is null or p_actor_person_id is null or p_as_of_date is null
  or p_currency is null or p_currency !~ '^[A-Z]{3}$' then
  raise exception 'Valid location, actor, as-of date and ISO currency are required' using errcode='22023';
 end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,p_location_id,'pos.settlement.exception.manage') then
  raise exception 'Financial intelligence permission denied' using errcode='42501';
 end if;

 select count(*) into v_current_exceptions
 from public.mme_pos_stripe_settlement_exception_cases
 where location_id=p_location_id and currency=p_currency
  and first_detected_at >= p_as_of_date-29 and first_detected_at < p_as_of_date+1
  and status not in ('false_positive');
 select count(*) into v_baseline_exceptions
 from public.mme_pos_stripe_settlement_exception_cases
 where location_id=p_location_id and currency=p_currency
  and first_detected_at >= p_as_of_date-59 and first_detected_at < p_as_of_date-29
  and status not in ('false_positive');
 select count(*),coalesce(sum(abs(amount_minor)),0)::bigint
 into v_current_batches,v_open_exposure
 from public.mme_pos_stripe_settlement_exception_cases
 where location_id=p_location_id and currency=p_currency
  and status not in ('resolved','accepted_variance','false_positive');

 select count(*) into v_delayed
 from public.mme_pos_settlement_batches
 where location_id=p_location_id and provider='stripe' and currency=p_currency
  and expected_arrival_at is not null and expected_arrival_at < (p_as_of_date+1)::timestamptz
  and (settled_at is null or settled_at>expected_arrival_at)
  and imported_at >= p_as_of_date-29;
 select count(*) into v_baseline_delayed
 from public.mme_pos_settlement_batches
 where location_id=p_location_id and provider='stripe' and currency=p_currency
  and expected_arrival_at is not null and settled_at>expected_arrival_at
  and imported_at >= p_as_of_date-59 and imported_at < p_as_of_date-29;

 select count(*) into v_refund_lines
 from public.mme_pos_settlement_lines l join public.mme_pos_settlement_batches b on b.id=l.batch_id
 where b.location_id=p_location_id and b.provider='stripe' and b.currency=p_currency
  and l.line_type='refund' and l.created_at >= p_as_of_date-29 and l.created_at < p_as_of_date+1;
 select count(*) into v_matched_refunds
 from public.mme_pos_stripe_refund_settlement_matches m
 join public.mme_pos_settlement_batches b on b.id=m.settlement_batch_id
 where b.location_id=p_location_id and b.provider='stripe' and b.currency=p_currency
  and m.match_status='matched' and m.matched_at >= p_as_of_date-29 and m.matched_at < p_as_of_date+1;

 if v_refund_lines>0 then
  v_exception_rate:=greatest(0,least(10000,round((v_current_exceptions::numeric/greatest(v_refund_lines,1))*10000)::integer));
 end if;
 v_score:=least(100,
  least(35,v_current_exceptions*7)
  +least(30,case when v_open_exposure>0 then 10 else 0 end + case when v_open_exposure>=100000 then 20 else 0 end)
  +least(20,v_delayed*10)
  +least(15,case when v_baseline_exceptions>0 and v_current_exceptions>v_baseline_exceptions then 15
     when v_current_exceptions>0 then 7 else 0 end));
 v_band:=case when v_score>=75 then 'critical' when v_score>=50 then 'high'
  when v_score>=25 then 'moderate' else 'low' end;

 insert into public.mme_pos_stripe_financial_intelligence_runs(
  location_id,currency,as_of_date,window_start,window_end,baseline_start,baseline_end,
  model_key,source_exception_count,source_settlement_batch_count,risk_score,risk_band,
  refund_exception_rate_bps,unresolved_exposure_minor,delayed_settlement_count,
  baseline_delayed_settlement_count,generated_by_person_id
 ) values(p_location_id,p_currency,p_as_of_date,p_as_of_date-29,p_as_of_date,
  p_as_of_date-59,p_as_of_date-30,'explainable_rules_v1',v_current_exceptions,v_current_batches,
  v_score,v_band,v_exception_rate,v_open_exposure,v_delayed,v_baseline_delayed,p_actor_person_id)
 returning id into v_run;

 insert into public.mme_pos_stripe_financial_intelligence_signals(
  run_id,signal_code,severity,observed_value,baseline_value,unit,explanation,evidence
 ) values
 (v_run,'open_exception_volume',case when v_current_exceptions>=5 then 'high' when v_current_exceptions>0 then 'medium' else 'info' end,
  v_current_exceptions,v_baseline_exceptions,'cases','Open and recently detected Stripe settlement exceptions in the 30-day window compared with the preceding 30 days.',
  jsonb_build_object('window_days',30,'current_count',v_current_exceptions,'baseline_count',v_baseline_exceptions)),
 (v_run,'delayed_settlement_volume',case when v_delayed>=3 then 'high' when v_delayed>0 then 'medium' else 'info' end,
  v_delayed,v_baseline_delayed,'batches','Stripe batches with an expected arrival time that remain unsettled or settled after the expected time.',
  jsonb_build_object('current_delayed',v_delayed,'baseline_delayed',v_baseline_delayed)),
 (v_run,'unresolved_refund_exposure',case when v_open_exposure>=100000 then 'critical' when v_open_exposure>0 then 'medium' else 'info' end,
  v_open_exposure,null,'minor_units','Outstanding exception amount in the selected currency; this is exposure, not a confirmed loss.',
  jsonb_build_object('currency',p_currency,'minor_units',v_open_exposure)),
 (v_run,'refund_exception_rate',case when v_exception_rate>=1500 then 'high' when v_exception_rate>0 then 'medium' else 'info' end,
  v_exception_rate,null,'basis_points','Exception count divided by imported Stripe refund-line count for the period; interpret carefully when volumes are small.',
  jsonb_build_object('refund_lines',v_refund_lines,'matched_refund_lines',v_matched_refunds,'exception_count',v_current_exceptions));

 if v_current_exceptions>0 then
  insert into public.mme_pos_stripe_financial_intelligence_recommendations(
   run_id,recommendation_code,priority,title,recommendation,rationale)
  values(v_run,'review_open_refund_exceptions',case when v_band in ('critical','high') then v_band else 'medium' end,
   'Review outstanding refund exceptions',
   'Assign unresolved refund exceptions to Finance, verify provider references and settlement evidence, and document each resolution before closing the period.',
   'The selected 30-day window contains '||v_current_exceptions||' detected exceptions; outstanding exception amount is expressed in '||p_currency||' minor units.');
 end if;
 if v_delayed>0 then
  insert into public.mme_pos_stripe_financial_intelligence_recommendations(
   run_id,recommendation_code,priority,title,recommendation,rationale)
  values(v_run,'investigate_delayed_settlements',case when v_delayed>=3 then 'high' else 'medium' end,
   'Investigate delayed Stripe settlements',
   'Compare payout expected-arrival timestamps with processor status and bank statement evidence; keep processor payout and bank deposit confirmation as separate controls.',
   'The current 30-day window contains '||v_delayed||' Stripe settlement batches that are late or remain unsettled past their expected arrival.');
 end if;
 if v_score>=50 then
  insert into public.mme_pos_stripe_financial_intelligence_recommendations(
   run_id,recommendation_code,priority,title,recommendation,rationale)
  values(v_run,'executive_financial_risk_review',v_band,
   'Escalate financial risk review',
   'Request a Finance review of the underlying exception cases and settlement evidence. Do not initiate refunds, payouts, journal changes or bank transfers from this risk score.',
   'The explainable rules model calculated a risk score of '||v_score||' out of 100 using exception volume, unresolved exposure, delayed batches and change from the prior period.');
 end if;
 return v_run;
end;
$$;

create or replace function public.mme_pos_record_stripe_financial_intelligence_decision(
 p_recommendation_id uuid,p_actor_person_id uuid,p_action text,p_reason text,p_assignee_person_id uuid default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_rec public.mme_pos_stripe_financial_intelligence_recommendations%rowtype;
 v_run public.mme_pos_stripe_financial_intelligence_runs%rowtype; v_id uuid;
begin
 select * into v_rec from public.mme_pos_stripe_financial_intelligence_recommendations
  where id=p_recommendation_id;
 if not found then raise exception 'Financial intelligence recommendation not found' using errcode='P0002'; end if;
 select * into v_run from public.mme_pos_stripe_financial_intelligence_runs where id=v_rec.run_id;
 if p_action not in ('acknowledge','assign','resolve','dismiss')
  or length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'Valid decision action and documented reason are required' using errcode='22023';
 end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_run.location_id,'pos.settlement.exception.manage') then
  raise exception 'Financial intelligence decision permission denied' using errcode='42501';
 end if;
 if p_action='assign' then
  if p_assignee_person_id is null or not exists(select 1 from public.mme_person_identities i
   join public.employee_relationships e on e.person_id=i.person_id
   where i.person_id=p_assignee_person_id and i.lifecycle_status='active' and e.employment_status='active') then
   raise exception 'Active employee assignee required' using errcode='22023';
  end if;
 elsif p_assignee_person_id is not null then
  raise exception 'Assignee is only valid for assign action' using errcode='22023';
 end if;
 if p_action in ('resolve','dismiss') and v_rec.priority='critical'
  and not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_run.location_id,'pos.settlement.approve') then
  raise exception 'Critical recommendation requires settlement approval permission' using errcode='42501';
 end if;
 insert into public.mme_pos_stripe_financial_intelligence_decisions(
  recommendation_id,actor_person_id,action,assignee_person_id,reason)
 values(p_recommendation_id,p_actor_person_id,p_action,p_assignee_person_id,p_reason)
 returning id into v_id;
 return v_id;
end;
$$;

create or replace view public.mme_pos_stripe_financial_intelligence_dashboard
with (security_invoker=true) as
select distinct on (r.location_id,r.currency)
 r.location_id,r.currency,r.id run_id,r.as_of_date,r.risk_score,r.risk_band,
 r.refund_exception_rate_bps,r.unresolved_exposure_minor,r.delayed_settlement_count,
 r.baseline_delayed_settlement_count,r.generated_at
from public.mme_pos_stripe_financial_intelligence_runs r
order by r.location_id,r.currency,r.generated_at desc;

revoke all on function public.mme_pos_build_stripe_financial_intelligence(uuid,uuid,date,text) from public,anon,authenticated;
revoke all on function public.mme_pos_record_stripe_financial_intelligence_decision(uuid,uuid,text,text,uuid) from public,anon,authenticated;
revoke all on public.mme_pos_stripe_financial_intelligence_dashboard from public,anon,authenticated;
grant execute on function public.mme_pos_build_stripe_financial_intelligence(uuid,uuid,date,text) to service_role;
grant execute on function public.mme_pos_record_stripe_financial_intelligence_decision(uuid,uuid,text,text,uuid) to service_role;
grant select on public.mme_pos_stripe_financial_intelligence_dashboard to service_role;

comment on table public.mme_pos_stripe_financial_intelligence_runs is
 'Immutable, explainable 30-day Stripe financial risk snapshots; scores are decision support and not predictions of loss.';
comment on view public.mme_pos_stripe_financial_intelligence_dashboard is
 'Latest location and currency risk snapshot for authorized Finance and CEO reporting.';

commit;
