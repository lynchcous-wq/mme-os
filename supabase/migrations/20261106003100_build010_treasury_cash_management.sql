begin;
create table if not exists public.mme_treasury_deposits(
 deposit_id uuid primary key default gen_random_uuid(),bank_account_id uuid not null references public.mme_treasury_bank_accounts(bank_account_id),
 deposit_reference text not null,deposit_date date not null,amount numeric(16,2) not null check(amount>0),currency char(3) not null default 'USD',
 source_type text not null check(source_type in ('pos_cash','pos_card','customer_payment','other')),source_reference text,
 deposit_status text not null default 'recorded' check(deposit_status in ('recorded','in_transit','cleared','exception','void')),
 recorded_by_auth_user_id uuid not null,cleared_at timestamptz,created_at timestamptz not null default now(),unique(bank_account_id,deposit_reference)
);
create table if not exists public.mme_treasury_outstanding_checks(
 check_id uuid primary key default gen_random_uuid(),bank_account_id uuid not null references public.mme_treasury_bank_accounts(bank_account_id),
 check_number text not null,payee text not null,issue_date date not null,amount numeric(16,2) not null check(amount>0),currency char(3) not null default 'USD',
 check_status text not null default 'issued' check(check_status in ('issued','presented','cleared','void','stopped','stale')),
 source_reference text,recorded_by_auth_user_id uuid not null,cleared_at timestamptz,created_at timestamptz not null default now(),unique(bank_account_id,check_number)
);
create table if not exists public.mme_treasury_ach_events(
 ach_event_id uuid primary key default gen_random_uuid(),bank_account_id uuid references public.mme_treasury_bank_accounts(bank_account_id),
 provider_reference text not null unique,event_type text not null check(event_type in ('created','submitted','accepted','settled','returned','rejected','cancelled')),
 amount numeric(16,2) check(amount>0),currency char(3) not null default 'USD',effective_date date,return_code text,event_details jsonb not null default '{}',
 recorded_by_auth_user_id uuid not null,created_at timestamptz not null default now()
);
create table if not exists public.mme_treasury_cash_transfers(
 transfer_id uuid primary key default gen_random_uuid(),from_account_id uuid not null references public.mme_treasury_bank_accounts(bank_account_id),
 to_account_id uuid not null references public.mme_treasury_bank_accounts(bank_account_id),transfer_reference text not null unique,
 transfer_date date not null,amount numeric(16,2) not null check(amount>0),currency char(3) not null default 'USD',
 transfer_status text not null default 'draft' check(transfer_status in ('draft','pending_approval','approved','rejected','recorded','cancelled')),
 memo text,created_by_auth_user_id uuid not null,approved_by_auth_user_id uuid,approved_at timestamptz,created_at timestamptz not null default now(),
 check(from_account_id<>to_account_id),check(approved_by_auth_user_id is null or approved_by_auth_user_id<>created_by_auth_user_id)
);
create table if not exists public.mme_treasury_cash_forecasts(
 forecast_id uuid primary key default gen_random_uuid(),forecast_date date not null,scenario text not null check(scenario in ('base','upside','downside')),
 opening_cash numeric(16,2) not null,projected_inflows numeric(16,2) not null default 0,projected_outflows numeric(16,2) not null default 0,
 restricted_cash numeric(16,2) not null default 0,projected_closing_cash numeric(16,2) generated always as(opening_cash+projected_inflows-projected_outflows) stored,
 assumptions jsonb not null default '{}',created_by_auth_user_id uuid not null,created_at timestamptz not null default now(),unique(forecast_date,scenario)
);
create table if not exists public.mme_treasury_cash_movement_approvals(
 approval_id uuid primary key default gen_random_uuid(),transfer_id uuid not null references public.mme_treasury_cash_transfers(transfer_id),
 approval_step integer not null check(approval_step>0),approver_auth_user_id uuid,approval_status text not null default 'pending' check(approval_status in ('pending','approved','rejected')),
 decision_note text,decided_at timestamptz,created_at timestamptz not null default now(),unique(transfer_id,approval_step)
);
create index if not exists mme_treasury_deposit_status_date_idx on public.mme_treasury_deposits(deposit_status,deposit_date);
create index if not exists mme_treasury_checks_status_date_idx on public.mme_treasury_outstanding_checks(check_status,issue_date);
create index if not exists mme_treasury_ach_account_date_idx on public.mme_treasury_ach_events(bank_account_id,created_at desc);
create index if not exists mme_treasury_forecast_date_idx on public.mme_treasury_cash_forecasts(forecast_date,scenario);
create or replace function public.mme_treasury_submit_transfer(p_transfer uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare t public.mme_treasury_cash_transfers%rowtype;
begin
 select * into t from public.mme_treasury_cash_transfers where transfer_id=p_transfer for update;
 if not found or t.transfer_status<>'draft' then raise exception 'transfer_not_submittable';end if;
 if t.created_by_auth_user_id<>p_actor then raise exception 'transfer_submitter_mismatch';end if;
 update public.mme_treasury_cash_transfers set transfer_status='pending_approval' where transfer_id=p_transfer;
 insert into public.mme_treasury_cash_movement_approvals(transfer_id,approval_step) values(p_transfer,1) on conflict do nothing;
 insert into public.mme_treasury_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'cash_transfer_submitted','cash_transfer',p_transfer,'{}');
 return p_transfer;
end $$;
create or replace function public.mme_treasury_decide_transfer(p_transfer uuid,p_decision text,p_note text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare t public.mme_treasury_cash_transfers%rowtype;
begin
 if p_decision not in ('approved','rejected') then raise exception 'invalid_transfer_decision';end if;
 select * into t from public.mme_treasury_cash_transfers where transfer_id=p_transfer for update;
 if not found or t.transfer_status<>'pending_approval' then raise exception 'transfer_not_awaiting_approval';end if;
 if t.created_by_auth_user_id=p_actor then raise exception 'transfer_self_approval_prohibited';end if;
 update public.mme_treasury_cash_movement_approvals set approver_auth_user_id=p_actor,approval_status=p_decision,decision_note=left(coalesce(p_note,''),1000),decided_at=now() where transfer_id=p_transfer and approval_step=1 and approval_status='pending';
 if not found then raise exception 'transfer_approval_step_missing';end if;
 update public.mme_treasury_cash_transfers set transfer_status=p_decision,approved_by_auth_user_id=case when p_decision='approved' then p_actor else null end,approved_at=case when p_decision='approved' then now() else null end where transfer_id=p_transfer;
 insert into public.mme_treasury_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'cash_transfer_'||p_decision,'cash_transfer',p_transfer,jsonb_build_object('note',left(coalesce(p_note,''),1000)));
 return p_transfer;
end $$;
do $$ declare t text;begin foreach t in array array['mme_treasury_deposits','mme_treasury_outstanding_checks','mme_treasury_ach_events','mme_treasury_cash_transfers','mme_treasury_cash_forecasts','mme_treasury_cash_movement_approvals'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end $$;
revoke all on function public.mme_treasury_submit_transfer(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_treasury_decide_transfer(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_treasury_submit_transfer(uuid,uuid) to service_role;
grant execute on function public.mme_treasury_decide_transfer(uuid,text,text,uuid) to service_role;
commit;