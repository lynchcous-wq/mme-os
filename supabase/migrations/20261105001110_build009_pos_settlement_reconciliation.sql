-- Build 009.30 — POS Payment Reconciliation & Settlement Integrity Intelligence Engine
-- Ledger matching and exception workflow; external processor/bank connectors remain separate trusted workers.
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
  'pos.settlement.view','pos.settlement.reconcile','pos.settlement.exception.manage','pos.settlement.approve','pos.settlement.bank.match','pos.settlement.cash.manage'
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

create table public.mme_pos_settlement_batches (
 id uuid primary key default gen_random_uuid(),
 provider text not null check(provider in ('stripe','verifone','bank','other')),
 provider_account_reference text,
 provider_payout_reference text not null,
 location_id uuid not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 gross_amount_minor bigint not null,
 fee_amount_minor bigint not null,
 net_amount_minor bigint not null,
 expected_arrival_at timestamptz,
 settled_at timestamptz,
 status text not null default 'received' check(status in ('received','reconciling','matched','exception','approved','settled','reversed','closed')),
 source_digest_sha256 text check(source_digest_sha256 is null or source_digest_sha256 ~ '^[a-f0-9]{64}$'),
 imported_at timestamptz not null default now(),
 last_synced_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(provider,provider_payout_reference),
 check(gross_amount_minor-fee_amount_minor=net_amount_minor)
);
create index mme_pos_settlement_batches_location_idx on public.mme_pos_settlement_batches(location_id,status,imported_at desc);

