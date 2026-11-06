begin;
create table if not exists public.mme_workforce_compensation_profiles(
 compensation_id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 pay_type text not null check(pay_type in ('hourly','salary','commission_only','hybrid')),
 base_rate numeric(14,2) not null default 0 check(base_rate>=0),
 currency char(3) not null default 'USD',
 effective_from date not null,
 effective_to date,
 commission_plan_key text,
 approved_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 check(effective_to is null or effective_to>=effective_from)
);
create table if not exists public.mme_workforce_time_entries(
 time_entry_id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 shift_date date not null,
 clock_in timestamptz not null,
 clock_out timestamptz,
 break_minutes integer not null default 0 check(break_minutes between 0 and 1440),
 entry_source text not null default 'manual' check(entry_source in ('manual','time_clock_import','manager_adjustment')),
 status text not null default 'submitted' check(status in ('draft','submitted','approved','rejected','locked')),
 submitted_by_auth_user_id uuid not null,
 reviewed_by_auth_user_id uuid,
 review_note text,
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 check(clock_out is null or clock_out>clock_in)
);
create table if not exists public.mme_workforce_payroll_periods(
 payroll_period_id uuid primary key default gen_random_uuid(),
 period_start date not null,
 period_end date not null,
 pay_date date,
 status text not null default 'draft' check(status in ('draft','review','approved','exported','closed','void')),
 created_by_auth_user_id uuid not null,
 approved_by_auth_user_id uuid,
 approved_at timestamptz,
 export_reference text,
 created_at timestamptz not null default now(),
 check(period_end>=period_start)
);
create table if not exists public.mme_workforce_payroll_line_items(
 line_item_id uuid primary key default gen_random_uuid(),
 payroll_period_id uuid not null references public.mme_workforce_payroll_periods(payroll_period_id) on delete cascade,
 person_id uuid not null,
 earning_type text not null check(earning_type in ('regular','overtime','commission','bonus','adjustment','deduction')),
 description text not null,
 quantity numeric(14,4) not null default 1,
 rate numeric(14,4) not null default 0,
 amount numeric(14,2) not null,
 currency char(3) not null default 'USD',
 source_reference text,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_workforce_commission_ledger(
 commission_id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 sale_reference text not null,
 product_category text not null,
 units integer not null default 1 check(units>0),
 gross_amount numeric(14,2) not null default 0,
 commission_amount numeric(14,2) not null check(commission_amount>=0),
 status text not null default 'pending' check(status in ('pending','verified','approved','paid','void')),
 verified_by_auth_user_id uuid,
 approved_by_auth_user_id uuid,
 payroll_period_id uuid references public.mme_workforce_payroll_periods(payroll_period_id),
 created_at timestamptz not null default now(),
 unique(person_id,sale_reference,product_category)
);
create table if not exists public.mme_workforce_performance_reviews(
 performance_review_id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 reviewer_auth_user_id uuid not null,
 review_period_start date not null,
 review_period_end date not null,
 rating numeric(3,2) check(rating between 0 and 5),
 strengths text,
 improvement_plan text,
 goals jsonb not null default '[]',
 status text not null default 'draft' check(status in ('draft','submitted','acknowledged','closed')),
 created_at timestamptz not null default now(),
 check(review_period_end>=review_period_start)
);
create table if not exists public.mme_workforce_schedule_shifts(
 shift_id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 location_id uuid,
 shift_start timestamptz not null,
 shift_end timestamptz not null,
 status text not null default 'scheduled' check(status in ('scheduled','confirmed','completed','missed','cancelled')),
 assigned_by_auth_user_id uuid not null,
 notes text,
 created_at timestamptz not null default now(),
 check(shift_end>shift_start)
);
create table if not exists public.mme_workforce_hr_payroll_audit(
 audit_id bigint generated always as identity primary key,
 actor_auth_user_id uuid not null,
 actor_role text not null,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}',
 request_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_workforce_time_person_date_idx on public.mme_workforce_time_entries(person_id,shift_date desc,status);
create index if not exists mme_workforce_payroll_period_idx on public.mme_workforce_payroll_periods(period_start,period_end,status);
create index if not exists mme_workforce_payroll_line_period_idx on public.mme_workforce_payroll_line_items(payroll_period_id,person_id);
create index if not exists mme_workforce_commission_status_idx on public.mme_workforce_commission_ledger(person_id,status,created_at desc);
create index if not exists mme_workforce_performance_person_idx on public.mme_workforce_performance_reviews(person_id,review_period_end desc);
create index if not exists mme_workforce_schedule_person_idx on public.mme_workforce_schedule_shifts(person_id,shift_start,status);
alter table public.mme_workforce_compensation_profiles enable row level security;
alter table public.mme_workforce_time_entries enable row level security;
alter table public.mme_workforce_payroll_periods enable row level security;
alter table public.mme_workforce_payroll_line_items enable row level security;
alter table public.mme_workforce_commission_ledger enable row level security;
alter table public.mme_workforce_performance_reviews enable row level security;
alter table public.mme_workforce_schedule_shifts enable row level security;
alter table public.mme_workforce_hr_payroll_audit enable row level security;
do $$ declare t text; begin
 foreach t in array array['mme_workforce_compensation_profiles','mme_workforce_time_entries','mme_workforce_payroll_periods','mme_workforce_payroll_line_items','mme_workforce_commission_ledger','mme_workforce_performance_reviews','mme_workforce_schedule_shifts','mme_workforce_hr_payroll_audit'] loop
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.mme_workforce_hr_payroll_audit_audit_id_seq to service_role;
comment on table public.mme_workforce_compensation_profiles is 'Restricted compensation configuration ledger; does not calculate or disburse payroll.';
comment on table public.mme_workforce_payroll_line_items is 'Payroll earning and deduction staging ledger; does not initiate ACH, checks or tax filings.';
comment on table public.mme_workforce_time_entries is 'Auditable time entry ledger; source clock and geolocation validation require integration.';
commit;