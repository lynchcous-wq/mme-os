begin;
create or replace view public.mme_warranty_security_compliance_kpis with (security_invoker=true) as
select
 (select count(*) from public.mme_warranty_api_security_case_evidence e) as total_evidence_count,
 (select count(*) from public.mme_warranty_api_security_case_evidence e where e.ingestion_status='clean') as clean_evidence_count,
 (select count(*) from public.mme_warranty_api_security_case_evidence e where e.ingestion_status='pending_scan') as pending_scan_count,
 (select count(*) from public.mme_warranty_api_security_case_evidence e where e.ingestion_status in ('quarantined','rejected','scan_error')) as flagged_evidence_count,
 (select count(*) from public.mme_warranty_api_security_evidence_legal_holds h where h.released_at is null) as active_legal_hold_count,
 (select count(*) from public.mme_warranty_api_security_evidence_retention_jobs j where j.status in ('pending','processing','failed')) as retention_work_backlog,
 (select count(*) from public.mme_warranty_api_security_evidence_access_events a where a.action='download_denied' and a.occurred_at>=now()-interval '30 days') as denied_downloads_30d,
 (select count(*) from public.mme_warranty_api_security_evidence_access_events a where a.action='download_granted' and a.occurred_at>=now()-interval '30 days') as granted_downloads_30d,
 (select count(*) from public.mme_warranty_api_security_events s where s.status in ('open','investigating') and s.severity in ('high','critical')) as open_high_risk_security_events,
 (select count(*) from public.mme_warranty_api_security_incidents i where i.status not in ('resolved','closed')) as open_security_incidents,
 now() as measured_at;

create or replace view public.mme_warranty_security_compliance_evidence with (security_invoker=true) as
select e.evidence_id,e.case_id,e.evidence_type,e.ingestion_status,e.byte_size,e.sha256_hex,e.collected_by,e.collected_at,e.scanned_at,e.scanner_name,e.scan_result_code,
 exists(select 1 from public.mme_warranty_api_security_evidence_legal_holds h where h.evidence_id=e.evidence_id and h.released_at is null) as has_active_legal_hold,
 coalesce(j.status,'not_queued') as retention_status,j.due_at as retention_due_at,j.attempt_count as retention_attempt_count
from public.mme_warranty_api_security_case_evidence e
left join public.mme_warranty_api_security_evidence_retention_jobs j on j.evidence_id=e.evidence_id;

create or replace view public.mme_warranty_security_compliance_access with (security_invoker=true) as
select a.access_id,a.evidence_id,a.actor_id,a.action,a.reason_code,a.request_id,a.occurred_at
from public.mme_warranty_api_security_evidence_access_events a;

create or replace view public.mme_warranty_security_compliance_holds with (security_invoker=true) as
select h.hold_id,h.evidence_id,h.hold_reason,h.placed_by,h.placed_at,h.released_by,h.released_at,h.release_reason,
 case when h.released_at is null then 'active' else 'released' end as hold_status
from public.mme_warranty_api_security_evidence_legal_holds h;

create or replace view public.mme_warranty_security_compliance_retention with (security_invoker=true) as
select j.job_id,j.evidence_id,j.status,j.due_at,j.attempt_count,j.last_error,j.updated_at,
 exists(select 1 from public.mme_warranty_api_security_evidence_legal_holds h where h.evidence_id=j.evidence_id and h.released_at is null) as has_active_legal_hold
from public.mme_warranty_api_security_evidence_retention_jobs j;

create or replace view public.mme_warranty_security_compliance_custody with (security_invoker=true) as
select c.custody_id,c.evidence_id,c.from_custodian,c.to_custodian,c.transferred_by,c.transfer_reason,c.evidence_sha256_hex,c.transferred_at
from public.mme_warranty_api_security_evidence_custody c;

revoke all on public.mme_warranty_security_compliance_kpis,public.mme_warranty_security_compliance_evidence,public.mme_warranty_security_compliance_access,public.mme_warranty_security_compliance_holds,public.mme_warranty_security_compliance_retention,public.mme_warranty_security_compliance_custody from public,anon,authenticated;
grant select on public.mme_warranty_security_compliance_kpis,public.mme_warranty_security_compliance_evidence,public.mme_warranty_security_compliance_access,public.mme_warranty_security_compliance_holds,public.mme_warranty_security_compliance_retention,public.mme_warranty_security_compliance_custody to service_role;
commit;
