-- Build 009.71 — warranty analytics, KPI facts and versioned executive snapshots.
begin;
create table public.mme_warranty_analytics_kpi_facts (
 fact_id uuid primary key default gen_random_uuid(),
 metric_code text not null,
 period_start date not null,
 period_end date not null,
 product_category text not null default 'all',
 provider_id uuid references public.mme_warranty_providers(provider_id) on delete restrict,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 realization text not null check(realization in ('actual','projection')),
 metric_value numeric(20,4) not null,
 unit_code text not null check(unit_code in ('count','currency','ratio','minutes','percent')),
 numerator numeric(20,4),
 denominator numeric(20,4),
 source_system text not null,
 source_reference text not null,
 model_version text,
 recorded_by uuid not null,
 recorded_at timestamptz not null default now(),
 idempotency_key text not null unique,
 check(period_end>=period_start),
 check(realization<>'projection' or model_version is not null),
 check(denominator is null or denominator>0)
);
create index mme_warranty_analytics_facts_period_idx on public.mme_warranty_analytics_kpi_facts(metric_code,period_start,period_end,realization,currency_code);
create index mme_warranty_analytics_facts_provider_idx on public.mme_warranty_analytics_kpi_facts(provider_id,metric_code,period_start desc);

create table public.mme_warranty_analytics_snapshots (
 snapshot_id uuid primary key default gen_random_uuid(),
 as_of_date date not null,
 period_start date not null,
 period_end date not null,
 metric_code text not null,
 product_category text not null,
 provider_id uuid references public.mme_warranty_providers(provider_id) on delete restrict,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 actual_value numeric(20,4),
 projected_value numeric(20,4),
 unit_code text not null check(unit_code in ('count','currency','ratio','minutes','percent')),
 numerator_actual numeric(20,4),
 denominator_actual numeric(20,4),
 model_version text,
 source_fact_count integer not null check(source_fact_count>=0),
 generated_by uuid not null,
 generated_at timestamptz not null default now(),
 unique(as_of_date,period_start,period_end,metric_code,product_category,provider_id,currency_code),
 check(period_end>=period_start),
 check(denominator_actual is null or denominator_actual>0)
);
create index mme_warranty_analytics_snapshots_date_idx on public.mme_warranty_analytics_snapshots(as_of_date desc,metric_code);

create table public.mme_warranty_analytics_forecast_assumptions (
 assumption_id uuid primary key default gen_random_uuid(),
 metric_code text not null,
 product_category text not null,
 provider_id uuid references public.mme_warranty_providers(provider_id) on delete restrict,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 assumption_value numeric(20,6) not null,
 unit_code text not null,
 effective_from date not null,
 effective_to date,
 model_version text not null,
 rationale text not null,
 approved_by uuid not null,
 created_at timestamptz not null default now(),
 check(effective_to is null or effective_to>=effective_from)
);
create index mme_warranty_analytics_assumptions_idx on public.mme_warranty_analytics_forecast_assumptions(metric_code,product_category,effective_from desc);

create table public.mme_warranty_analytics_scorecards (
 scorecard_id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.mme_warranty_providers(provider_id) on delete restrict,
 period_start date not null,
 period_end date not null,
 response_sla_pct numeric(7,4),
 average_response_minutes numeric(16,4),
 reimbursement_match_pct numeric(7,4),
 claim_decision_count bigint not null default 0 check(claim_decision_count>=0),
 late_response_count bigint not null default 0 check(late_response_count>=0),
 unavailable_event_count bigint not null default 0 check(unavailable_event_count>=0),
 source_snapshot_ids uuid[] not null default '{}',
 generated_at timestamptz not null default now(),
 model_version text not null,
 unique(provider_id,period_start,period_end,model_version),
 check(period_end>=period_start),
 check(response_sla_pct is null or response_sla_pct between 0 and 100),
 check(reimbursement_match_pct is null or reimbursement_match_pct between 0 and 100)
);

alter table public.mme_warranty_analytics_kpi_facts enable row level security;
alter table public.mme_warranty_analytics_snapshots enable row level security;
alter table public.mme_warranty_analytics_forecast_assumptions enable row level security;
alter table public.mme_warranty_analytics_scorecards enable row level security;
revoke all on public.mme_warranty_analytics_kpi_facts,public.mme_warranty_analytics_snapshots,public.mme_warranty_analytics_forecast_assumptions,public.mme_warranty_analytics_scorecards from public,anon,authenticated;
grant select,insert on public.mme_warranty_analytics_kpi_facts to service_role;
grant select,insert on public.mme_warranty_analytics_snapshots,public.mme_warranty_analytics_scorecards to service_role;
grant select,insert,update on public.mme_warranty_analytics_forecast_assumptions to service_role;

create or replace view public.mme_warranty_financial_analytics_v as
select entry_type,realization,currency_code,date_trunc('month',effective_at)::date as period_start,
       count(*)::bigint as entry_count,sum(amount)::numeric(18,2) as total_amount
from public.mme_warranty_financial_entries
group by entry_type,realization,currency_code,date_trunc('month',effective_at)::date;

create or replace view public.mme_warranty_lifecycle_analytics_v as
select date_trunc('month',occurred_at)::date as period_start,event_type,count(*)::bigint as event_count
from public.mme_warranty_lifecycle_events
group by date_trunc('month',occurred_at)::date,event_type;

create or replace view public.mme_warranty_provider_sla_analytics_v as
select provider_id,date_trunc('month',occurred_at)::date as period_start,
 count(*) filter(where event_type='response_received')::bigint as responses,
 count(*) filter(where event_type='response_late')::bigint as late_responses,
 count(*) filter(where event_type='provider_unavailable')::bigint as unavailable_events,
 avg(elapsed_minutes) filter(where event_type='response_received') as average_response_minutes
from public.mme_warranty_provider_sla_events
group by provider_id,date_trunc('month',occurred_at)::date;

commit;