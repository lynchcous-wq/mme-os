-- Build 009.31 — Settlement Exception Resolution & Financial Close Automation
-- Additive workflow layer over Build 009.30. No money movement.
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
  'pos.settlement.adjustment.request'
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

create table public.mme_pos_settlement_exception_history (
 id uuid primary key default gen_random_uuid(),
 exception_id uuid not null references public.mme_pos_settlement_exceptions(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 action text not null check(action in ('assigned','status_changed','resolved','accepted_variance','false_positive','escalated','note_added')),
 previous_status text,
 new_status text,
 assigned_to_person_id uuid,
 resolution_code text,
 reason text not null check(length(btrim(reason)) between 8 and 1500),
 evidence_reference text,
 occurred_at timestamptz not null default now()
);
create index mme_pos_exception_history_idx on public.mme_pos_settlement_exception_history(exception_id,occurred_at);

create table public.mme_pos_settlement_adjustment_requests (
 id uuid primary key default gen_random_uuid(),
 exception_id uuid not null references public.mme_pos_settlement_exceptions(id) on delete restrict,
 location_id uuid not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 amount_minor bigint not null check(amount_minor<>0),
 adjustment_type text not null check(adjustment_type in ('fee_correction','timing_correction','rounding','processor_correction','cash_over_short','other')),
 explanation text not null check(length(btrim(explanation)) between 12 and 2000),
 source_evidence_reference text not null,
 requested_by_person_id uuid not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','posted_to_ledger','cancelled')),
 reviewed_by_person_id uuid,
 review_reason text,
 reviewed_at timestamptz,
 posted_reference text,
 created_at timestamptz not null default now(),
 check(reviewed_by_person_id is null or reviewed_by_person_id<>requested_by_person_id)
);
create index mme_pos_adjustment_queue_idx on public.mme_pos_settlement_adjustment_requests(location_id,status,created_at);

create table public.mme_pos_financial_closes (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 business_period_start timestamptz not null,
 business_period_end timestamptz not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 status text not null default 'preparing' check(status in ('preparing','blocked','ready_for_approval','approved','closed','reopened')),
 settlement_run_count integer not null default 0 check(settlement_run_count>=0),
 open_exception_count integer not null default 0 check(open_exception_count>=0),
 unmatched_bank_deposit_count integer not null default 0 check(unmatched_bank_deposit_count>=0),
 unapproved_cash_close_count integer not null default 0 check(unapproved_cash_close_count>=0),
 cash_variance_count integer not null default 0 check(cash_variance_count>=0),
 processor_net_minor bigint not null default 0,
 bank_deposit_net_minor bigint not null default 0,
 cash_variance_minor bigint not null default 0,
 prepared_by_person_id uuid not null,
 approved_by_person_id uuid,
 approved_at timestamptz,
 closed_by_person_id uuid,
 closed_at timestamptz,
 reopened_by_person_id uuid,
 reopened_at timestamptz,
 reopen_reason text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(business_period_end>business_period_start),
 check(approved_by_person_id is null or approved_by_person_id<>prepared_by_person_id),
 check(closed_by_person_id is null or approved_by_person_id=closed_by_person_id),
 unique(location_id,business_period_start,business_period_end,currency)
);
create index mme_pos_financial_closes_queue_idx on public.mme_pos_financial_closes(location_id,status,business_period_end desc);

create table public.mme_pos_financial_close_items (
 id uuid primary key default gen_random_uuid(),
 close_id uuid not null references public.mme_pos_financial_closes(id) on delete restrict,
 item_type text not null check(item_type in ('settlement_run','exception','bank_deposit','cash_close','adjustment')),
 source_reference text not null,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 amount_minor bigint not null default 0,
 source_status text not null,
 captured_at timestamptz not null default now(),
 unique(close_id,item_type,source_reference)
);

create table public.mme_pos_financial_close_events (
 id uuid primary key default gen_random_uuid(),
 close_id uuid not null references public.mme_pos_financial_closes(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('prepared','blocked','refreshed','approved','closed','reopened')),
 reason text not null check(length(btrim(reason)) between 8 and 1500),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);

alter table public.mme_pos_settlement_exception_history enable row level security;
alter table public.mme_pos_settlement_adjustment_requests enable row level security;
alter table public.mme_pos_financial_closes enable row level security;
alter table public.mme_pos_financial_close_items enable row level security;
alter table public.mme_pos_financial_close_events enable row level security;
revoke all on public.mme_pos_settlement_exception_history,public.mme_pos_settlement_adjustment_requests,
 public.mme_pos_financial_closes,public.mme_pos_financial_close_items,public.mme_pos_financial_close_events
 from public,anon,authenticated;
grant all on public.mme_pos_settlement_exception_history,public.mme_pos_settlement_adjustment_requests,
 public.mme_pos_financial_closes,public.mme_pos_financial_close_items,public.mme_pos_financial_close_events
 to service_role;

create or replace function public.mme_pos_assign_settlement_exception(
 p_exception_id uuid,p_assignee_person_id uuid,p_actor_person_id uuid,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_exception public.mme_pos_settlement_exceptions%rowtype;
begin
 select * into v_exception from public.mme_pos_settlement_exceptions where id=p_exception_id for update;
 if not found then raise exception 'Settlement exception not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.settlement.exception.manage',v_exception.location_id) then
  raise exception 'Exception assignment permission denied' using errcode='42501';
 end if;
 if p_assignee_person_id is null or length(btrim(coalesce(p_reason,'')))<8 or v_exception.status in ('resolved','accepted_variance','false_positive') then
  raise exception 'Active exception, assignee and reason required' using errcode='22023';
 end if;
 if not exists(select 1 from public.mme_person_identities i join public.employee_relationships e using(person_id)
  where i.person_id=p_assignee_person_id and i.lifecycle_status='active' and e.employment_status='active') then
  raise exception 'Assignee must be an active employee' using errcode='42501';
 end if;
 update public.mme_pos_settlement_exceptions set assigned_to_person_id=p_assignee_person_id,
  status=case when status='open' then 'assigned' else status end,updated_at=now() where id=p_exception_id;
 insert into public.mme_pos_settlement_exception_history(exception_id,location_id,actor_person_id,action,previous_status,new_status,assigned_to_person_id,reason)
 values(p_exception_id,v_exception.location_id,p_actor_person_id,'assigned',v_exception.status,
  case when v_exception.status='open' then 'assigned' else v_exception.status end,p_assignee_person_id,p_reason);
 return true;
end;
$$;

create or replace function public.mme_pos_resolve_settlement_exception(
 p_exception_id uuid,p_actor_person_id uuid,p_resolution_code text,p_resolution_notes text,
 p_evidence_reference text,p_accept_variance boolean default false
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_exception public.mme_pos_settlement_exceptions%rowtype; v_next_status text;
begin
 select * into v_exception from public.mme_pos_settlement_exceptions where id=p_exception_id for update;
 if not found then raise exception 'Settlement exception not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.settlement.exception.manage',v_exception.location_id) then
  raise exception 'Exception resolution permission denied' using errcode='42501';
 end if;
 if v_exception.status in ('resolved','accepted_variance','false_positive') or length(btrim(coalesce(p_resolution_code,'')))<3
  or length(btrim(coalesce(p_resolution_notes,'')))<12 or length(btrim(coalesce(p_evidence_reference,'')))<3 then
  raise exception 'Resolution code, explanation and evidence reference are required' using errcode='22023';
 end if;
 if p_accept_variance and not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.settlement.adjustment.request',v_exception.location_id) then
  raise exception 'Variance acceptance permission denied' using errcode='42501';
 end if;
 v_next_status:=case when p_accept_variance then 'accepted_variance' else 'resolved' end;
 update public.mme_pos_settlement_exceptions set status=v_next_status,resolution_code=p_resolution_code,
  resolution_notes=p_resolution_notes,resolved_by_person_id=p_actor_person_id,resolved_at=now(),updated_at=now()
 where id=p_exception_id;
 insert into public.mme_pos_settlement_exception_history(exception_id,location_id,actor_person_id,action,previous_status,new_status,resolution_code,reason,evidence_reference)
 values(p_exception_id,v_exception.location_id,p_actor_person_id,case when p_accept_variance then 'accepted_variance' else 'resolved' end,
  v_exception.status,v_next_status,p_resolution_code,p_resolution_notes,p_evidence_reference);
 insert into public.mme_pos_settlement_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason,metadata)
 values(v_exception.location_id,p_actor_person_id,'settlement_exception_'||v_next_status,'settlement_exception',p_exception_id::text,
  p_resolution_notes,jsonb_build_object('resolution_code',p_resolution_code,'evidence_reference',p_evidence_reference));
 return true;
