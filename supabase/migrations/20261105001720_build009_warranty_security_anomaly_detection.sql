begin;
alter table public.mme_warranty_api_security_risk_signals
 add column if not exists detection_fingerprint text;
create unique index if not exists mme_warranty_security_risk_signal_dedupe_idx
 on public.mme_warranty_api_security_risk_signals(case_id,signal_type,detection_fingerprint)
 where detection_fingerprint is not null and review_status='unreviewed';

create or replace function public.mme_warranty_api_security_detect_anomalies(p_window_minutes integer default 60)
returns table(signals_created integer,window_minutes integer,scanned_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_created integer:=0; v_rows integer:=0; v_window integer:=greatest(5,least(coalesce(p_window_minutes,60),10080));
begin
 -- Repeated denied evidence downloads: threshold >=5 per actor/case in 30 minutes.
 with candidates as (
  select e.case_id,a.actor_id,count(*) n,min(a.occurred_at) first_seen,max(a.occurred_at) last_seen,
   md5(e.case_id::text||':'||a.actor_id::text||':denied:'||date_trunc('hour',now())::text) fp
  from public.mme_warranty_api_security_evidence_access_events a
  join public.mme_warranty_api_security_case_evidence e on e.evidence_id=a.evidence_id
  where a.action='download_denied' and a.occurred_at>=now()-interval '30 minutes'
  group by e.case_id,a.actor_id having count(*)>=5
 ), ins as (
  insert into public.mme_warranty_api_security_risk_signals(case_id,signal_type,severity,confidence,weight,explanation,source_reference,observed_at,detection_fingerprint)
  select case_id,'repeated_denied_downloads',case when n>=10 then 'high' else 'medium' end,
   least(0.99,0.65+n*0.02),least(30,10+n),
   format('%s denied evidence-download attempts by one actor were recorded in 30 minutes. This is an access-pattern anomaly requiring context; it does not establish intent.',n),
   'actor:'||actor_id::text,last_seen,fp from candidates
  on conflict do nothing returning 1
 ) select count(*) into v_rows from ins;
 v_created:=v_created+v_rows;

 -- Abnormally high granted-download volume by actor within a configurable window.
 with candidates as (
  select e.case_id,a.actor_id,count(*) n,max(a.occurred_at) last_seen,
   md5(e.case_id::text||':'||a.actor_id::text||':volume:'||date_trunc('hour',now())::text) fp
  from public.mme_warranty_api_security_evidence_access_events a
  join public.mme_warranty_api_security_case_evidence e on e.evidence_id=a.evidence_id
  where a.action='download_granted' and a.occurred_at>=now()-make_interval(mins=>v_window)
  group by e.case_id,a.actor_id having count(*)>=20
 ), ins as (
  insert into public.mme_warranty_api_security_risk_signals(case_id,signal_type,severity,confidence,weight,explanation,source_reference,observed_at,detection_fingerprint)
  select case_id,'unusual_download_volume',case when n>=50 then 'high' else 'medium' end,
   least(0.95,0.60+n*0.005),least(25,8+n/5),
   format('%s successful evidence downloads by one actor occurred within %s minutes. Review assignment, workload and legitimate bulk activity before drawing conclusions.',n,v_window),
   'actor:'||actor_id::text,last_seen,fp from candidates
  on conflict do nothing returning 1
 ) select count(*) into v_rows from ins;
 v_created:=v_created+v_rows;

 -- Evidence with quarantined, rejected or failed scan states.
 with candidates as (
  select e.case_id,e.evidence_id,e.ingestion_status,e.collected_at,
   md5(e.evidence_id::text||':integrity:'||e.ingestion_status) fp
  from public.mme_warranty_api_security_case_evidence e
  where e.ingestion_status in ('quarantined','rejected','scan_error')
 ), ins as (
  insert into public.mme_warranty_api_security_risk_signals(case_id,signal_type,severity,confidence,weight,explanation,source_reference,observed_at,detection_fingerprint)
  select case_id,'evidence_integrity_exception',case when ingestion_status='rejected' then 'high' else 'medium' end,
   0.95,case when ingestion_status='rejected' then 25 else 18 end,
   'Evidence ingestion is in state '||ingestion_status||'. Preserve the original artifact and review scanner output and provenance.',
   'evidence:'||evidence_id::text,now(),fp from candidates
  on conflict do nothing returning 1
 ) select count(*) into v_rows from ins;
 v_created:=v_created+v_rows;

 -- Retention failures and overdue pending jobs are surfaced, never auto-deleted here.
 with candidates as (
  select e.case_id,j.job_id,j.status,j.due_at,j.attempt_count,
   md5(j.job_id::text||':retention:'||j.status||':'||j.attempt_count::text) fp
  from public.mme_warranty_api_security_evidence_retention_jobs j
  join public.mme_warranty_api_security_case_evidence e on e.evidence_id=j.evidence_id
  where j.due_at<now() and j.status in ('pending','failed') and not exists(
   select 1 from public.mme_warranty_api_security_evidence_legal_holds h where h.evidence_id=j.evidence_id and h.released_at is null)
 ), ins as (
  insert into public.mme_warranty_api_security_risk_signals(case_id,signal_type,severity,confidence,weight,explanation,source_reference,observed_at,detection_fingerprint)
  select case_id,'retention_overdue',case when status='failed' then 'high' else 'medium' end,
   0.90,case when status='failed' then 20 else 12 end,
   format('Evidence retention job is overdue (status %s, attempts %s). Verify policy, legal hold state and worker health; this detector does not delete evidence.',status,attempt_count),
   'retention_job:'||job_id::text,now(),fp from candidates
  on conflict do nothing returning 1
 ) select count(*) into v_rows from ins;
 v_created:=v_created+v_rows;

 return query select v_created,v_window,now();
end $$;
revoke all on function public.mme_warranty_api_security_detect_anomalies(integer) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_detect_anomalies(integer) to service_role;
commit;
