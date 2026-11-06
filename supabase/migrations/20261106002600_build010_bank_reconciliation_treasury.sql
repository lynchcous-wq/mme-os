begin;
create table if not exists public.mme_treasury_bank_accounts(
 bank_account_id uuid primary key default gen_random_uuid(),
 account_name text not null,
 institution_name text not null,
 account_mask text not null check(account_mask ~ '^[0-9]{2,8}$'),
 currency char(3) not null default 'USD',
 gl_account_id uuid not null references public.mme_gl_accounts(account_id),
 account_status text not null default 'active' check(account_status in ('active','inactive','closed')),
 opening_balance numeric(16,2) not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(institution_name,account_mask)
);
create table if not exists public.mme_treasury_statements(
 statement_id uuid primary key default gen_random_uuid(),
 bank_account_id uuid not null references public.mme_treasury_bank_accounts(bank_account_id),
 statement_reference text not null,
 period_start date not null,
 period_end date not null,
 opening_balance numeric(16,2) not null,
 closing_balance numeric(16,2) not null,
 import_status text not null default 'imported' check(import_status in ('imported','reconciled','exception')),
 imported_by_auth_user_id uuid not null,
 imported_at timestamptz not null default now(),
 unique(bank_account_id,statement_reference),
 check(period_end>=period_start)
);
create table if not exists public.mme_treasury_bank_transactions(
 transaction_id uuid primary key default gen_random_uuid(),
 statement_id uuid not null references public.mme_treasury_statements(statement_id) on delete restrict,
 external_transaction_id text,
 transaction_date date not null,
 description text not null,
 amount numeric(16,2) not null check(amount<>0),
 currency char(3) not null default 'USD',
 transaction_type text not null check(transaction_type in ('credit','debit')),
 match_status text not null default 'unmatched' check(match_status in ('unmatched','suggested','matched','excluded')),
 raw_data jsonb not null default '{}',
 created_at timestamptz not null default now(),
 check((transaction_type='credit' and amount>0) or (transaction_type='debit' and amount<0)),
 unique(statement_id,external_transaction_id)
);
create index if not exists mme_treasury_transactions_match_idx on public.mme_treasury_bank_transactions(match_status,transaction_date);
create table if not exists public.mme_treasury_reconciliations(
 reconciliation_id uuid primary key default gen_random_uuid(),
 statement_id uuid not null unique references public.mme_treasury_statements(statement_id),
 bank_account_id uuid not null references public.mme_treasury_bank_accounts(bank_account_id),
 statement_closing_balance numeric(16,2) not null,
 gl_closing_balance numeric(16,2) not null,
 difference numeric(16,2) not null,
 reconciliation_status text not null default 'open' check(reconciliation_status in ('open','reconciled','exception')),
 prepared_by_auth_user_id uuid not null,
 reviewed_by_auth_user_id uuid,
 reconciled_at timestamptz,
 created_at timestamptz not null default now(),
 check(reviewed_by_auth_user_id is null or reviewed_by_auth_user_id<>prepared_by_auth_user_id)
);
create table if not exists public.mme_treasury_matches(
 match_id uuid primary key default gen_random_uuid(),
 transaction_id uuid not null references public.mme_treasury_bank_transactions(transaction_id),
 journal_entry_id uuid not null references public.mme_gl_journal_entries(entry_id),
 matched_amount numeric(16,2) not null check(matched_amount>0),
 matched_by_auth_user_id uuid not null,
 matched_at timestamptz not null default now(),
 unique(transaction_id,journal_entry_id)
);
create table if not exists public.mme_treasury_audit(
 audit_id uuid primary key default gen_random_uuid(),
 actor_auth_user_id uuid not null,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create or replace function public.mme_treasury_import_statement(p_account uuid,p_reference text,p_start date,p_end date,p_opening numeric,p_closing numeric,p_rows jsonb,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_statement uuid;v_row jsonb;v_date date;v_amount numeric(16,2);v_desc text;v_type text;v_id text;
begin
 if not exists(select 1 from public.mme_treasury_bank_accounts where bank_account_id=p_account and account_status='active') then raise exception 'active_bank_account_required';end if;
 if coalesce(trim(p_reference),'')='' or p_start is null or p_end<p_start or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>10000 then raise exception 'invalid_statement';end if;
 insert into public.mme_treasury_statements(bank_account_id,statement_reference,period_start,period_end,opening_balance,closing_balance,imported_by_auth_user_id) values(p_account,p_reference,p_start,p_end,p_opening,p_closing,p_actor) returning statement_id into v_statement;
 for v_row in select * from jsonb_array_elements(p_rows) loop
  v_date:=(v_row->>'date')::date;v_amount:=(v_row->>'amount')::numeric;v_desc:=left(coalesce(v_row->>'description','Bank transaction'),500);v_id:=nullif(v_row->>'external_id','');
  if v_date<p_start or v_date>p_end or v_amount=0 or coalesce(v_row->>'currency','USD') !~ '^[A-Za-z]{3}$' then raise exception 'invalid_statement_row';end if;
  v_type:=case when v_amount>0 then 'credit' else 'debit' end;
  insert into public.mme_treasury_bank_transactions(statement_id,external_transaction_id,transaction_date,description,amount,currency,transaction_type,raw_data) values(v_statement,v_id,v_date,v_desc,v_amount,upper(coalesce(v_row->>'currency','USD')),v_type,v_row);
 end loop;
 insert into public.mme_treasury_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'statement_imported','bank_statement',v_statement,jsonb_build_object('row_count',jsonb_array_length(p_rows),'reference',p_reference));
 return v_statement;
end $$;
create or replace function public.mme_treasury_match_transaction(p_transaction uuid,p_entry uuid,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_tx public.mme_treasury_bank_transactions%rowtype;v_entry public.mme_gl_journal_entries%rowtype;v_match uuid;v_sum numeric(16,2);
begin
 select * into v_tx from public.mme_treasury_bank_transactions where transaction_id=p_transaction for update;
 if not found or v_tx.match_status in ('matched','excluded') then raise exception 'transaction_not_matchable';end if;
 select * into v_entry from public.mme_gl_journal_entries where entry_id=p_entry and entry_status='posted';
 if not found then raise exception 'posted_journal_entry_required';end if;
 if v_tx.transaction_date<>v_entry.entry_date then raise exception 'date_mismatch_requires_review';end if;
 if abs(v_tx.amount)<>p_amount then raise exception 'match_amount_must_equal_bank_transaction';end if;
 if (v_tx.amount>0 and not exists(select 1 from public.mme_gl_journal_lines where entry_id=p_entry and debit>0)) or (v_tx.amount<0 and not exists(select 1 from public.mme_gl_journal_lines where entry_id=p_entry and credit>0)) then raise exception 'journal_direction_mismatch';end if;
 select coalesce(sum(matched_amount),0) into v_sum from public.mme_treasury_matches where transaction_id=p_transaction;
 if v_sum+p_amount>abs(v_tx.amount) then raise exception 'match_exceeds_transaction';end if;
 insert into public.mme_treasury_matches(transaction_id,journal_entry_id,matched_amount,matched_by_auth_user_id) values(p_transaction,p_entry,p_amount,p_actor) returning match_id into v_match;
 if v_sum+p_amount=abs(v_tx.amount) then update public.mme_treasury_bank_transactions set match_status='matched' where transaction_id=p_transaction;else update public.mme_treasury_bank_transactions set match_status='suggested' where transaction_id=p_transaction;end if;
 insert into public.mme_treasury_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'transaction_matched','bank_transaction',p_transaction,jsonb_build_object('journal_entry_id',p_entry,'amount',p_amount));
 return v_match;
end $$;
create or replace function public.mme_treasury_reconcile_statement(p_statement uuid,p_gl_balance numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v public.mme_treasury_statements%rowtype;v_id uuid;v_unmatched int;v_diff numeric(16,2);
begin
 select * into v from public.mme_treasury_statements where statement_id=p_statement for update;
 if not found then raise exception 'statement_not_found';end if;
 select count(*) into v_unmatched from public.mme_treasury_bank_transactions where statement_id=p_statement and match_status not in ('matched','excluded');
 v_diff:=round(v.closing_balance-p_gl_balance,2);
 insert into public.mme_treasury_reconciliations(statement_id,bank_account_id,statement_closing_balance,gl_closing_balance,difference,reconciliation_status,prepared_by_auth_user_id) values(p_statement,v.bank_account_id,v.closing_balance,p_gl_balance,v_diff,case when v_diff=0 and v_unmatched=0 then 'reconciled' else 'exception' end,p_actor) on conflict(statement_id) do update set gl_closing_balance=excluded.gl_closing_balance,difference=excluded.difference,reconciliation_status=excluded.reconciliation_status returning reconciliation_id into v_id;
 update public.mme_treasury_statements set import_status=case when v_diff=0 and v_unmatched=0 then 'reconciled' else 'exception' end where statement_id=p_statement;
 insert into public.mme_treasury_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'statement_reconciled','bank_statement',p_statement,jsonb_build_object('difference',v_diff,'unmatched_count',v_unmatched));
 return v_id;
end $$;
alter table public.mme_treasury_bank_accounts enable row level security;alter table public.mme_treasury_statements enable row level security;alter table public.mme_treasury_bank_transactions enable row level security;alter table public.mme_treasury_reconciliations enable row level security;alter table public.mme_treasury_matches enable row level security;alter table public.mme_treasury_audit enable row level security;
revoke all on public.mme_treasury_bank_accounts,public.mme_treasury_statements,public.mme_treasury_bank_transactions,public.mme_treasury_reconciliations,public.mme_treasury_matches,public.mme_treasury_audit from public,anon,authenticated;
grant all on public.mme_treasury_bank_accounts,public.mme_treasury_statements,public.mme_treasury_bank_transactions,public.mme_treasury_reconciliations,public.mme_treasury_matches,public.mme_treasury_audit to service_role;
revoke all on function public.mme_treasury_import_statement(uuid,text,date,date,numeric,numeric,jsonb,uuid) from public,anon,authenticated;
revoke all on function public.mme_treasury_match_transaction(uuid,uuid,numeric,uuid) from public,anon,authenticated;
revoke all on function public.mme_treasury_reconcile_statement(uuid,numeric,uuid) from public,anon,authenticated;
grant execute on function public.mme_treasury_import_statement(uuid,text,date,date,numeric,numeric,jsonb,uuid) to service_role;
grant execute on function public.mme_treasury_match_transaction(uuid,uuid,numeric,uuid) to service_role;
grant execute on function public.mme_treasury_reconcile_statement(uuid,numeric,uuid) to service_role;
commit;