end;
$$;

create or replace function public.mme_pos_request_settlement_adjustment(
 p_exception_id uuid,p_actor_person_id uuid,p_currency text,p_amount_minor bigint,p_adjustment_type text,
 p_explanation text,p_source_evidence_reference text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_exception public.mme_pos_settlement_exceptions%rowtype; v_id uuid;
begin
 select * into v_exception from public.mme_pos_settlement_exceptions where id=p_exception_id for update;
 if not found then raise exception 'Settlement exception not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.settlement.adjustment.request',v_exception.location_id) then
  raise exception 'Adjustment request permission denied' using errcode='42501';
 end if;
 if p_currency !~ '^[A-Z]{3}$' or p_amount_minor=0 or length(btrim(coalesce(p_explanation,'')))<12
  or length(btrim(coalesce(p_source_evidence_reference,'')))<3 then
  raise exception 'Valid currency, non-zero amount, explanation and source evidence are required' using errcode='22023';
 end if;
 insert into public.mme_pos_settlement_adjustment_requests(exception_id,location_id,currency,amount_minor,adjustment_type,
  explanation,source_evidence_reference,requested_by_person_id)
 values(p_exception_id,v_exception.location_id,p_currency,p_amount_minor,p_adjustment_type,p_explanation,
  p_source_evidence_reference,p_actor_person_id) returning id into v_id;
 insert into public.mme_pos_settlement_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason,metadata)
 values(v_exception.location_id,p_actor_person_id,'settlement_adjustment_requested','adjustment_request',v_id::text,p_explanation,
  jsonb_build_object('amount_minor',p_amount_minor,'currency',p_currency,'exception_id',p_exception_id));
 return v_id;
