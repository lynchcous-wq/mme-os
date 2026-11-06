begin;

create table if not exists public.mme_security_incident_response_cases (
 case_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null unique references public.mme_security_integration_alerts(alert_id) on delete restrict,
 severity text not null check(severity in ('critical','warning','info')),
 status text not null default 'triage' check(status in ('triage','investigating','containment','recovery','closure_pending','closed')),
 owner_id uuid,
 sla_due_at timestamptz not null,
 escalated_at timestamptz,
 escalation_level integer not null default 0 check(escalation_level between 0 and 5),
 recovery_verified_at timestamptz,
 recovery_verified_by uuid,
 recovery_evidence text,
 closure_requested_at timestamptz,
 closure_requested_by uuid,
 closure_approved_at timestamptz,
 closure_approved_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(status<>'closed' or (recovery_verified_at is not null and closure_approved_at is not null))
);
create index if not exists mme_security_incident_cases_status_sla_idx on public.mme_security_incident_response_cases(status,sla_due_at);
create index if not exists mme_security_incident_cases_owner_idx on public.mme_security_incident_response_cases(owner_id,status);
create table if not exists public.mme_security_incident_response_events (
 event_id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_security_incident_response_cases(case_id) on delete restrict,
 actor_id uuid not null,
 actor_role text not null,
 event_type text not null check(event_type in ('case_opened','owner_assigned','escalated','recovery_verified','closure_requested','closure_approved')),
 rationale text not null check(length(trim(rationale)) between 10 and 2000),
 event_data jsonb not null default '{}'::jsonb,
 request_id text,
 created_at timestamptz not null default now()
);
create index if not exists mme_security_incident_response_events_case_idx on public.mme_security_incident_response_events(case_id,created_at desc);
alter table public.mme_security_incident_response_cases enable row level security;
alter table public.mme_security_incident_response_events enable row level security;
revoke all on public.mme_security_incident_response_cases from public,anon,authenticated;
revoke all on public.mme_security_incident_response_events from public,anon,authenticated;
grant select,insert,update on public.mme_security_incident_response_cases to service_role;
grant select,insert on public.mme_security_incident_response_events to service_role;

create or replace function public.mme_security_incident_response_action(
 p_alert_id uuid,p_action text,p_actor_id uuid,p_actor_role text,p_rationale text,
 p_owner_id uuid default null,p_recovery_evidence text default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 a public.mme_security_integration_alerts%rowtype;
 c public.mme_security_incident_response_cases%rowtype;
 v_event text;
 v_data jsonb:='{}'::jsonb;
 v_sla interval;
begin
 if p_actor_role not in ('ceo','cio','it_admin','manager') then raise exception 'incident_response_forbidden'; end if;
 if p_actor_id is null or coalesce(length(trim(p_rationale)),0)<10 or length(p_rationale)>2000 then raise exception 'invalid_action_context'; end if;
 select * into a from public.mme_security_integration_alerts where alert_id=p_alert_id;
 if not found then raise exception 'security_alert_not_found'; end if;
 select * into c from public.mme_security_incident_response_cases where alert_id=p_alert_id for update;
 if not found then
   if p_action<>'open_case' then raise exception 'incident_case_not_found'; end if;
   v_sla:=case a.severity when 'critical' then interval '15 minutes' when 'warning' then interval '1 hour' else interval '4 hours' end;
   insert into public.mme_security_incident_response_cases(alert_id,severity,sla_due_at)
   values(a.alert_id,a.severity,now()+v_sla) returning * into c;
   v_event:='case_opened';
   v_data:=jsonb_build_object('slaDueAt',c.sla_due_at,'severity',c.severity);
 else
   if p_action='open_case' then raise exception 'incident_case_already_exists'; end if;
   if c.status='closed' then raise exception 'incident_case_closed'; end if;
   if p_action='assign_owner' then
     if p_owner_id is null then raise exception 'owner_required'; end if;
     update public.mme_security_incident_response_cases set owner_id=p_owner_id,status=case when status='triage' then 'investigating' else status end,updated_at=now()
       where case_id=c.case_id returning * into c;
     v_event:='owner_assigned'; v_data:=jsonb_build_object('ownerId',p_owner_id);
   elsif p_action='escalate' then
     update public.mme_security_incident_response_cases set escalation_level=least(escalation_level+1,5),escalated_at=now(),status=case when status in ('triage','investigating') then 'containment' else status end,updated_at=now()
       where case_id=c.case_id returning * into c;
     v_event:='escalated'; v_data:=jsonb_build_object('escalationLevel',c.escalation_level);
   elsif p_action='verify_recovery' then
     if coalesce(length(trim(p_recovery_evidence)),0)<10 or length(p_recovery_evidence)>2000 then raise exception 'recovery_evidence_required'; end if;
     update public.mme_security_incident_response_cases set recovery_verified_at=now(),recovery_verified_by=p_actor_id,recovery_evidence=trim(p_recovery_evidence),status='recovery',updated_at=now()
       where case_id=c.case_id returning * into c;
     v_event:='recovery_verified'; v_data:=jsonb_build_object('verifiedAt',c.recovery_verified_at);
   elsif p_action='request_closure' then
     if c.recovery_verified_at is null then raise exception 'recovery_verification_required'; end if;
     update public.mme_security_incident_response_cases set closure_requested_at=now(),closure_requested_by=p_actor_id,status='closure_pending',updated_at=now()
       where case_id=c.case_id returning * into c;
     v_event:='closure_requested';
   elsif p_action='approve_closure' then
     if c.status<>'closure_pending' or c.recovery_verified_at is null then raise exception 'closure_not_ready'; end if;
     if c.closure_requested_by=p_actor_id then raise exception 'separation_of_duties_required'; end if;
     update public.mme_security_incident_response_cases set closure_approved_at=now(),closure_approved_by=p_actor_id,status='closed',updated_at=now()
       where case_id=c.case_id returning * into c;
     v_event:='closure_approved';
   else raise exception 'invalid_incident_action';
   end if;
 end if;
 insert into public.mme_security_incident_response_events(case_id,actor_id,actor_role,event_type,rationale,event_data,request_id)
 values(c.case_id,p_actor_id,p_actor_role,v_event,trim(p_rationale),v_data,p_request_id);
 return jsonb_build_object('caseId',c.case_id,'alertId',c.alert_id,'status',c.status,'ownerId',c.owner_id,'slaDueAt',c.sla_due_at,'escalationLevel',c.escalation_level,'event',v_event);
end $$;
revoke all on function public.mme_security_incident_response_action(uuid,text,uuid,text,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_security_incident_response_action(uuid,text,uuid,text,text,uuid,text,text) to service_role;
commit;