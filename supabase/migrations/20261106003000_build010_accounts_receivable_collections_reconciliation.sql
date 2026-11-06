begin;
create table if not exists public.mme_ar_provider_transactions(
 provider_transaction_id uuid primary key default gen_random_uuid(),
 provider text not null check(provider in ('stripe','bank','pos','manual')),
 provider_account_ref text,
 provider_event_ref text not null,
 transaction_ref text not null,
 external_payment_reference text,
 customer_id uuid,
 transaction_date date not null,
 amount numeric(16,2) not null check(amount>0),
 currency char(3) not null default 'USD',
 transaction_status text not null default 'pending_review' check(transaction_status in ('pending_review','matched','exception','ignored')),
 evidence_hash text,
 imported_by_auth_user_id uuid not null,
 imported_at timestamptz not null default now(),
 unique(provider,provider_event_ref),
 unique(provider,transaction_ref)
);
create table if not exists public.mme_ar_payment_reconciliations(
 reconciliation_id uuid primary key default gen_random_uuid(),
 provider_transaction_id uuid not null unique references public.mme_ar_provider_transactions(provider_transaction_id),
 payment_id uuid not null references public.mme_ar_payments(payment_id),
 match_status text not null default 'matched' check(match_status in ('matched','exception','reversed')),
 matched_by_auth_user_id uuid not null,
 matched_at timestamptz not null default now(),
 match_details jsonb not null default '{}',
 unique(payment_id,provider_transaction_id)
);
create table if not exists public.mme_ar_subscription_links(
 subscription_link_id uuid primary key default gen_random_uuid(),
 customer_id uuid not null,
 provider text not null default 'stripe' check(provider in ('stripe')),
 provider_customer_ref text not null,
 provider_subscription_ref text not null unique,
 subscription_status text not null default 'pending_verification' check(subscription_status in ('pending_verification','active','past_due','paused','cancelled','incomplete')),
 billing_currency char(3) not null default 'USD',
 billing_interval text not null check(billing_interval in ('day','week','month','year')),
 interval_count integer not null default 1 check(interval_count between 1 and 36),
 next_invoice_date date,
 last_provider_invoice_ref text,
 last_synced_at timestamptz,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_ar_collection_cases(
 collection_case_id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.mme_ar_invoices(invoice_id),
 customer_id uuid not null,
 case_status text not null default 'open' check(case_status in ('open','contacted','promise_to_pay','disputed','escalated','resolved','closed')),
 priority text not null default 'normal' check(priority in ('low','normal','high','critical')),
 assigned_to_auth_user_id uuid,
 next_action_at timestamptz,
 promise_to_pay_date date,
 promise_to_pay_amount numeric(16,2) check(promise_to_pay_amount>0),
 case_notes text,
 opened_by_auth_user_id uuid not null,
 resolved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists mme_ar_one_active_collection_case_idx on public.mme_ar_collection_cases(invoice_id) where case_status not in ('resolved','closed');
create table if not exists public.mme_ar_collection_activities(
 activity_id uuid primary key default gen_random_uuid(),
 collection_case_id uuid not null references public.mme_ar_collection_cases(collection_case_id),
 activity_type text not null check(activity_type in ('call','email','sms','letter','promise_to_pay','dispute','note','escalation','system')),
 activity_note text not null,
 outcome text,
 contacted_at timestamptz not null default now(),
 next_action_at timestamptz,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_ar_reminder_policies(
 policy_id uuid primary key default gen_random_uuid(),
 policy_name text not null unique,
 days_relative_to_due integer not null,
 channel text not null check(channel in ('email','sms','internal_task')),
 enabled boolean not null default false,
 template_key text,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_ar_provider_txn_status_idx on public.mme_ar_provider_transactions(transaction_status,transaction_date);
create index if not exists mme_ar_collection_case_due_idx on public.mme_ar_collection_cases(case_status,next_action_at,priority);
create index if not exists mme_ar_collection_activity_case_idx on public.mme_ar_collection_activities(collection_case_id,contacted_at desc);
create or replace function public.mme_ar_reconcile_provider_transaction(p_transaction uuid,p_payment uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare t public.mme_ar_provider_transactions%rowtype;p public.mme_ar_payments%rowtype;v uuid;
begin
 select * into t from public.mme_ar_provider_transactions where provider_transaction_id=p_transaction for update;
 if not found or t.transaction_status<>'pending_review' then raise exception 'provider_transaction_not_reconcilable';end if;
 select * into p from public.mme_ar_payments where payment_id=p_payment for update;
 if not found or p.status<>'recorded' then raise exception 'ar_payment_not_reconcilable';end if;
 if t.amount<>p.amount or t.currency<>p.currency then raise exception 'payment_amount_or_currency_mismatch';end if;
 if t.customer_id is not null and t.customer_id<>p.customer_id then raise exception 'payment_customer_mismatch';end if;
 if t.external_payment_reference is not null and t.external_payment_reference<>p.external_reference and t.external_payment_reference<>p.payment_reference then raise exception 'payment_reference_mismatch';end if;
 insert into public.mme_ar_payment_reconciliations(provider_transaction_id,payment_id,matched_by_auth_user_id,match_details) values(t.provider_transaction_id,p.payment_id,p_actor,jsonb_build_object('provider',t.provider,'transaction_ref',t.transaction_ref,'amount',t.amount,'currency',t.currency)) returning reconciliation_id into v;
 update public.mme_ar_provider_transactions set transaction_status='matched' where provider_transaction_id=p_transaction;
 insert into public.mme_ar_audit_events(actor_auth_user_id,action,entity_type,entity_id,details,request_id) values(p_actor,'provider_payment_reconciled','payment',p.payment_id,jsonb_build_object('provider_transaction_id',p_transaction,'reconciliation_id',v),gen_random_uuid());
 return v;
end $$;
create or replace function public.mme_ar_open_collection_case(p_invoice uuid,p_priority text,p_assignee uuid,p_next_action timestamptz,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare i public.mme_ar_invoices%rowtype;v uuid;b numeric(16,2);
begin
 if p_priority not in ('low','normal','high','critical') then raise exception 'invalid_collection_priority';end if;
 select * into i from public.mme_ar_invoices where invoice_id=p_invoice for update;
 if not found or i.invoice_status in ('paid','void','written_off') then raise exception 'invoice_not_collectible';end if;
 select outstanding_amount into b from public.mme_ar_invoice_balances where invoice_id=p_invoice;
 if coalesce(b,0)<=0 then raise exception 'invoice_has_no_outstanding_balance';end if;
 insert into public.mme_ar_collection_cases(invoice_id,customer_id,priority,assigned_to_auth_user_id,next_action_at,opened_by_auth_user_id) values(p_invoice,i.customer_id,p_priority,p_assignee,p_next_action,p_actor) returning collection_case_id into v;
 insert into public.mme_ar_audit_events(actor_auth_user_id,action,entity_type,entity_id,details,request_id) values(p_actor,'collection_case_opened','collection_case',v,jsonb_build_object('invoice_id',p_invoice,'outstanding',b),gen_random_uuid());
 return v;
end $$;
do $$ declare t text;begin foreach t in array array['mme_ar_provider_transactions','mme_ar_payment_reconciliations','mme_ar_subscription_links','mme_ar_collection_cases','mme_ar_collection_activities','mme_ar_reminder_policies'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end $$;
revoke all on function public.mme_ar_reconcile_provider_transaction(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_ar_reconcile_provider_transaction(uuid,uuid,uuid) to service_role;
revoke all on function public.mme_ar_open_collection_case(uuid,text,uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.mme_ar_open_collection_case(uuid,text,uuid,timestamptz,uuid) to service_role;
commit;