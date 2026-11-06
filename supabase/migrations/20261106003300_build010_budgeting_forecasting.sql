begin;
create table if not exists public.mme_financial_budgets(
 budget_id uuid primary key default gen_random_uuid(),budget_code text not null unique,budget_name text not null,fiscal_year integer not null check(fiscal_year between 2000 and 2200),
 entity_id uuid references public.mme_financial_reporting_entities(entity_id),currency char(3) not null default 'USD',
 budget_status text not null default 'draft' check(budget_status in ('draft','submitted','approved','locked','superseded')),
 version integer not null default 1 check(version>0),parent_budget_id uuid references public.mme_financial_budgets(budget_id),
 assumptions jsonb not null default '{}',created_by_auth_user_id uuid not null,approved_by_auth_user_id uuid,approved_at timestamptz,
 created_at timestamptz not null default now(),unique(budget_code,version),check(approved_by_auth_user_id is null or approved_by_auth_user_id<>created_by_auth_user_id)
);
create table if not exists public.mme_financial_budget_lines(
 budget_line_id uuid primary key default gen_random_uuid(),budget_id uuid not null references public.mme_financial_budgets(budget_id),
 account_code text not null,department_code text,store_entity_id uuid references public.mme_financial_reporting_entities(entity_id),
 period_start date not null,period_end date not null,amount numeric(18,2) not null,currency char(3) not null default 'USD',
 line_type text not null check(line_type in ('revenue','cogs','payroll','operating_expense','capex','other')),
 notes text,created_at timestamptz not null default now(),check(period_end>=period_start),unique(budget_id,account_code,department_code,store_entity_id,period_start,line_type)
);
create table if not exists public.mme_financial_budget_approvals(
 approval_id uuid primary key default gen_random_uuid(),budget_id uuid not null references public.mme_financial_budgets(budget_id),
 approval_step integer not null check(approval_step>0),approver_auth_user_id uuid,approval_status text not null default 'pending' check(approval_status in ('pending','approved','rejected')),
 decision_note text,decided_at timestamptz,created_at timestamptz not null default now(),unique(budget_id,approval_step)
);
create table if not exists public.mme_financial_forecast_scenarios(
 scenario_id uuid primary key default gen_random_uuid(),scenario_code text not null unique,scenario_name text not null,scenario_type text not null check(scenario_type in ('base','upside','downside','custom')),
 fiscal_year integer not null,currency char(3) not null default 'USD',assumptions jsonb not null default '{}',
 scenario_status text not null default 'draft' check(scenario_status in ('draft','review','approved','archived')),
 created_by_auth_user_id uuid not null,approved_by_auth_user_id uuid,approved_at timestamptz,created_at timestamptz not null default now(),
 check(approved_by_auth_user_id is null or approved_by_auth_user_id<>created_by_auth_user_id)
);
create table if not exists public.mme_financial_forecast_lines(
 forecast_line_id uuid primary key default gen_random_uuid(),scenario_id uuid not null references public.mme_financial_forecast_scenarios(scenario_id),
 entity_id uuid references public.mme_financial_reporting_entities(entity_id),period_start date not null,period_end date not null,
 metric_code text not null,metric_label text not null,forecast_amount numeric(18,2) not null,currency char(3) not null default 'USD',
 driver_inputs jsonb not null default '{}',source text not null default 'manual' check(source in ('manual','budget','historical_actual','assumption')),
 created_at timestamptz not null default now(),check(period_end>=period_start),unique(scenario_id,entity_id,period_start,metric_code)
);
create table if not exists public.mme_financial_actual_snapshots(
 actual_snapshot_id uuid primary key default gen_random_uuid(),entity_id uuid references public.mme_financial_reporting_entities(entity_id),
 account_code text not null,department_code text,period_start date not null,period_end date not null,
 actual_amount numeric(18,2) not null,currency char(3) not null default 'USD',source_system text not null,
 source_watermark jsonb not null default '{}',captured_at timestamptz not null default now(),check(period_end>=period_start)
);
create table if not exists public.mme_financial_planning_drivers(
 driver_id uuid primary key default gen_random_uuid(),driver_code text not null unique,driver_name text not null,
 driver_category text not null check(driver_category in ('revenue','payroll','inventory','operating_expense','cash','other')),
 entity_id uuid references public.mme_financial_reporting_entities(entity_id),period_start date not null,period_end date not null,
 quantity numeric(18,4),unit_cost numeric(18,4),growth_rate numeric(12,6),assumptions jsonb not null default '{}',
 created_by_auth_user_id uuid not null,created_at timestamptz not null default now(),check(period_end>=period_start)
);
create index if not exists mme_fin_budget_year_status_idx on public.mme_financial_budgets(fiscal_year,budget_status);
create index if not exists mme_fin_budget_lines_period_idx on public.mme_financial_budget_lines(budget_id,period_start,account_code);
create index if not exists mme_fin_forecast_lines_period_idx on public.mme_financial_forecast_lines(scenario_id,period_start,metric_code);
create index if not exists mme_fin_actuals_period_idx on public.mme_financial_actual_snapshots(period_start,period_end,entity_id);
create or replace function public.mme_financial_submit_budget(p_id uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare b public.mme_financial_budgets%rowtype;
begin select * into b from public.mme_financial_budgets where budget_id=p_id for update;
if not found or b.budget_status<>'draft' then raise exception 'budget_not_submittable';end if;
if b.created_by_auth_user_id<>p_actor then raise exception 'budget_submitter_mismatch';end if;
if not exists(select 1 from public.mme_financial_budget_lines where budget_id=p_id) then raise exception 'budget_has_no_lines';end if;
update public.mme_financial_budgets set budget_status='submitted' where budget_id=p_id;
insert into public.mme_financial_budget_approvals(budget_id,approval_step) values(p_id,1) on conflict do nothing;
return p_id;end $$;
create or replace function public.mme_financial_decide_budget(p_id uuid,p_decision text,p_note text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare b public.mme_financial_budgets%rowtype;
begin if p_decision not in ('approved','rejected') then raise exception 'invalid_budget_decision';end if;
select * into b from public.mme_financial_budgets where budget_id=p_id for update;
if not found or b.budget_status<>'submitted' then raise exception 'budget_not_awaiting_approval';end if;
if b.created_by_auth_user_id=p_actor then raise exception 'budget_self_approval_prohibited';end if;
update public.mme_financial_budget_approvals set approver_auth_user_id=p_actor,approval_status=p_decision,decision_note=left(coalesce(p_note,''),1000),decided_at=now() where budget_id=p_id and approval_step=1 and approval_status='pending';
if not found then raise exception 'budget_approval_step_missing';end if;
update public.mme_financial_budgets set budget_status=p_decision,approved_by_auth_user_id=case when p_decision='approved' then p_actor else null end,approved_at=case when p_decision='approved' then now() else null end where budget_id=p_id;
return p_id;end $$;
do $$ declare t text;begin foreach t in array array['mme_financial_budgets','mme_financial_budget_lines','mme_financial_budget_approvals','mme_financial_forecast_scenarios','mme_financial_forecast_lines','mme_financial_actual_snapshots','mme_financial_planning_drivers'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end $$;
revoke all on function public.mme_financial_submit_budget(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_financial_decide_budget(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_financial_submit_budget(uuid,uuid) to service_role;
grant execute on function public.mme_financial_decide_budget(uuid,text,text,uuid) to service_role;
commit;