end;
$$;

create or replace function public.mme_pos_review_settlement_adjustment(
 p_adjustment_id uuid,p_reviewer_person_id uuid,p_decision text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_adjustment public.mme_pos_settlement_adjustment_requests%rowtype;
begin
 select * into v_adjustment from public.mme_pos_settlement_adjustment_requests where id=p_adjustment_id for update;
 if not found then raise exception 'Adjustment request not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_reviewer_person_id,'pos.settlement.approve',v_adjustment.location_id) then
  raise exception 'Adjustment review permission denied' using errcode='42501';
 end if;
 if p_reviewer_person_id=v_adjustment.requested_by_person_id or v_adjustment.status<>'pending'
  or p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'Independent reviewer, pending request and reason required' using errcode='42501';
 end if;
 update public.mme_pos_settlement_adjustment_requests set status=case when p_decision='approve' then 'approved' else 'rejected' end,
  reviewed_by_person_id=p_reviewer_person_id,review_reason=p_reason,reviewed_at=now() where id=p_adjustment_id;
 insert into public.mme_pos_settlement_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(v_adjustment.location_id,p_reviewer_person_id,'settlement_adjustment_'||p_decision,'adjustment_request',p_adjustment_id::text,p_reason);
 return true;
end;
$$;

create or replace function public.mme_pos_prepare_financial_close(
 p_location_id uuid,p_period_start timestamptz,p_period_end timestamptz,p_currency text,p_actor_person_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_runs integer; v_exceptions integer; v_unmatched_bank integer; v_cash_unapproved integer;
 v_cash_variances integer; v_processor_net bigint; v_bank_net bigint; v_cash_variance bigint; v_status text;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.settlement.close.prepare',p_location_id) then
  raise exception 'Financial close preparation permission denied' using errcode='42501';
 end if;
 if p_period_end<=p_period_start or p_currency !~ '^[A-Z]{3}$' then raise exception 'Invalid financial close period or currency' using errcode='22023'; end if;
 select count(*),coalesce(sum(b.net_amount_minor),0) into v_runs,v_processor_net
 from public.mme_pos_reconciliation_runs r join public.mme_pos_settlement_batches b on b.id=r.batch_id
 where r.location_id=p_location_id and r.status in ('approved','closed') and b.currency=p_currency
  and b.settled_at>=p_period_start and b.settled_at<p_period_end;
 select count(*) into v_exceptions from public.mme_pos_settlement_exceptions e
 join public.mme_pos_reconciliation_runs r on r.id=e.run_id
 where e.location_id=p_location_id and r.status in ('approved','closed')
  and e.status not in ('resolved','accepted_variance','false_positive')
  and exists(select 1 from public.mme_pos_settlement_batches b where b.id=e.batch_id and b.currency=p_currency and b.settled_at>=p_period_start and b.settled_at<p_period_end);
 select count(*),coalesce(sum(d.amount_minor),0) into v_unmatched_bank,v_bank_net
 from public.mme_pos_settlement_bank_matches m join public.mme_pos_bank_deposits d on d.id=m.bank_deposit_id
 join public.mme_pos_settlement_batches b on b.id=m.batch_id
 where b.location_id=p_location_id and b.currency=p_currency and b.settled_at>=p_period_start and b.settled_at<p_period_end
  and m.match_status<>'matched';
 select count(*) into v_cash_unapproved from public.mme_pos_cash_drawer_closings c
 where c.location_id=p_location_id and c.business_date between (p_period_start at time zone 'UTC')::date and ((p_period_end - interval '1 microsecond') at time zone 'UTC')::date
  and c.status not in ('approved','closed');
 select count(*),coalesce(sum(variance_minor),0) into v_cash_variances,v_cash_variance
 from public.mme_pos_cash_drawer_closings c
 where c.location_id=p_location_id and c.business_date between (p_period_start at time zone 'UTC')::date and ((p_period_end - interval '1 microsecond') at time zone 'UTC')::date
  and c.variance_minor is not null and c.variance_minor<>0;
 v_status:=case when v_exceptions=0 and v_unmatched_bank=0 and v_cash_unapproved=0 and v_cash_variances=0
  and v_processor_net=v_bank_net then 'ready_for_approval' else 'blocked' end;
 insert into public.mme_pos_financial_closes(location_id,business_period_start,business_period_end,currency,status,
  settlement_run_count,open_exception_count,unmatched_bank_deposit_count,unapproved_cash_close_count,cash_variance_count,
  processor_net_minor,bank_deposit_net_minor,cash_variance_minor,prepared_by_person_id)
 values(p_location_id,p_period_start,p_period_end,p_currency,v_status,v_runs,v_exceptions,v_unmatched_bank,
  v_cash_unapproved,v_cash_variances,v_processor_net,v_bank_net,v_cash_variance,p_actor_person_id)
 on conflict(location_id,business_period_start,business_period_end,currency) do update set
  status=excluded.status,settlement_run_count=excluded.settlement_run_count,open_exception_count=excluded.open_exception_count,
  unmatched_bank_deposit_count=excluded.unmatched_bank_deposit_count,unapproved_cash_close_count=excluded.unapproved_cash_close_count,
  cash_variance_count=excluded.cash_variance_count,processor_net_minor=excluded.processor_net_minor,
  bank_deposit_net_minor=excluded.bank_deposit_net_minor,cash_variance_minor=excluded.cash_variance_minor,
  prepared_by_person_id=excluded.prepared_by_person_id,updated_at=now()
 where public.mme_pos_financial_closes.status not in ('approved','closed')
 returning id into v_id;
 if v_id is null then raise exception 'Financial close already approved or closed; reopen through authorized workflow before refresh' using errcode='55000'; end if;
 insert into public.mme_pos_financial_close_items(close_id,item_type,source_reference,currency,amount_minor,source_status)
 select v_id,'settlement_run',r.id::text,p_currency,b.net_amount_minor,r.status
 from public.mme_pos_reconciliation_runs r join public.mme_pos_settlement_batches b on b.id=r.batch_id
 where r.location_id=p_location_id and r.status in ('approved','closed') and b.currency=p_currency and b.settled_at>=p_period_start and b.settled_at<p_period_end
 on conflict(close_id,item_type,source_reference) do update set amount_minor=excluded.amount_minor,source_status=excluded.source_status,captured_at=now();
 insert into public.mme_pos_financial_close_events(close_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_id,p_location_id,p_actor_person_id,case when v_status='blocked' then 'blocked' else 'prepared' end,
  'Financial close snapshot prepared from approved processor and bank records.',
  jsonb_build_object('settlement_runs',v_runs,'open_exceptions',v_exceptions,'unmatched_bank',v_unmatched_bank,
   'unapproved_cash_closes',v_cash_unapproved,'cash_variances',v_cash_variances,'processor_net_minor',v_processor_net,'bank_deposit_net_minor',v_bank_net));
 return v_id;
end;
$$;

create or replace function public.mme_pos_approve_financial_close(
 p_close_id uuid,p_approver_person_id uuid,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_close public.mme_pos_financial_closes%rowtype;
begin
 select * into v_close from public.mme_pos_financial_closes where id=p_close_id for update;
 if not found then raise exception 'Financial close not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_approver_person_id,'pos.settlement.close.approve',v_close.location_id) then
  raise exception 'Financial close approval permission denied' using errcode='42501';
 end if;
 if p_approver_person_id=v_close.prepared_by_person_id or v_close.status<>'ready_for_approval'
  or length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'Independent approver, ready close and reason required' using errcode='42501';
 end if;
 update public.mme_pos_financial_closes set status='approved',approved_by_person_id=p_approver_person_id,approved_at=now(),updated_at=now() where id=p_close_id;
 insert into public.mme_pos_financial_close_events(close_id,location_id,actor_person_id,event_type,reason)
 values(p_close_id,v_close.location_id,p_approver_person_id,'approved',p_reason);
 return true;
end;
$$;

create or replace function public.mme_pos_finalize_financial_close(
 p_close_id uuid,p_actor_person_id uuid,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_close public.mme_pos_financial_closes%rowtype;
begin
 select * into v_close from public.mme_pos_financial_closes where id=p_close_id for update;
 if not found then raise exception 'Financial close not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.settlement.close.approve',v_close.location_id) then
  raise exception 'Financial close finalization permission denied' using errcode='42501';
 end if;
 if v_close.status<>'approved' or p_actor_person_id<>v_close.approved_by_person_id or length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'Only the recorded approver may finalize an approved close with a reason' using errcode='42501';
 end if;
 update public.mme_pos_financial_closes set status='closed',closed_by_person_id=p_actor_person_id,closed_at=now(),updated_at=now() where id=p_close_id;
 insert into public.mme_pos_financial_close_events(close_id,location_id,actor_person_id,event_type,reason)
 values(p_close_id,v_close.location_id,p_actor_person_id,'closed',p_reason);
 return true;
end;
$$;

create or replace function public.mme_pos_reopen_financial_close(
 p_close_id uuid,p_actor_person_id uuid,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_close public.mme_pos_financial_closes%rowtype;
begin
 select * into v_close from public.mme_pos_financial_closes where id=p_close_id for update;
 if not found then raise exception 'Financial close not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.settlement.close.approve',v_close.location_id) then
  raise exception 'Financial close reopen permission denied' using errcode='42501';
 end if;
 if v_close.status<>'closed' or length(btrim(coalesce(p_reason,'')))<12 then
  raise exception 'Closed period and detailed reopen reason required' using errcode='55000';
 end if;
 update public.mme_pos_financial_closes set status='reopened',reopened_by_person_id=p_actor_person_id,reopened_at=now(),
  reopen_reason=p_reason,updated_at=now() where id=p_close_id;
 insert into public.mme_pos_financial_close_events(close_id,location_id,actor_person_id,event_type,reason)
 values(p_close_id,v_close.location_id,p_actor_person_id,'reopened',p_reason);
 return true;
end;
$$;

revoke all on function public.mme_pos_assign_settlement_exception(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_resolve_settlement_exception(uuid,uuid,text,text,text,boolean) from public,anon,authenticated;
revoke all on function public.mme_pos_request_settlement_adjustment(uuid,uuid,text,bigint,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_review_settlement_adjustment(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_prepare_financial_close(uuid,timestamptz,timestamptz,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_approve_financial_close(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_finalize_financial_close(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_reopen_financial_close(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_pos_assign_settlement_exception(uuid,uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_resolve_settlement_exception(uuid,uuid,text,text,text,boolean) to service_role;
grant execute on function public.mme_pos_request_settlement_adjustment(uuid,uuid,text,bigint,text,text,text) to service_role;
grant execute on function public.mme_pos_review_settlement_adjustment(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_pos_prepare_financial_close(uuid,timestamptz,timestamptz,text,uuid) to service_role;
grant execute on function public.mme_pos_approve_financial_close(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_finalize_financial_close(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_reopen_financial_close(uuid,uuid,text) to service_role;

comment on table public.mme_pos_settlement_exception_history is 'Append-only exception assignment, investigation, resolution and evidence-reference history.';
comment on table public.mme_pos_settlement_adjustment_requests is 'Proposed accounting adjustments; approval does not itself post money or mutate processor records.';
comment on table public.mme_pos_financial_closes is 'Store- and currency-scoped financial close snapshots with independent approval and controlled reopen.';
comment on table public.mme_pos_financial_close_items is 'Source snapshot references captured during financial close preparation.';
commit;
