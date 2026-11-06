begin;
create table if not exists public.mme_financial_reporting_entities(
 entity_id uuid primary key default gen_random_uuid(),entity_code text not null unique,entity_name text not null,entity_type text not null check(entity_type in ('parent','subsidiary','store','department','elimination')),
 parent_entity_id uuid references public.mme_financial_reporting_entities(entity_id),functional_currency char(3) not null default 'USD',active boolean not null default true,
 created_by_auth_user_id uuid not null,created_at timestamptz not null default now(),check(parent_entity_id is null or parent_entity_id<>entity_id)
);
create table if not exists public.mme_financial_consolidation_runs(
 consolidation_run_id uuid primary key default gen_random_uuid(),period_start date not null,period_end date not null,reporting_currency char(3) not null default 'USD',
 run_status text not null default 'draft' check(run_status in ('draft','review','approved','superseded')),scope_description text not null,
 entity_ids uuid[] not null default '{}',eliminations_total numeric(18,2) not null default 0,exchange_adjustments numeric(18,2) not null default 0,
 source_snapshot jsonb not null default '{}',created_by_auth_user_id uuid not null,approved_by_auth_user_id uuid,approved_at timestamptz,created_at timestamptz not null default now(),
 check(period_end>=period_start),check(approved_by_auth_user_id is null or approved_by_auth_user_id<>created_by_auth_user_id)
);
create table if not exists public.mme_financial_elimination_entries(
 elimination_id uuid primary key default gen_random_uuid(),consolidation_run_id uuid not null references public.mme_financial_consolidation_runs(consolidation_run_id),
 entity_id uuid not null references public.mme_financial_reporting_entities(entity_id),counterparty_entity_id uuid references public.mme_financial_reporting_entities(entity_id),
 elimination_code text not null,description text not null,account_code text not null,debit numeric(18,2) not null default 0,credit numeric(18,2) not null default 0,
 source_reference text,created_by_auth_user_id uuid not null,created_at timestamptz not null default now(),
 check(debit>=0 and credit>=0 and ((debit>0 and credit=0) or (credit>0 and debit=0)))
);
create table if not exists public.mme_financial_report_snapshots(
 snapshot_id uuid primary key default gen_random_uuid(),report_type text not null check(report_type in ('income_statement','balance_sheet','cash_flow','trial_balance','department_profitability','store_profitability','consolidated')),
 period_start date not null,period_end date not null,entity_id uuid references public.mme_financial_reporting_entities(entity_id),
 consolidation_run_id uuid references public.mme_financial_consolidation_runs(consolidation_run_id),currency char(3) not null default 'USD',
 report_payload jsonb not null,source_systems text[] not null default array['general_ledger'],source_watermarks jsonb not null default '{}',
 snapshot_status text not null default 'draft' check(snapshot_status in ('draft','review','certified','superseded')),
 generated_by_auth_user_id uuid not null,certified_by_auth_user_id uuid,certified_at timestamptz,created_at timestamptz not null default now(),
 check(period_end>=period_start),check(certified_by_auth_user_id is null or certified_by_auth_user_id<>generated_by_auth_user_id)
);
create table if not exists public.mme_financial_variance_analyses(
 variance_id uuid primary key default gen_random_uuid(),report_type text not null,period_start date not null,period_end date not null,entity_id uuid references public.mme_financial_reporting_entities(entity_id),
 metric_code text not null,metric_label text not null,actual_amount numeric(18,2) not null,budget_amount numeric(18,2) not null,
 variance_amount numeric(18,2) generated always as(actual_amount-budget_amount) stored,
 variance_percent numeric(12,4),explanation text,review_status text not null default 'unreviewed' check(review_status in ('unreviewed','explained','escalated','accepted')),
 created_by_auth_user_id uuid not null,created_at timestamptz not null default now(),check(period_end>=period_start)
);
create table if not exists public.mme_financial_close_certifications(
 certification_id uuid primary key default gen_random_uuid(),period_start date not null,period_end date not null,entity_id uuid references public.mme_financial_reporting_entities(entity_id),
 certification_status text not null default 'pending' check(certification_status in ('pending','certified','rejected')),
 trial_balance_debits numeric(18,2) not null default 0,trial_balance_credits numeric(18,2) not null default 0,unposted_journal_count integer not null default 0,
 unreconciled_bank_count integer not null default 0,open_ap_count integer not null default 0,open_ar_count integer not null default 0,
 checklist jsonb not null default '{}',exceptions jsonb not null default '[]',certified_by_auth_user_id uuid,certified_at timestamptz,
 created_by_auth_user_id uuid not null,created_at timestamptz not null default now(),check(period_end>=period_start),
 check(certified_by_auth_user_id is null or certified_by_auth_user_id<>created_by_auth_user_id)
);
create index if not exists mme_financial_snapshot_period_idx on public.mme_financial_report_snapshots(report_type,period_start,period_end,entity_id);
create index if not exists mme_financial_variance_period_idx on public.mme_financial_variance_analyses(period_start,period_end,review_status);
create index if not exists mme_financial_consolidation_period_idx on public.mme_financial_consolidation_runs(period_start,period_end,run_status);
create or replace function public.mme_financial_certify_close(p_id uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare c public.mme_financial_close_certifications%rowtype;
begin
 select * into c from public.mme_financial_close_certifications where certification_id=p_id for update;
 if not found or c.certification_status<>'pending' then raise exception 'close_certification_not_pending';end if;
 if c.created_by_auth_user_id=p_actor then raise exception 'close_submitter_cannot_certify';end if;
 if abs(c.trial_balance_debits-c.trial_balance_credits)>0.005 then raise exception 'trial_balance_not_balanced';end if;
 if c.unposted_journal_count<>0 or c.unreconciled_bank_count<>0 then raise exception 'close_has_unresolved_ledger_or_bank_exceptions';end if;
 update public.mme_financial_close_certifications set certification_status='certified',certified_by_auth_user_id=p_actor,certified_at=now() where certification_id=p_id;
 return p_id;
end $$;
do $$ declare t text;begin foreach t in array array['mme_financial_reporting_entities','mme_financial_consolidation_runs','mme_financial_elimination_entries','mme_financial_report_snapshots','mme_financial_variance_analyses','mme_financial_close_certifications'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end $$;
revoke all on function public.mme_financial_certify_close(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_financial_certify_close(uuid,uuid) to service_role;
commit;