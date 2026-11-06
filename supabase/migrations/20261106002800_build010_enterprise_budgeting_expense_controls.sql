begin;
create table if not exists public.mme_budget_plans(
 budget_id uuid primary key default gen_random_uuid(),
 budget_name text not null,
 fiscal_year integer not null check(fiscal_year between 2000 and 2200),
 period_start date not null,
 period_end date not null,
 currency char(3) not null default 'USD',
 budget_status text not null default 'draft' check(budget_status in ('draft','submitted','approved','locked','archived')),
 created_by_auth_user_id uuid not null,
 approved_by_auth_user_id uuid,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 check(period_end>=period_start),
 check(approved_by_auth_user_id is null or approved_by_auth_user_id<>created_by_auth_user_id),
 unique(budget_name,fiscal_year)
);
create table if not exists public.mme_budget_dimensions(
 dimension_id uuid primary key default gen_random_uuid(),
 budget_id uuid not null references public.mme_budget_plans(budget_id) on delete cascade,
 dimension_type text not null check(dimension_type in ('company','department','store','cost_center','capital_project')),
 dimension_key text not null,
 dimension_name text not null,
 parent_dimension_id uuid references public.mme_budget_dimensions(dimension_id),
 created_at timestamptz not null default now(),
 unique(budget_id,dimension_type,dimension_key)
);
create table if not exists public.mme_budget_lines(
 line_id uuid primary key default gen_random_uuid(),
 budget_id uuid not null references public.mme_budget_plans(budget_id) on delete cascade,
 dimension_id uuid not null references public.mme_budget_dimensions(dimension_id),
 category text not null,
 period_start date not null,
 period_end date not null,
 budget_amount numeric(16,2) not null check(budget_amount>=0),
 capex boolean not null default false,
 notes text,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 check(period_end>=period_start)
);
create index if not exists mme_budget_lines_period_idx on public.mme_budget_lines(budget_id,dimension_id,period_start,period_end);
create table if not exists public.mme_expense_submissions(
 expense_id uuid primary key default gen_random_uuid(),
 submitter_auth_user_id uuid not null,
 dimension_id uuid not null references public.mme_budget_dimensions(dimension_id),
 budget_line_id uuid references public.mme_budget_lines(line_id),
 merchant text not null,
 expense_date date not null,
 category text not null,
 description text not null,
 amount numeric(16,2) not null check(amount>0),
 currency char(3) not null default 'USD',
 receipt_storage_path text,
 expense_status text not null default 'submitted' check(expense_status in ('draft','submitted','approved','rejected','paid','cancelled')),
 submitted_at timestamptz not null default now(),
 reviewed_by_auth_user_id uuid,
 reviewed_at timestamptz,
 review_note text,
 created_at timestamptz not null default now(),
 check(reviewed_by_auth_user_id is null or reviewed_by_auth_user_id<>submitter_auth_user_id)
);
create index if not exists mme_expense_submissions_status_idx on public.mme_expense_submissions(expense_status,expense_date);
create table if not exists public.mme_spending_policies(
 policy_id uuid primary key default gen_random_uuid(),
 dimension_id uuid references public.mme_budget_dimensions(dimension_id),
 category text,
 max_single_expense numeric(16,2) check(max_single_expense>0),
 approval_threshold numeric(16,2) check(approval_threshold>0),
 requires_receipt boolean not null default true,
 policy_status text not null default 'active' check(policy_status in ('active','inactive')),
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_budget_approvals(
 approval_id uuid primary key default gen_random_uuid(),
 entity_type text not null check(entity_type in ('budget','expense','purchase_request','capital_expenditure')),
 entity_id uuid not null,
 approval_step integer not null check(approval_step>0),
 approver_auth_user_id uuid,
 approval_status text not null default 'pending' check(approval_status in ('pending','approved','rejected','skipped')),
 decision_note text,
 decided_at timestamptz,
 created_at timestamptz not null default now(),
 unique(entity_type,entity_id,approval_step)
);
create table if not exists public.mme_budget_actuals(
 actual_id uuid primary key default gen_random_uuid(),
 source_module text not null check(source_module in ('gl','ap','pos','payroll','expenses','purchasing')),
 source_reference text not null,
 dimension_id uuid references public.mme_budget_dimensions(dimension_id),
 category text not null,
 effective_date date not null,
 amount numeric(16,2) not null check(amount>=0),
 currency char(3) not null default 'USD',
 description text not null,
 imported_by_auth_user_id uuid not null,
 imported_at timestamptz not null default now(),
 unique(source_module,source_reference)
);
create table if not exists public.mme_budget_audit(
 audit_id uuid primary key default gen_random_uuid(),
 actor_auth_user_id uuid not null,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create or replace function public.mme_budget_review_expense(p_expense uuid,p_decision text,p_note text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare e public.mme_expense_submissions%rowtype;v uuid;
begin
 if p_decision not in ('approved','rejected') then raise exception 'invalid_expense_decision';end if;
 select * into e from public.mme_expense_submissions where expense_id=p_expense for update;
 if not found or e.expense_status<>'submitted' then raise exception 'expense_not_reviewable';end if;
 if e.submitter_auth_user_id=p_actor then raise exception 'submitter_cannot_approve_own_expense';end if;
 update public.mme_expense_submissions set expense_status=p_decision,reviewed_by_auth_user_id=p_actor,reviewed_at=now(),review_note=left(coalesce(p_note,''),1000) where expense_id=p_expense;
 insert into public.mme_budget_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'expense_'||p_decision,'expense',p_expense,jsonb_build_object('submitter',e.submitter_auth_user_id,'amount',e.amount,'note',left(coalesce(p_note,''),1000)));
 return p_expense;
end $$;
create or replace function public.mme_budget_approve_plan(p_budget uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare b public.mme_budget_plans%rowtype;
begin
 select * into b from public.mme_budget_plans where budget_id=p_budget for update;
 if not found or b.budget_status not in ('draft','submitted') then raise exception 'budget_not_approvable';end if;
 if b.created_by_auth_user_id=p_actor then raise exception 'creator_cannot_approve_budget';end if;
 update public.mme_budget_plans set budget_status='approved',approved_by_auth_user_id=p_actor,approved_at=now() where budget_id=p_budget;
 insert into public.mme_budget_audit(actor_auth_user_id,action,entity_type,entity_id) values(p_actor,'budget_approved','budget',p_budget);
 return p_budget;
end $$;
alter table public.mme_budget_plans enable row level security;
alter table public.mme_budget_dimensions enable row level security;
alter table public.mme_budget_lines enable row level security;
alter table public.mme_expense_submissions enable row level security;
alter table public.mme_spending_policies enable row level security;
alter table public.mme_budget_approvals enable row level security;
alter table public.mme_budget_actuals enable row level security;
alter table public.mme_budget_audit enable row level security;
revoke all on public.mme_budget_plans,public.mme_budget_dimensions,public.mme_budget_lines,public.mme_expense_submissions,public.mme_spending_policies,public.mme_budget_approvals,public.mme_budget_actuals,public.mme_budget_audit from public,anon,authenticated;
grant all on public.mme_budget_plans,public.mme_budget_dimensions,public.mme_budget_lines,public.mme_expense_submissions,public.mme_spending_policies,public.mme_budget_approvals,public.mme_budget_actuals,public.mme_budget_audit to service_role;
revoke all on function public.mme_budget_review_expense(uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_budget_approve_plan(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_budget_review_expense(uuid,text,text,uuid) to service_role;
grant execute on function public.mme_budget_approve_plan(uuid,uuid) to service_role;
commit;