create table public.mme_pos_settlement_lines (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_settlement_batches(id) on delete restrict,
 provider text not null,
 provider_balance_reference text not null,
 line_type text not null check(line_type in ('charge','refund','dispute','dispute_reversal','fee','adjustment','reserve','payout','other')),
 transaction_reference text,
 payment_reference text,
 charge_reference text,
 refund_reference text,
 dispute_reference text,
 amount_minor bigint not null,
 fee_minor bigint not null default 0,
 net_amount_minor bigint generated always as (amount_minor-fee_minor) stored,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 effective_at timestamptz,
 available_at timestamptz,
 source_digest_sha256 text check(source_digest_sha256 is null or source_digest_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default now(),
 unique(provider,provider_balance_reference)
);
create index mme_pos_settlement_lines_batch_idx on public.mme_pos_settlement_lines(batch_id,line_type);
create index mme_pos_settlement_lines_tx_idx on public.mme_pos_settlement_lines(transaction_reference,payment_reference);

create table public.mme_pos_reconciliation_runs (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_settlement_batches(id) on delete restrict,
 location_id uuid not null,
 run_number integer not null check(run_number>0),
 status text not null default 'queued' check(status in ('queued','running','completed','completed_with_exceptions','failed','approved','closed')),
 internal_gross_minor bigint,
 processor_gross_minor bigint,
 internal_fees_minor bigint,
 processor_fees_minor bigint,
 internal_net_minor bigint,
 processor_net_minor bigint,
 matched_count integer not null default 0 check(matched_count>=0),
 exception_count integer not null default 0 check(exception_count>=0),
 started_at timestamptz,
 completed_at timestamptz,
 created_by_person_id uuid,
 created_at timestamptz not null default now(),
 unique(batch_id,run_number)
);

create table public.mme_pos_settlement_matches (
 id uuid primary key default gen_random_uuid(),
 run_id uuid not null references public.mme_pos_reconciliation_runs(id) on delete restrict,
 settlement_line_id uuid not null references public.mme_pos_settlement_lines(id) on delete restrict,
 internal_transaction_reference text not null,
 match_method text not null check(match_method in ('exact_provider_reference','exact_transaction_reference','approved_manual')),
 match_status text not null default 'matched' check(match_status in ('matched','mismatch','duplicate','unmatched','manual_review')),
 internal_amount_minor bigint not null,
 settlement_amount_minor bigint not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 matched_by_person_id uuid,
 matched_at timestamptz not null default now(),
 notes text,
 unique(run_id,settlement_line_id),
 check(match_status<>'matched' or internal_amount_minor=settlement_amount_minor)
);

create table public.mme_pos_settlement_exceptions (
 id uuid primary key default gen_random_uuid(),
 run_id uuid not null references public.mme_pos_reconciliation_runs(id) on delete restrict,
 batch_id uuid not null references public.mme_pos_settlement_batches(id) on delete restrict,
 location_id uuid not null,
 exception_type text not null check(exception_type in ('missing_internal_transaction','missing_processor_line','amount_mismatch','fee_mismatch','currency_mismatch','duplicate_reference','refund_mismatch','dispute_mismatch','late_settlement','unexpected_adjustment','bank_deposit_mismatch','other')),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','assigned','investigating','resolved','accepted_variance','false_positive','escalated')),
 amount_difference_minor bigint,
 currency char(3),
 description text not null check(length(btrim(description)) between 8 and 2000),
 assigned_to_person_id uuid,
 resolution_code text,
 resolution_notes text,
 resolved_by_person_id uuid,
 resolved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_pos_settlement_exceptions_queue_idx on public.mme_pos_settlement_exceptions(location_id,status,severity,created_at desc);

create table public.mme_pos_bank_deposits (
 id uuid primary key default gen_random_uuid(),
 bank_account_reference text not null,
 bank_statement_reference text not null,
 location_id uuid not null,
 deposit_date date not null,
 amount_minor bigint not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 description_masked text,
 source_digest_sha256 text check(source_digest_sha256 is null or source_digest_sha256 ~ '^[a-f0-9]{64}$'),
 imported_at timestamptz not null default now(),
 unique(bank_account_reference,bank_statement_reference)
);
create table public.mme_pos_settlement_bank_matches (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_settlement_batches(id) on delete restrict,
 bank_deposit_id uuid not null references public.mme_pos_bank_deposits(id) on delete restrict,
 match_status text not null default 'pending' check(match_status in ('pending','matched','amount_mismatch','date_mismatch','manual_review')),
 amount_difference_minor bigint not null,
 matched_by_person_id uuid,
 matched_at timestamptz,
 notes text,
 unique(batch_id,bank_deposit_id)
);

create table public.mme_pos_settlement_approvals (
 id uuid primary key default gen_random_uuid(),
 run_id uuid not null references public.mme_pos_reconciliation_runs(id) on delete restrict,
 approver_person_id uuid not null,
 decision text not null check(decision in ('approve','reject','return_for_review')),
 reason text not null check(length(btrim(reason)) between 8 and 1500),
 approved_at timestamptz not null default now()
);

create table public.mme_pos_cash_drawer_closings (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 register_reference text not null,
 business_date date not null,
 opening_float_minor bigint not null check(opening_float_minor>=0),
 cash_sales_minor bigint not null check(cash_sales_minor>=0),
 cash_refunds_minor bigint not null check(cash_refunds_minor>=0),
 paid_out_minor bigint not null default 0 check(paid_out_minor>=0),
 expected_cash_minor bigint generated always as (opening_float_minor+cash_sales_minor-cash_refunds_minor-paid_out_minor) stored,
 counted_cash_minor bigint check(counted_cash_minor is null or counted_cash_minor>=0),
 variance_minor bigint generated always as (counted_cash_minor-expected_cash_minor) stored,
 counted_by_person_id uuid,
 witnessed_by_person_id uuid,
 status text not null default 'open' check(status in ('open','counted','variance_review','approved','closed')),
 counted_at timestamptz,
 approved_by_person_id uuid,
 approved_at timestamptz,
 notes text check(notes is null or length(notes)<=1500),
 created_at timestamptz not null default now(),
 unique(location_id,register_reference,business_date),
 check(counted_by_person_id is null or witnessed_by_person_id is null or counted_by_person_id<>witnessed_by_person_id),
 check(approved_by_person_id is null or approved_by_person_id<>counted_by_person_id)
);
alter table public.mme_pos_cash_drawer_closings enable row level security;
revoke all on public.mme_pos_cash_drawer_closings from public,anon,authenticated;
grant all on public.mme_pos_cash_drawer_closings to service_role;

create table public.mme_pos_settlement_audit_events (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 actor_person_id uuid,
 action text not null,
 object_type text not null,
 object_reference text not null,
 reason text not null check(length(btrim(reason)) between 8 and 1500),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_settlement_audit_idx on public.mme_pos_settlement_audit_events(location_id,occurred_at desc);

alter table public.mme_pos_settlement_batches enable row level security;
alter table public.mme_pos_settlement_lines enable row level security;
alter table public.mme_pos_reconciliation_runs enable row level security;
alter table public.mme_pos_settlement_matches enable row level security;
alter table public.mme_pos_settlement_exceptions enable row level security;
alter table public.mme_pos_bank_deposits enable row level security;
alter table public.mme_pos_settlement_bank_matches enable row level security;
alter table public.mme_pos_settlement_approvals enable row level security;
alter table public.mme_pos_cash_drawer_closings enable row level security;
alter table public.mme_pos_settlement_audit_events enable row level security;
revoke all on public.mme_pos_settlement_batches,public.mme_pos_settlement_lines,public.mme_pos_reconciliation_runs,
 public.mme_pos_settlement_matches,public.mme_pos_settlement_exceptions,public.mme_pos_bank_deposits,
 public.mme_pos_settlement_bank_matches,public.mme_pos_settlement_approvals,public.mme_pos_settlement_audit_events,public.mme_pos_cash_drawer_closings from public,anon,authenticated;
grant all on public.mme_pos_settlement_batches,public.mme_pos_settlement_lines,public.mme_pos_reconciliation_runs,
 public.mme_pos_settlement_matches,public.mme_pos_settlement_exceptions,public.mme_pos_bank_deposits,
 public.mme_pos_settlement_bank_matches,public.mme_pos_settlement_approvals,public.mme_pos_settlement_audit_events,public.mme_pos_cash_drawer_closings to service_role;

create or replace function public.mme_pos_authorize_settlement_action(p_actor_person_id uuid,p_location_id uuid,p_permission text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_permission not in ('pos.settlement.view','pos.settlement.reconcile','pos.settlement.exception.manage','pos.settlement.approve','pos.settlement.bank.match','pos.settlement.cash.manage') then return false; end if;
 return public.mme_pos_authorize_hardware_action(p_actor_person_id,p_permission,p_location_id);
end;
$$;

create or replace function public.mme_pos_create_settlement_run(p_batch_id uuid,p_actor_person_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_settlement_batches%rowtype; v_run integer; v_id uuid;
begin
 select * into v_batch from public.mme_pos_settlement_batches where id=p_batch_id for update;
 if not found then raise exception 'Settlement batch not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_batch.location_id,'pos.settlement.reconcile') then
  raise exception 'Settlement reconciliation permission denied' using errcode='42501';
 end if;
 select coalesce(max(run_number),0)+1 into v_run from public.mme_pos_reconciliation_runs where batch_id=p_batch_id;
 insert into public.mme_pos_reconciliation_runs(batch_id,location_id,run_number,status,created_by_person_id,started_at)
 values(p_batch_id,v_batch.location_id,v_run,'running',p_actor_person_id,now()) returning id into v_id;
 update public.mme_pos_settlement_batches set status='reconciling',updated_at=now() where id=p_batch_id;
 insert into public.mme_pos_settlement_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(v_batch.location_id,p_actor_person_id,'reconciliation_started','settlement_batch',p_batch_id::text,'Authorized reconciliation run started.');
 return v_id;
end;
$$;

create or replace function public.mme_pos_match_settlement_line(
 p_run_id uuid,p_line_id uuid,p_internal_transaction_reference text,p_internal_amount_minor bigint,
 p_currency text,p_actor_person_id uuid,p_match_method text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_run public.mme_pos_reconciliation_runs%rowtype; v_line public.mme_pos_settlement_lines%rowtype; v_status text; v_id uuid;
begin
 select * into v_run from public.mme_pos_reconciliation_runs where id=p_run_id for update;
 if not found then raise exception 'Reconciliation run not found' using errcode='P0002'; end if;
 select * into v_line from public.mme_pos_settlement_lines where id=p_line_id;
 if not found or v_line.batch_id<>v_run.batch_id then raise exception 'Settlement line does not belong to run batch' using errcode='42501'; end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_run.location_id,'pos.settlement.reconcile') then
  raise exception 'Settlement matching permission denied' using errcode='42501';
 end if;
 if v_run.status<>'running' or p_internal_amount_minor is null or p_currency !~ '^[A-Z]{3}$' then
  raise exception 'Invalid reconciliation state or amount' using errcode='22023';
 end if;
 if exists(select 1 from public.mme_pos_settlement_matches where run_id=p_run_id and internal_transaction_reference=p_internal_transaction_reference) then
  v_status:='duplicate';
 elsif v_line.currency<>p_currency then v_status:='mismatch';
 elsif v_line.net_amount_minor<>p_internal_amount_minor then v_status:='mismatch';
 else v_status:='matched'; end if;
 if p_match_method='approved_manual' and not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_run.location_id,'pos.settlement.exception.manage') then
  raise exception 'Manual match permission denied' using errcode='42501';
 end if;
 insert into public.mme_pos_settlement_matches(run_id,settlement_line_id,internal_transaction_reference,match_method,match_status,
  internal_amount_minor,settlement_amount_minor,currency,matched_by_person_id,notes)
 values(p_run_id,p_line_id,p_internal_transaction_reference,p_match_method,v_status,p_internal_amount_minor,v_line.net_amount_minor,
  p_currency,p_actor_person_id,case when v_status='matched' then null else 'Requires exception review; no automatic adjustment posted.' end)
 returning id into v_id;
 if v_status<>'matched' then
  insert into public.mme_pos_settlement_exceptions(run_id,batch_id,location_id,exception_type,severity,status,
   amount_difference_minor,currency,description)
  values(p_run_id,v_run.batch_id,v_run.location_id,case when v_status='duplicate' then 'duplicate_reference'
   when v_line.currency<>p_currency then 'currency_mismatch' else 'amount_mismatch' end,
   case when v_status='duplicate' then 'high' else 'medium' end,'open',
   v_line.net_amount_minor-p_internal_amount_minor,p_currency,
   'Settlement line did not produce a unique exact match; review source records before resolution.');
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_complete_settlement_run(p_run_id uuid,p_actor_person_id uuid)
returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_run public.mme_pos_reconciliation_runs%rowtype; v_batch public.mme_pos_settlement_batches%rowtype;
 v_matched integer; v_exceptions integer; v_unmatched integer; v_open_exceptions integer; v_gross bigint; v_fees bigint; v_net bigint;
begin
 select * into v_run from public.mme_pos_reconciliation_runs where id=p_run_id for update;
 if not found then raise exception 'Reconciliation run not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_run.location_id,'pos.settlement.reconcile') then
  raise exception 'Settlement completion permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_settlement_batches where id=v_run.batch_id;
 if v_run.status<>'running' then raise exception 'Reconciliation run is not active' using errcode='55000'; end if;
 select count(*) filter(where match_status='matched'),count(*) filter(where match_status<>'matched')
 into v_matched,v_exceptions from public.mme_pos_settlement_matches where run_id=p_run_id;
 select count(*) into v_unmatched from public.mme_pos_settlement_lines l where l.batch_id=v_batch.id
  and not exists(select 1 from public.mme_pos_settlement_matches m where m.run_id=p_run_id and m.settlement_line_id=l.id);
 select count(*) into v_open_exceptions from public.mme_pos_settlement_exceptions e where e.run_id=p_run_id
  and e.status not in ('resolved','accepted_variance','false_positive');
 v_exceptions:=v_exceptions+v_unmatched+v_open_exceptions;
 select coalesce(sum(amount_minor),0),coalesce(sum(fee_minor),0),coalesce(sum(net_amount_minor),0)
 into v_gross,v_fees,v_net from public.mme_pos_settlement_lines where batch_id=v_batch.id;
 update public.mme_pos_reconciliation_runs set status=case when v_exceptions=0 then 'completed' else 'completed_with_exceptions' end,
  processor_gross_minor=v_gross,processor_fees_minor=v_fees,processor_net_minor=v_net,
  matched_count=v_matched,exception_count=v_exceptions,completed_at=now() where id=p_run_id;
 update public.mme_pos_settlement_batches set status=case when v_exceptions=0 then 'matched' else 'exception' end,updated_at=now()
 where id=v_batch.id;
 insert into public.mme_pos_settlement_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason,metadata)
 values(v_run.location_id,p_actor_person_id,'reconciliation_completed','reconciliation_run',p_run_id::text,
  'Reconciliation run completed; exceptions remain subject to review.',
  jsonb_build_object('matched_count',v_matched,'exception_count',v_exceptions));
 return true;
end;
$$;

create or replace function public.mme_pos_approve_settlement_run(p_run_id uuid,p_approver_person_id uuid,p_decision text,p_reason text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_run public.mme_pos_reconciliation_runs%rowtype; v_id uuid;
begin
 select * into v_run from public.mme_pos_reconciliation_runs where id=p_run_id for update;
 if not found then raise exception 'Reconciliation run not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_settlement_action(p_approver_person_id,v_run.location_id,'pos.settlement.approve') then
  raise exception 'Settlement approval permission denied' using errcode='42501';
 end if;
 if v_run.created_by_person_id=p_approver_person_id or v_run.status not in ('completed','completed_with_exceptions')
  or p_decision not in ('approve','reject','return_for_review') or length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'Independent approval, completed run and reason required' using errcode='42501';
 end if;
 insert into public.mme_pos_settlement_approvals(run_id,approver_person_id,decision,reason)
 values(p_run_id,p_approver_person_id,p_decision,p_reason) returning id into v_id;
 if p_decision='approve' and (v_run.exception_count>0 or exists(select 1 from public.mme_pos_settlement_exceptions e where e.run_id=p_run_id and e.status not in ('resolved','accepted_variance','false_positive')) or exists(select 1 from public.mme_pos_settlement_matches m where m.run_id=p_run_id and m.match_status<>'matched')) then
  raise exception 'Unmatched lines or unresolved exceptions prevent settlement approval' using errcode='55000';
 end if;
 if p_decision='approve' then update public.mme_pos_reconciliation_runs set status='approved' where id=p_run_id; end if;
 insert into public.mme_pos_settlement_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(v_run.location_id,p_approver_person_id,'settlement_run_'||p_decision,'reconciliation_run',p_run_id::text,p_reason);
 return v_id;
end;
$$;

revoke all on function public.mme_pos_authorize_settlement_action(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_create_settlement_run(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_match_settlement_line(uuid,uuid,text,bigint,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_complete_settlement_run(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_approve_settlement_run(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_settlement_action(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_create_settlement_run(uuid,uuid) to service_role;
grant execute on function public.mme_pos_match_settlement_line(uuid,uuid,text,bigint,text,uuid,text) to service_role;
grant execute on function public.mme_pos_complete_settlement_run(uuid,uuid) to service_role;
grant execute on function public.mme_pos_approve_settlement_run(uuid,uuid,text,text) to service_role;

comment on table public.mme_pos_cash_drawer_closings is 'Register cash close, independent witness and variance review; drawer command state is reconciled separately.';
comment on table public.mme_pos_settlement_batches is 'Imported processor payout/settlement batches. Amounts are integer minor units and net equals gross minus fees.';
comment on table public.mme_pos_settlement_lines is 'Normalized provider balance lines. Store processor references, never raw payment credentials.';
comment on table public.mme_pos_settlement_matches is 'Exact or authorized manual transaction matching. Does not mutate the POS or general ledger.';
comment on table public.mme_pos_settlement_exceptions is 'Unmatched, duplicate, amount, fee, currency, dispute and deposit reconciliation exceptions.';
commit;
