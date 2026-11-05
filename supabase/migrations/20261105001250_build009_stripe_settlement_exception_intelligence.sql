-- Build 009.45 — Stripe settlement exception intelligence and controlled case management.
begin;

create table public.mme_pos_stripe_settlement_exception_cases (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 settlement_batch_id uuid not null references public.mme_pos_settlement_batches(id) on delete restrict,
 settlement_line_id uuid references public.mme_pos_settlement_lines(id) on delete restrict,
 refund_request_id uuid references public.mme_pos_refund_requests(id) on delete restrict,
 refund_match_id uuid references public.mme_pos_stripe_refund_settlement_matches(id) on delete restrict,
 exception_type text not null check(exception_type in (
  'missing_internal_refund','missing_processor_refund','amount_mismatch','currency_mismatch',
  'connected_account_mismatch','duplicate_refund','manual_review','closed_period','financial_fact_conflict'
 )),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','assigned','investigating','escalated','resolved','accepted_variance','false_positive')),
 amount_minor bigint,
 currency char(3) check(currency is null or currency ~ '^[A-Z]{3}$'),
 discrepancy_code text not null check(length(btrim(discrepancy_code)) between 3 and 120),
 description text not null check(length(btrim(description)) between 8 and 2000),
 assigned_to_person_id uuid,
 due_at timestamptz,
 resolution_code text,
 resolution_notes text,
 resolved_by_person_id uuid,
 resolved_at timestamptz,
 first_detected_at timestamptz not null default now(),
 last_detected_at timestamptz not null default now(),
 escalation_level integer not null default 0 check(escalation_level between 0 and 3),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(status not in ('resolved','accepted_variance','false_positive') or (resolved_by_person_id is not null and resolved_at is not null and resolution_code is not null))
);
create unique index mme_pos_stripe_exception_match_unique
 on public.mme_pos_stripe_settlement_exception_cases(refund_match_id,exception_type)
 where refund_match_id is not null;
create unique index mme_pos_stripe_exception_line_unique
 on public.mme_pos_stripe_settlement_exception_cases(settlement_line_id,exception_type)
 where settlement_line_id is not null and refund_match_id is null;
create unique index mme_pos_stripe_exception_refund_unique
 on public.mme_pos_stripe_settlement_exception_cases(refund_request_id,exception_type)
 where refund_request_id is not null and settlement_line_id is null;
create index mme_pos_stripe_exception_queue_idx
 on public.mme_pos_stripe_settlement_exception_cases(location_id,status,severity,due_at,created_at desc);
create index mme_pos_stripe_exception_batch_idx
 on public.mme_pos_stripe_settlement_exception_cases(settlement_batch_id,exception_type,status);

