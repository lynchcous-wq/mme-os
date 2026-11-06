begin;
create table public.mme_warranty_api_security_risk_signals (
 signal_id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_warranty_api_security_investigation_cases(case_id) on delete restrict,
 signal_type text not null check(signal_type in ('repeated_denied_downloads','unusual_download_volume','evidence_integrity_exception','scan_failure','retention_overdue','custody_gap','incident_severity','manual_review')),
 severity text not null check(severity in ('low','medium','high','critical')),
 confidence numeric(4,3) not null check(confidence between 0 and 1),
 weight integer not null check(weight between 1 and 40),
 explanation text not null check(length(trim(explanation)) between 10 and 2000),
 source_reference text,
 observed_at timestamptz not null default now(),
 created_by uuid,
 review_status text not null default 'unreviewed' check(review_status in ('unreviewed','accepted','dismissed','needs_context')),
 reviewed_by uuid,
 reviewed_at timestamptz,
 review_note text,
 created_at timestamptz not null default now(),
 check((review_status='unreviewed' and reviewed_by is null and reviewed_at is null) or (review_status<>'unreviewed' and reviewed_by is not null and reviewed_at is not null))
);
create index mme_warranty_security_risk_case_idx on public.mme_warranty_api_security_risk_signals(case_id,created_at desc);
create index mme_warranty_security_risk_review_idx on public.mme_warranty_api_security_risk_signals(review_status,severity,created_at desc);
alter table public.mme_warranty_api_security_risk_signals enable row level security;
revoke all on public.mme_warranty_api_security_risk_signals from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_risk_signals to service_role;
revoke delete,truncate on public.mme_warranty_api_security_risk_signals from public,anon,authenticated,service_role;
create or replace view public.mme_warranty_security_case_risk_intelligence with (security_invoker=true) as
select c.case_id,c.case_number,c.incident_id,c.title,c.status as case_status,c.priority as case_priority,c.lead_investigator_id,c.due_at,
 coalesce(sum(case when s.review_status<>'dismissed' then s.weight else 0 end),0)::integer as raw_risk_score,
 least(100,coalesce(sum(case when s.review_status<>'dismissed' then s.weight else 0 end),0))::integer as risk_score,
 count(s.signal_id) filter(where s.review_status<>'dismissed')::integer as active_signal_count,
 count(s.signal_id) filter(where s.review_status='unreviewed')::integer as unreviewed_signal_count,
 count(s.signal_id) filter(where s.severity in ('high','critical') and s.review_status<>'dismissed')::integer as high_critical_signal_count,
 max(s.created_at) as latest_signal_at,
 jsonb_agg(jsonb_build_object('signalId',s.signal_id,'type',s.signal_type,'severity',s.severity,'confidence',s.confidence,'weight',s.weight,'explanation',s.explanation,'sourceReference',s.source_reference,'reviewStatus',s.review_status,'observedAt',s.observed_at) order by s.created_at desc) filter(where s.signal_id is not null and s.review_status<>'dismissed') as contributing_signals
from public.mme_warranty_api_security_investigation_cases c
left join public.mme_warranty_api_security_risk_signals s on s.case_id=c.case_id
group by c.case_id,c.case_number,c.incident_id,c.title,c.status,c.priority,c.lead_investigator_id,c.due_at;
revoke all on public.mme_warranty_security_case_risk_intelligence from public,anon,authenticated;
grant select on public.mme_warranty_security_case_risk_intelligence to service_role;
create table public.mme_warranty_api_security_risk_review_events (
 review_event_id bigint generated always as identity primary key,
 signal_id uuid not null references public.mme_warranty_api_security_risk_signals(signal_id) on delete restrict,
 reviewer_id uuid not null,
 prior_status text not null,
 new_status text not null,
 review_note text not null check(length(trim(review_note)) between 5 and 2000),
 request_id uuid not null,
 occurred_at timestamptz not null default now()
);
alter table public.mme_warranty_api_security_risk_review_events enable row level security;
revoke all on public.mme_warranty_api_security_risk_review_events from public,anon,authenticated;
grant select,insert on public.mme_warranty_api_security_risk_review_events to service_role;
create or replace function public.mme_warranty_api_security_risk_review(p_signal_id uuid,p_reviewer_id uuid,p_status text,p_note text,p_request_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_prior text;
begin
 if p_status not in ('accepted','dismissed','needs_context') or length(trim(coalesce(p_note,'')))<5 then raise exception 'invalid_risk_review'; end if;
 select review_status into v_prior from public.mme_warranty_api_security_risk_signals where signal_id=p_signal_id for update;
 if not found then raise exception 'risk_signal_not_found'; end if;
 update public.mme_warranty_api_security_risk_signals set review_status=p_status,reviewed_by=p_reviewer_id,reviewed_at=now(),review_note=trim(p_note) where signal_id=p_signal_id;
 insert into public.mme_warranty_api_security_risk_review_events(signal_id,reviewer_id,prior_status,new_status,review_note,request_id)
 values(p_signal_id,p_reviewer_id,v_prior,p_status,trim(p_note),p_request_id);
end $$;
revoke all on function public.mme_warranty_api_security_risk_review(uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_risk_review(uuid,uuid,text,text,uuid) to service_role;
commit;
