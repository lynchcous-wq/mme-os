begin;
create table if not exists public.mme_cashflow_forecast_scenarios(
 scenario_id uuid primary key default gen_random_uuid(),
 scenario_name text not null,
 scenario_type text not null default 'base' check(scenario_type in ('base','optimistic','conservative','custom')),
 currency char(3) not null default 'USD',
 horizon_days integer not null default 90 check(horizon_days between 1 and 365),
 assumptions jsonb not null default '{}',
 scenario_status text not null default 'draft' check(scenario_status in ('draft','active','archived')),
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_cashflow_forecast_items(
 item_id uuid primary key default gen_random_uuid(),
 scenario_id uuid not null references public.mme_cashflow_forecast_scenarios(scenario_id) on delete cascade,
 effective_date date not null,
 category text not null check(category in ('opening_cash','sales_receipts','subscription_receipts','other_receipts','inventory_purchases','payroll','rent','vendor_payments','taxes','debt_service','capital_expenditure','other_expense')),
 direction text not null check(direction in ('inflow','outflow')),
 amount numeric(16,2) not null check(amount>0),
 confidence text not null default 'medium' check(confidence in ('low','medium','high')),
 source_type text not null default 'manual' check(source_type in ('manual','actual','recurring_rule','projection')),
 source_reference text,
 description text not null,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_cashflow_items_scenario_date_idx on public.mme_cashflow_forecast_items(scenario_id,effective_date);
create table if not exists public.mme_cashflow_actuals(
 actual_id uuid primary key default gen_random_uuid(),
 source_module text not null check(source_module in ('gl','treasury','pos','stripe','payroll','accounts_payable','accounts_receivable')),
 source_reference text not null,
 effective_date date not null,
 category text not null,
 direction text not null check(direction in ('inflow','outflow')),
 amount numeric(16,2) not null check(amount>0),
 currency char(3) not null default 'USD',
 description text not null,
 imported_by_auth_user_id uuid not null,
 imported_at timestamptz not null default now(),
 unique(source_module,source_reference)
);
create table if not exists public.mme_cashflow_forecast_runs(
 run_id uuid primary key default gen_random_uuid(),
 scenario_id uuid not null references public.mme_cashflow_forecast_scenarios(scenario_id),
 start_date date not null,
 end_date date not null,
 opening_cash numeric(16,2) not null,
 projected_inflows numeric(16,2) not null,
 projected_outflows numeric(16,2) not null,
 ending_cash numeric(16,2) not null,
 lowest_projected_cash numeric(16,2) not null,
 run_status text not null default 'completed' check(run_status in ('completed','review_required')),
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 check(end_date>=start_date)
);
create table if not exists public.mme_cashflow_forecast_run_days(
 run_day_id uuid primary key default gen_random_uuid(),
 run_id uuid not null references public.mme_cashflow_forecast_runs(run_id) on delete cascade,
 effective_date date not null,
 opening_cash numeric(16,2) not null,
 inflows numeric(16,2) not null,
 outflows numeric(16,2) not null,
 ending_cash numeric(16,2) not null,
 unique(run_id,effective_date)
);
create table if not exists public.mme_cashflow_audit(
 audit_id uuid primary key default gen_random_uuid(),
 actor_auth_user_id uuid not null,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create or replace function public.mme_cashflow_run_forecast(p_scenario uuid,p_start date,p_opening_cash numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare s public.mme_cashflow_forecast_scenarios%rowtype;v_run uuid;v_day date;v_end date;v_open numeric(16,2);v_in numeric(16,2);v_out numeric(16,2);v_close numeric(16,2);v_total_in numeric(16,2):=0;v_total_out numeric(16,2):=0;v_low numeric(16,2);v_status text:='completed';
begin
 select * into s from public.mme_cashflow_forecast_scenarios where scenario_id=p_scenario and scenario_status<>'archived';
 if not found then raise exception 'active_forecast_scenario_required';end if;
 if p_start is null or p_opening_cash<0 then raise exception 'invalid_forecast_opening_cash';end if;
 v_end:=p_start+s.horizon_days-1;v_open:=p_opening_cash;v_low:=p_opening_cash;
 insert into public.mme_cashflow_forecast_runs(scenario_id,start_date,end_date,opening_cash,projected_inflows,projected_outflows,ending_cash,lowest_projected_cash,created_by_auth_user_id) values(p_scenario,p_start,v_end,p_opening_cash,0,0,p_opening_cash,p_opening_cash,p_actor) returning run_id into v_run;
 for v_day in select generate_series(p_start,v_end,interval '1 day')::date loop
  select coalesce(sum(amount) filter(where direction='inflow'),0),coalesce(sum(amount) filter(where direction='outflow'),0) into v_in,v_out from public.mme_cashflow_forecast_items where scenario_id=p_scenario and effective_date=v_day;
  v_close:=v_open+v_in-v_out;v_total_in:=v_total_in+v_in;v_total_out:=v_total_out+v_out;v_low:=least(v_low,v_close);
  insert into public.mme_cashflow_forecast_run_days(run_id,effective_date,opening_cash,inflows,outflows,ending_cash) values(v_run,v_day,v_open,v_in,v_out,v_close);
  v_open:=v_close;
 end loop;
 if v_low<0 then v_status:='review_required';end if;
 update public.mme_cashflow_forecast_runs set projected_inflows=v_total_in,projected_outflows=v_total_out,ending_cash=v_open,lowest_projected_cash=v_low,run_status=v_status where run_id=v_run;
 insert into public.mme_cashflow_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'forecast_run','forecast_run',v_run,jsonb_build_object('scenario_id',p_scenario,'start_date',p_start,'end_date',v_end,'lowest_cash',v_low,'status',v_status));
 return v_run;
end $$;
alter table public.mme_cashflow_forecast_scenarios enable row level security;
alter table public.mme_cashflow_forecast_items enable row level security;
alter table public.mme_cashflow_actuals enable row level security;
alter table public.mme_cashflow_forecast_runs enable row level security;
alter table public.mme_cashflow_forecast_run_days enable row level security;
alter table public.mme_cashflow_audit enable row level security;
revoke all on public.mme_cashflow_forecast_scenarios,public.mme_cashflow_forecast_items,public.mme_cashflow_actuals,public.mme_cashflow_forecast_runs,public.mme_cashflow_forecast_run_days,public.mme_cashflow_audit from public,anon,authenticated;
grant all on public.mme_cashflow_forecast_scenarios,public.mme_cashflow_forecast_items,public.mme_cashflow_actuals,public.mme_cashflow_forecast_runs,public.mme_cashflow_forecast_run_days,public.mme_cashflow_audit to service_role;
revoke all on function public.mme_cashflow_run_forecast(uuid,date,numeric,uuid) from public,anon,authenticated;
grant execute on function public.mme_cashflow_run_forecast(uuid,date,numeric,uuid) to service_role;
commit;