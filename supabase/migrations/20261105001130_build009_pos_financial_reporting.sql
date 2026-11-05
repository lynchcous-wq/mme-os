-- Build 009.32 — POS Financial Reporting & Profitability Intelligence
-- Append-only, source-attributed financial facts and reproducible reporting snapshots.
begin;

create or replace function public.mme_pos_authorize_hardware_action(
 p_actor_person_id uuid,p_permission_key text,p_location_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_person_status text; v_ceo_person_id uuid; v_frozen boolean; v_employment_status text;
begin
 if p_actor_person_id is null or p_location_id is null or p_permission_key not in (
  'pos.hardware.register','pos.hardware.command','pos.hardware.incident.view',
  'pos.hardware.incident.acknowledge','pos.hardware.incident.resolve','pos.hardware.admin',
  'pos.hardware.assign','pos.hardware.configure','pos.hardware.approve','pos.hardware.retire',
  'pos.network.view','pos.network.manage','pos.network.certificates','pos.network.incidents',
  'pos.security.view','pos.security.manage','pos.security.investigate','pos.security.contain','pos.security.rules.manage',
  'pos.fraud.view','pos.fraud.review','pos.fraud.rules.manage','pos.fraud.case.manage','pos.fraud.override',
  'pos.disputes.view','pos.disputes.manage','pos.disputes.evidence','pos.disputes.approve','pos.disputes.submit',
  'pos.settlement.view','pos.settlement.reconcile','pos.settlement.exception.manage','pos.settlement.approve',
  'pos.settlement.bank.match','pos.settlement.cash.manage','pos.settlement.close.prepare','pos.settlement.close.approve',
  'pos.settlement.adjustment.request','pos.finance.report.view','pos.finance.report.build','pos.finance.report.import'
 ) then return false; end if;
 select lifecycle_status into v_person_status from public.mme_person_identities where person_id=p_actor_person_id;
 if not found or v_person_status is distinct from 'active' then return false; end if;
 select ceo_person_id,employee_access_frozen into v_ceo_person_id,v_frozen from public.employee_security_settings where singleton=true;
 if not found or v_frozen is distinct from false or v_ceo_person_id is null then return false; end if;
 select employment_status into v_employment_status from public.employee_relationships where person_id=p_actor_person_id;
 if v_employment_status is distinct from 'active' then return false; end if;
 if p_actor_person_id=v_ceo_person_id then return true; end if;
 return exists(select 1 from public.employee_permission_grants g where g.person_id=p_actor_person_id
  and g.permission_key=p_permission_key and g.revoked_at is null and (g.expires_at is null or g.expires_at>now())
  and (g.scope='{}'::jsonb or g.scope->>'location_id'=p_location_id::text));
end;
$$;

create table public.mme_pos_financial_reporting_facts (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 source_system text not null check(source_system in ('pos','payments','inventory','subscriptions','manual_import')),
 source_line_reference text not null check(length(btrim(source_line_reference)) between 1 and 200),
 fact_type text not null check(fact_type in ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment')),
 business_date date not null,
 occurred_at timestamptz not null,
 business_timezone text not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 amount_minor bigint not null,
 quantity_milli bigint,
 product_category text check(product_category is null or length(product_category)<=120),
 sku_reference text check(sku_reference is null or length(sku_reference)<=160),
 register_reference text check(register_reference is null or length(register_reference)<=120),
 employee_person_id uuid,
 source_transaction_reference text check(source_transaction_reference is null or length(source_transaction_reference)<=200),
 source_digest_sha256 text check(source_digest_sha256 is null or source_digest_sha256 ~ '^[a-f0-9]{64}$'),
 imported_by_person_id uuid not null,
 imported_at timestamptz not null default now(),
 unique(location_id,source_system,source_line_reference,fact_type),
 check((fact_type in ('gross_sale','subscription_revenue','sales_tax') and amount_minor>=0)
  or (fact_type in ('discount','refund','cost_of_goods_sold','processor_fee','chargeback') and amount_minor<=0)
  or fact_type in ('cash_over_short','inventory_adjustment'))
);
create index mme_pos_financial_facts_period_idx on public.mme_pos_financial_reporting_facts(location_id,currency,business_date,fact_type);
create index mme_pos_financial_facts_category_idx on public.mme_pos_financial_reporting_facts(location_id,business_date,product_category);
create index mme_pos_financial_facts_employee_idx on public.mme_pos_financial_reporting_facts(location_id,business_date,employee_person_id);

create table public.mme_pos_financial_report_runs (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 period_start date not null,
 period_end date not null,
 business_timezone text not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 status text not null check(status in ('provisional','closed_period_snapshot')),
 source_fact_count bigint not null default 0 check(source_fact_count>=0),
 built_by_person_id uuid not null,
 built_at timestamptz not null default now(),
 source_cutoff_at timestamptz not null default now(),
 unique(location_id,period_start,period_end,currency,source_cutoff_at),
 check(period_end>=period_start)
);
create index mme_pos_financial_report_runs_idx on public.mme_pos_financial_report_runs(location_id,built_at desc);

create table public.mme_pos_financial_report_rows (
 id uuid primary key default gen_random_uuid(),
 report_run_id uuid not null references public.mme_pos_financial_report_runs(id) on delete restrict,
 business_date date not null,
 grouping_level text not null check(grouping_level in ('store','product_category','register','employee')),
 grouping_reference text,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 gross_sales_minor bigint not null default 0,
 discounts_minor bigint not null default 0,
 refunds_minor bigint not null default 0,
 subscription_revenue_minor bigint not null default 0,
 net_sales_minor bigint not null default 0,
 sales_tax_minor bigint not null default 0,
 cost_of_goods_sold_minor bigint not null default 0,
 processor_fees_minor bigint not null default 0,
 chargebacks_minor bigint not null default 0,
 cash_over_short_minor bigint not null default 0,
 inventory_adjustments_minor bigint not null default 0,
 gross_profit_minor bigint not null default 0,
 contribution_profit_minor bigint not null default 0,
 source_fact_count bigint not null default 0,
 unique(report_run_id,business_date,grouping_level,grouping_reference)
);
create index mme_pos_financial_report_rows_run_idx on public.mme_pos_financial_report_rows(report_run_id,business_date,grouping_level);

create table public.mme_pos_financial_report_summaries (
 report_run_id uuid primary key references public.mme_pos_financial_report_runs(id) on delete restrict,
 settlement_net_minor bigint not null default 0,
 settlement_fee_minor bigint not null default 0,
 matched_bank_deposit_minor bigint not null default 0,
 cash_expected_minor bigint not null default 0,
 cash_counted_minor bigint not null default 0,
 cash_variance_minor bigint not null default 0,
 open_settlement_exception_count integer not null default 0,
 unreconciled_batch_count integer not null default 0,
 created_at timestamptz not null default now()
);

alter table public.mme_pos_financial_reporting_facts enable row level security;
alter table public.mme_pos_financial_report_runs enable row level security;
alter table public.mme_pos_financial_report_rows enable row level security;
alter table public.mme_pos_financial_report_summaries enable row level security;
revoke all on public.mme_pos_financial_reporting_facts,public.mme_pos_financial_report_runs,
 public.mme_pos_financial_report_rows,public.mme_pos_financial_report_summaries from public,anon,authenticated;
grant all on public.mme_pos_financial_reporting_facts,public.mme_pos_financial_report_runs,
 public.mme_pos_financial_report_rows,public.mme_pos_financial_report_summaries to service_role;

create or replace function public.mme_pos_import_financial_fact(
 p_location_id uuid,p_actor_person_id uuid,p_source_system text,p_source_line_reference text,
 p_fact_type text,p_business_date date,p_occurred_at timestamptz,p_business_timezone text,
 p_currency text,p_amount_minor bigint,p_quantity_milli bigint default null,
 p_product_category text default null,p_sku_reference text default null,p_register_reference text default null,
 p_employee_person_id uuid default null,p_source_transaction_reference text default null,p_source_digest_sha256 text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_existing uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',p_location_id) then
  raise exception 'Financial fact import permission denied' using errcode='42501';
 end if;
 if p_source_line_reference is null or p_business_date is null or p_occurred_at is null
  or p_business_timezone is null or not exists(select 1 from pg_timezone_names where name=p_business_timezone)
  or p_currency !~ '^[A-Z]{3}$' or (p_occurred_at at time zone p_business_timezone)::date<>p_business_date
  or p_amount_minor is null then
  raise exception 'Invalid financial fact source, currency, timezone or date' using errcode='22023';
 end if;
 if exists(select 1 from public.mme_pos_financial_closes c where c.location_id=p_location_id
  and c.currency=p_currency and p_occurred_at>=c.business_period_start and p_occurred_at<c.business_period_end
  and c.status='closed') then
  raise exception 'Financial facts cannot be added to a closed period; use the authorized reopen and adjustment workflow' using errcode='55000';
 end if;
 select id into v_existing from public.mme_pos_financial_reporting_facts
 where location_id=p_location_id and source_system=p_source_system
  and source_line_reference=p_source_line_reference and fact_type=p_fact_type;
 if found then return v_existing; end if;
 insert into public.mme_pos_financial_reporting_facts(location_id,source_system,source_line_reference,fact_type,
  business_date,occurred_at,business_timezone,currency,amount_minor,quantity_milli,product_category,sku_reference,
  register_reference,employee_person_id,source_transaction_reference,source_digest_sha256,imported_by_person_id)
 values(p_location_id,p_source_system,p_source_line_reference,p_fact_type,p_business_date,p_occurred_at,
  p_business_timezone,p_currency,p_amount_minor,p_quantity_milli,p_product_category,p_sku_reference,
  p_register_reference,p_employee_person_id,p_source_transaction_reference,p_source_digest_sha256,p_actor_person_id)
 on conflict(location_id,source_system,source_line_reference,fact_type) do nothing
 returning id into v_id;
 if v_id is null then
  select id into v_id from public.mme_pos_financial_reporting_facts
  where location_id=p_location_id and source_system=p_source_system
   and source_line_reference=p_source_line_reference and fact_type=p_fact_type;
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_build_financial_report(
 p_location_id uuid,p_actor_person_id uuid,p_period_start date,p_period_end date,
 p_currency text,p_business_timezone text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_run uuid; v_cutoff timestamptz:=clock_timestamp(); v_count bigint; v_status text;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.build',p_location_id) then
  raise exception 'Financial report build permission denied' using errcode='42501';
 end if;
 if p_period_end<p_period_start or p_currency !~ '^[A-Z]{3}$'
  or not exists(select 1 from pg_timezone_names where name=p_business_timezone) then
  raise exception 'Invalid financial report period, currency or timezone' using errcode='22023';
 end if;
 select count(*) into v_count from public.mme_pos_financial_reporting_facts f
 where f.location_id=p_location_id and f.currency=p_currency and f.business_date between p_period_start and p_period_end
  and f.imported_at<=v_cutoff;
 v_status:=case when exists(select 1 from public.mme_pos_financial_closes c
  where c.location_id=p_location_id and c.currency=p_currency and c.status='closed'
   and c.business_period_start<=((p_period_start::timestamp at time zone p_business_timezone))
   and c.business_period_end>=(((p_period_end+1)::timestamp at time zone p_business_timezone)))
  then 'closed_period_snapshot' else 'provisional' end;
 insert into public.mme_pos_financial_report_runs(location_id,period_start,period_end,business_timezone,currency,status,
  source_fact_count,built_by_person_id,built_at,source_cutoff_at)
 values(p_location_id,p_period_start,p_period_end,p_business_timezone,p_currency,v_status,v_count,p_actor_person_id,v_cutoff,v_cutoff)
 returning id into v_run;

 insert into public.mme_pos_financial_report_rows(report_run_id,business_date,grouping_level,grouping_reference,currency,
  gross_sales_minor,discounts_minor,refunds_minor,subscription_revenue_minor,net_sales_minor,sales_tax_minor,
  cost_of_goods_sold_minor,processor_fees_minor,chargebacks_minor,cash_over_short_minor,inventory_adjustments_minor,
  gross_profit_minor,contribution_profit_minor,source_fact_count)
 with grouped as (
  select f.business_date,
   case when grouping(f.product_category)=0 then 'product_category'
        when grouping(f.register_reference)=0 then 'register'
        when grouping(f.employee_person_id)=0 then 'employee' else 'store' end as grouping_level,
   case when grouping(f.product_category)=0 then f.product_category
        when grouping(f.register_reference)=0 then f.register_reference
        when grouping(f.employee_person_id)=0 then f.employee_person_id::text else null end as grouping_reference,
   f.currency,
   coalesce(sum(amount_minor) filter(where fact_type='gross_sale'),0)::bigint gross_sales,
   coalesce(sum(amount_minor) filter(where fact_type='discount'),0)::bigint discounts,
   coalesce(sum(amount_minor) filter(where fact_type='refund'),0)::bigint refunds,
   coalesce(sum(amount_minor) filter(where fact_type='subscription_revenue'),0)::bigint subscription_revenue,
   coalesce(sum(amount_minor) filter(where fact_type in ('gross_sale','discount','refund','subscription_revenue')),0)::bigint net_sales,
   coalesce(sum(amount_minor) filter(where fact_type='sales_tax'),0)::bigint sales_tax,
   coalesce(sum(amount_minor) filter(where fact_type='cost_of_goods_sold'),0)::bigint cogs,
   coalesce(sum(amount_minor) filter(where fact_type='processor_fee'),0)::bigint processor_fees,
   coalesce(sum(amount_minor) filter(where fact_type='chargeback'),0)::bigint chargebacks,
   coalesce(sum(amount_minor) filter(where fact_type='cash_over_short'),0)::bigint cash_over_short,
   coalesce(sum(amount_minor) filter(where fact_type='inventory_adjustment'),0)::bigint inventory_adjustments,
   count(*)::bigint fact_count
  from public.mme_pos_financial_reporting_facts f
  where f.location_id=p_location_id and f.currency=p_currency
   and f.business_date between p_period_start and p_period_end and f.imported_at<=v_cutoff
  group by grouping sets ((f.business_date,f.currency),(f.business_date,f.currency,f.product_category),
   (f.business_date,f.currency,f.register_reference),(f.business_date,f.currency,f.employee_person_id))
 )
 select v_run,business_date,grouping_level,grouping_reference,currency,gross_sales,discounts,refunds,
  subscription_revenue,net_sales,sales_tax,cogs,processor_fees,chargebacks,cash_over_short,inventory_adjustments,
  net_sales+cogs,net_sales+cogs+processor_fees+chargebacks+cash_over_short,fact_count
 from grouped;

 insert into public.mme_pos_financial_report_summaries(report_run_id,settlement_net_minor,settlement_fee_minor,
  matched_bank_deposit_minor,cash_expected_minor,cash_counted_minor,cash_variance_minor,
  open_settlement_exception_count,unreconciled_batch_count)
 select v_run,
  coalesce((select sum(b.net_amount_minor) from public.mme_pos_settlement_batches b where b.location_id=p_location_id
   and b.currency=p_currency and b.settled_at>=p_period_start::timestamp at time zone p_business_timezone
   and b.settled_at<((p_period_end+1)::timestamp at time zone p_business_timezone)),0),
  coalesce((select sum(b.fee_amount_minor) from public.mme_pos_settlement_batches b where b.location_id=p_location_id
   and b.currency=p_currency and b.settled_at>=p_period_start::timestamp at time zone p_business_timezone
   and b.settled_at<((p_period_end+1)::timestamp at time zone p_business_timezone)),0),
  coalesce((select sum(d.amount_minor) from public.mme_pos_settlement_bank_matches m
   join public.mme_pos_bank_deposits d on d.id=m.bank_deposit_id
   where d.location_id=p_location_id and d.currency=p_currency and m.match_status='matched'
    and d.deposit_date between p_period_start and p_period_end),0),
  coalesce((select sum(c.expected_cash_minor) from public.mme_pos_cash_drawer_closings c
   where c.location_id=p_location_id and c.business_date between p_period_start and p_period_end),0),
  coalesce((select sum(c.counted_cash_minor) from public.mme_pos_cash_drawer_closings c
   where c.location_id=p_location_id and c.business_date between p_period_start and p_period_end),0),
  coalesce((select sum(c.variance_minor) from public.mme_pos_cash_drawer_closings c
   where c.location_id=p_location_id and c.business_date between p_period_start and p_period_end),0),
  (select count(*) from public.mme_pos_settlement_exceptions e join public.mme_pos_settlement_batches b on b.id=e.batch_id
   where e.location_id=p_location_id and b.currency=p_currency and b.settled_at>=p_period_start::timestamp at time zone p_business_timezone
    and b.settled_at<((p_period_end+1)::timestamp at time zone p_business_timezone)
    and e.status not in ('resolved','accepted_variance','false_positive')),
  greatest((select count(*) from public.mme_pos_settlement_batches b where b.location_id=p_location_id
   and b.currency=p_currency and b.settled_at>=p_period_start::timestamp at time zone p_business_timezone
   and b.settled_at<((p_period_end+1)::timestamp at time zone p_business_timezone))
   -(select count(distinct r.batch_id) from public.mme_pos_reconciliation_runs r
    join public.mme_pos_settlement_batches b on b.id=r.batch_id
    where r.location_id=p_location_id and r.status in ('approved','closed') and b.currency=p_currency
     and b.settled_at>=p_period_start::timestamp at time zone p_business_timezone
     and b.settled_at<((p_period_end+1)::timestamp at time zone p_business_timezone)),0)::integer;
 return v_run;
end;
$$;

create or replace view public.mme_pos_financial_report_daily
with (security_invoker=true) as
select r.id report_run_id,r.location_id,r.period_start,r.period_end,r.currency,r.status,
 row.business_date,row.gross_sales_minor,row.discounts_minor,row.refunds_minor,row.subscription_revenue_minor,
 row.net_sales_minor,row.sales_tax_minor,row.cost_of_goods_sold_minor,row.processor_fees_minor,
 row.chargebacks_minor,row.gross_profit_minor,row.contribution_profit_minor
from public.mme_pos_financial_report_runs r
join public.mme_pos_financial_report_rows row on row.report_run_id=r.id
where row.grouping_level='store';

create or replace view public.mme_pos_financial_report_profitability
with (security_invoker=true) as
select r.id report_run_id,r.location_id,r.currency,row.grouping_level,row.grouping_reference,
 sum(row.net_sales_minor) net_sales_minor,sum(row.cost_of_goods_sold_minor) cost_of_goods_sold_minor,
 sum(row.gross_profit_minor) gross_profit_minor,sum(row.processor_fees_minor) processor_fees_minor,
 sum(row.chargebacks_minor) chargebacks_minor,sum(row.contribution_profit_minor) contribution_profit_minor,
 case when sum(row.net_sales_minor)=0 then null
  else round(sum(row.gross_profit_minor)::numeric*10000/sum(row.net_sales_minor))::integer end gross_margin_basis_points
from public.mme_pos_financial_report_runs r
join public.mme_pos_financial_report_rows row on row.report_run_id=r.id
where row.grouping_level in ('product_category','register','employee')
group by r.id,r.location_id,r.currency,row.grouping_level,row.grouping_reference;

revoke all on function public.mme_pos_import_financial_fact(uuid,uuid,text,text,text,date,timestamptz,text,text,bigint,bigint,text,text,text,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_build_financial_report(uuid,uuid,date,date,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_import_financial_fact(uuid,uuid,text,text,text,date,timestamptz,text,text,bigint,bigint,text,text,text,uuid,text,text) to service_role;
grant execute on function public.mme_pos_build_financial_report(uuid,uuid,date,date,text,text) to service_role;
revoke all on public.mme_pos_financial_report_daily,public.mme_pos_financial_report_profitability from public,anon,authenticated;
grant select on public.mme_pos_financial_report_daily,public.mme_pos_financial_report_profitability to service_role;

comment on table public.mme_pos_financial_reporting_facts is 'Append-only, source-attributed POS financial facts. Signed amounts use integer minor currency units.';
comment on table public.mme_pos_financial_report_runs is 'Immutable reporting run metadata and source cutoff for reproducible financial reports.';
comment on table public.mme_pos_financial_report_rows is 'Daily store, product-category, register and employee reporting aggregates.';
comment on table public.mme_pos_financial_report_summaries is 'Settlement, bank deposit and cash control summaries for a report run.';
commit;