create table public.mme_pos_stripe_settlement_exception_events (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_pos_stripe_settlement_exception_cases(id) on delete restrict,
 actor_person_id uuid,
 event_type text not null check(event_type in ('detected','reopened','assigned','unassigned','investigating','escalated','resolved','accepted_variance','false_positive','note')),
 detail_code text not null,
 notes text check(notes is null or length(notes)<=2000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_stripe_exception_events_idx
 on public.mme_pos_stripe_settlement_exception_events(case_id,occurred_at desc);

alter table public.mme_pos_stripe_settlement_exception_cases enable row level security;
alter table public.mme_pos_stripe_settlement_exception_events enable row level security;
revoke all on public.mme_pos_stripe_settlement_exception_cases,public.mme_pos_stripe_settlement_exception_events
 from public,anon,authenticated;
grant all on public.mme_pos_stripe_settlement_exception_cases,public.mme_pos_stripe_settlement_exception_events
 to service_role;

create or replace function public.mme_pos_detect_stripe_settlement_exceptions(
 p_batch_id uuid,p_actor_person_id uuid,p_missing_refund_grace interval default interval '24 hours'
) returns table(case_id uuid,exception_type text,severity text)
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_batch public.mme_pos_settlement_batches%rowtype;
 v_match public.mme_pos_stripe_refund_settlement_matches%rowtype;
 v_refund record;
 v_line public.mme_pos_settlement_lines%rowtype;
 v_case uuid;
 v_type text;
 v_severity text;
 v_code text;
 v_description text;
 v_count integer:=0;
begin
 select * into v_batch from public.mme_pos_settlement_batches where id=p_batch_id for update;
 if not found then raise exception 'Settlement batch not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_batch.location_id,'pos.settlement.exception.manage') then
  raise exception 'Stripe settlement exception detection permission denied' using errcode='42501';
 end if;
 if p_missing_refund_grace is null or p_missing_refund_grace<interval '1 hour'
  or p_missing_refund_grace>interval '30 days' then
  raise exception 'Missing-refund grace must be between one hour and thirty days' using errcode='22023';
 end if;

 for v_match in select m.* from public.mme_pos_stripe_refund_settlement_matches m
  where m.settlement_batch_id=p_batch_id and
   (m.match_status<>'matched' or m.financial_fact_status in ('period_closed','conflict'))
  order by m.matched_at
 loop
  if v_match.match_status='mismatch' then
   v_type:=case
    when v_match.discrepancy_code like '%amount%' then 'amount_mismatch'
    when v_match.discrepancy_code like '%currency%' then 'currency_mismatch'
    when v_match.discrepancy_code like '%account%' then 'connected_account_mismatch'
    else 'manual_review' end;
   v_severity:=case when v_type in ('connected_account_mismatch','duplicate_refund') then 'critical'
    when v_type in ('amount_mismatch','currency_mismatch') then 'high' else 'medium' end;
   v_code:=coalesce(v_match.discrepancy_code,'refund_match_mismatch');
   v_description:='Stripe refund settlement match failed validation. Compare the provider refund, connected account, amount, currency and imported payout line before taking action.';
  elsif v_match.financial_fact_status='period_closed' then
   v_type:='closed_period'; v_severity:='high'; v_code:=coalesce(v_match.discrepancy_code,'financial_period_closed');
   v_description:='Refund settlement matched but the financial reporting period is closed. Use the authorized adjustment workflow; do not rewrite a closed period.';
  elsif v_match.financial_fact_status='conflict' then
   v_type:='financial_fact_conflict'; v_severity:='critical'; v_code:=coalesce(v_match.discrepancy_code,'financial_fact_conflict');
   v_description:='Refund settlement matched but an existing financial fact conflicts with the provider source. Quarantine and investigate the source records.';
  else
   v_type:='manual_review'; v_severity:='medium'; v_code:='manual_review_required';
   v_description:='Refund settlement requires manual review.';
  end if;
  insert into public.mme_pos_stripe_settlement_exception_cases(
   location_id,settlement_batch_id,settlement_line_id,refund_request_id,refund_match_id,
   exception_type,severity,amount_minor,currency,discrepancy_code,description,due_at
  ) values(v_batch.location_id,p_batch_id,v_match.settlement_line_id,v_match.refund_request_id,v_match.id,
   v_type,v_severity,v_match.requested_amount_minor,v_match.currency,v_code,v_description,
   now()+case v_severity when 'critical' then interval '1 hour' when 'high' then interval '4 hours' else interval '1 day' end)
  on conflict do nothing returning id into v_case;
  if v_case is not null then
   insert into public.mme_pos_stripe_settlement_exception_events(case_id,actor_person_id,event_type,detail_code)
    values(v_case,p_actor_person_id,'detected',v_code);
   case_id:=v_case; exception_type:=v_type; severity:=v_severity; return next;
   v_count:=v_count+1; v_case:=null;
  end if;
 end loop;

 for v_line in select l.* from public.mme_pos_settlement_lines l
  where l.batch_id=p_batch_id and l.line_type='refund'
   and not exists(select 1 from public.mme_pos_stripe_refund_settlement_matches m where m.settlement_line_id=l.id)
  order by l.id
 loop
  if exists(select 1 from public.mme_pos_refund_requests r
    where r.provider_refund_reference=v_line.refund_reference and r.request_type='refund'
     and r.status='completed') then
   v_type:='manual_review'; v_code:='provider_refund_exists_but_no_settlement_match';
   v_description:='A completed MME refund references this Stripe refund, but no settlement match exists.';
  else
   v_type:='missing_internal_refund'; v_code:='processor_refund_without_internal_refund';
   v_description:='Stripe payout contains a refund line with no matching completed MME refund request. Verify source and account ownership.';
  end if;
  v_severity:='high';
  insert into public.mme_pos_stripe_settlement_exception_cases(
   location_id,settlement_batch_id,settlement_line_id,exception_type,severity,amount_minor,currency,
   discrepancy_code,description,due_at
  ) values(v_batch.location_id,p_batch_id,v_line.id,v_type,v_severity,abs(v_line.amount_minor),
   v_line.currency,v_code,v_description,now()+interval '4 hours')
  on conflict do nothing returning id into v_case;
  if v_case is not null then
   insert into public.mme_pos_stripe_settlement_exception_events(case_id,actor_person_id,event_type,detail_code)
    values(v_case,p_actor_person_id,'detected',v_code);
   case_id:=v_case; exception_type:=v_type; severity:=v_severity; return next;
   v_count:=v_count+1; v_case:=null;
  end if;
 end loop;

 for v_refund in
  select r.id as refund_request_id,r.tender_attempt_id,r.amount_minor,r.currency,r.updated_at,
   r.provider_refund_reference,r.provider_operation_reference
  from public.mme_pos_refund_requests r
  join public.mme_pos_tender_attempts t on t.id=r.tender_attempt_id
  where r.request_type='refund' and r.status='completed' and t.provider='stripe'
   and r.updated_at<now()-p_missing_refund_grace
   and not exists(select 1 from public.mme_pos_stripe_refund_settlement_matches m where m.refund_request_id=r.id)
 loop
  v_type:='missing_processor_refund'; v_severity:='high'; v_code:='completed_internal_refund_missing_from_settlement';
  v_description:='Completed MME Stripe refund has not appeared in a matched Stripe settlement line within the configured grace period. Confirm provider balance transaction and payout timing.';
  insert into public.mme_pos_stripe_settlement_exception_cases(
   location_id,settlement_batch_id,refund_request_id,exception_type,severity,amount_minor,currency,
   discrepancy_code,description,due_at
  ) values(v_batch.location_id,p_batch_id,v_refund.refund_request_id,v_type,v_severity,
   v_refund.amount_minor,v_refund.currency,v_code,v_description,now()+interval '4 hours')
  on conflict do nothing returning id into v_case;
  if v_case is not null then
   insert into public.mme_pos_stripe_settlement_exception_events(case_id,actor_person_id,event_type,detail_code)
    values(v_case,p_actor_person_id,'detected',v_code);
   case_id:=v_case; exception_type:=v_type; severity:=v_severity; return next;
   v_count:=v_count+1; v_case:=null;
  end if;
 end loop;

 return;
end;
$$;

create or replace function public.mme_pos_manage_stripe_settlement_exception(
 p_case_id uuid,p_actor_person_id uuid,p_action text,p_assignee_person_id uuid default null,
 p_resolution_code text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_case public.mme_pos_stripe_settlement_exception_cases%rowtype; v_event text;
begin
 select * into v_case from public.mme_pos_stripe_settlement_exception_cases where id=p_case_id for update;
 if not found then raise exception 'Stripe settlement exception case not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_case.location_id,'pos.settlement.exception.manage') then
  raise exception 'Stripe settlement exception management permission denied' using errcode='42501';
 end if;
 if p_action='assign' then
  if p_assignee_person_id is null or not exists(select 1 from public.mme_person_identities i
    join public.employee_relationships e on e.person_id=i.person_id
    where i.person_id=p_assignee_person_id and i.lifecycle_status='active' and e.employment_status='active') then
   raise exception 'Active employee assignee required' using errcode='22023';
  end if;
  update public.mme_pos_stripe_settlement_exception_cases set assigned_to_person_id=p_assignee_person_id,
   status='assigned',updated_at=now() where id=p_case_id;
  v_event:='assigned';
 elsif p_action='investigate' then
  if v_case.status in ('resolved','accepted_variance','false_positive') then
   raise exception 'Closed exception cannot be investigated' using errcode='55000';
  end if;
  update public.mme_pos_stripe_settlement_exception_cases set status='investigating',updated_at=now()
   where id=p_case_id;
  v_event:='investigating';
 elsif p_action='resolve' or p_action='accept_variance' or p_action='false_positive' then
  if length(btrim(coalesce(p_resolution_code,'')))<3 or length(btrim(coalesce(p_notes,'')))<8 then
   raise exception 'Resolution code and evidence notes are required' using errcode='22023';
  end if;
  if v_case.severity='critical' and not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_case.location_id,'pos.settlement.approve') then
   raise exception 'Critical exception requires settlement approval permission' using errcode='42501';
  end if;
  update public.mme_pos_stripe_settlement_exception_cases set
   status=case p_action when 'resolve' then 'resolved' when 'accept_variance' then 'accepted_variance' else 'false_positive' end,
   resolution_code=p_resolution_code,resolution_notes=p_notes,resolved_by_person_id=p_actor_person_id,
   resolved_at=now(),updated_at=now() where id=p_case_id;
  v_event:=case p_action when 'resolve' then 'resolved' when 'accept_variance' then 'accepted_variance' else 'false_positive' end;
 elsif p_action='reopen' then
  if v_case.status not in ('resolved','accepted_variance','false_positive') then
   raise exception 'Only closed exceptions can be reopened' using errcode='55000';
  end if;
  update public.mme_pos_stripe_settlement_exception_cases set status='open',resolution_code=null,
   resolution_notes=null,resolved_by_person_id=null,resolved_at=null,updated_at=now() where id=p_case_id;
  v_event:='reopened';
 else
  raise exception 'Unsupported exception action' using errcode='22023';
 end if;
 insert into public.mme_pos_stripe_settlement_exception_events(case_id,actor_person_id,event_type,detail_code,notes)
 values(p_case_id,p_actor_person_id,v_event,'case_'||v_event,p_notes);
 return p_case_id;
end;
$$;

create or replace function public.mme_pos_escalate_stripe_settlement_exceptions(
 p_location_id uuid,p_actor_person_id uuid
) returns integer language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_count integer;
begin
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,p_location_id,'pos.settlement.exception.manage') then
  raise exception 'Exception escalation permission denied' using errcode='42501';
 end if;
 with escalated as (
  update public.mme_pos_stripe_settlement_exception_cases set
   status='escalated',escalation_level=least(escalation_level+1,3),updated_at=now()
  where location_id=p_location_id and status in ('open','assigned','investigating')
   and due_at<=now() and escalation_level<3
  returning id,severity,escalation_level
 )
 insert into public.mme_pos_stripe_settlement_exception_events(case_id,actor_person_id,event_type,detail_code,metadata)
 select id,p_actor_person_id,'escalated','exception_sla_breached',
  jsonb_build_object('severity',severity,'escalation_level',escalation_level) from escalated;
 get diagnostics v_count=row_count;
 return v_count;
end;
$$;

create or replace view public.mme_pos_stripe_settlement_exception_dashboard
with (security_invoker=true) as
select location_id,currency,status,severity,exception_type,
 count(*)::integer case_count,
 coalesce(sum(amount_minor),0)::bigint exposure_amount_minor,
 count(*) filter(where due_at<=now() and status not in ('resolved','accepted_variance','false_positive'))::integer overdue_count,
 count(*) filter(where assigned_to_person_id is null and status not in ('resolved','accepted_variance','false_positive'))::integer unassigned_count,
 min(due_at) filter(where status not in ('resolved','accepted_variance','false_positive')) next_due_at,
 max(last_detected_at) last_detected_at
from public.mme_pos_stripe_settlement_exception_cases
group by location_id,currency,status,severity,exception_type;

revoke all on function public.mme_pos_detect_stripe_settlement_exceptions(uuid,uuid,interval) from public,anon,authenticated;
revoke all on function public.mme_pos_manage_stripe_settlement_exception(uuid,uuid,text,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_escalate_stripe_settlement_exceptions(uuid,uuid) from public,anon,authenticated;
revoke all on public.mme_pos_stripe_settlement_exception_dashboard from public,anon,authenticated;
grant execute on function public.mme_pos_detect_stripe_settlement_exceptions(uuid,uuid,interval) to service_role;
grant execute on function public.mme_pos_manage_stripe_settlement_exception(uuid,uuid,text,uuid,text,text) to service_role;
grant execute on function public.mme_pos_escalate_stripe_settlement_exceptions(uuid,uuid) to service_role;
grant select on public.mme_pos_stripe_settlement_exception_dashboard to service_role;

comment on table public.mme_pos_stripe_settlement_exception_cases is
 'Finance-controlled Stripe settlement exception queue with evidence-backed assignment, SLA escalation and resolution.';
comment on view public.mme_pos_stripe_settlement_exception_dashboard is
 'Store-scoped exception counts and exposure by currency, severity and lifecycle state; amount totals are not additive across currencies.';

commit;
