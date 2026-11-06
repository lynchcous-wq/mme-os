-- Build 009.83: read-only warranty retention compliance dashboard projections
begin;
create or replace view public.mme_warranty_compliance_dashboard_kpis with (security_invoker=true) as
select
 (select count(*) from public.mme_warranty_evidence_retention_records where retention_status='active' and retain_until>now()) as retained_evidence_count,
 (select count(*) from public.mme_warranty_evidence_retention_records where retention_status='active' and retain_until<=now()) as overdue_evidence_count,
 (select count(*) from public.mme_warranty_evidence_deletion_jobs where status='queued') as deletion_approval_backlog,
 (select count(*) from public.mme_warranty_evidence_deletion_jobs where status='failed') as failed_deletion_count,
 (select count(*) from public.mme_warranty_evidence_legal_holds where hold_status='active') as active_legal_hold_count,
 (select count(*) from public.mme_warranty_evidence_retention_exceptions where status='approved' and expires_at>now()) as active_exception_count,
 (select count(*) from public.mme_warranty_retention_alerts where status in ('open','acknowledged') and severity in ('high','critical')) as high_risk_alert_count,
 (select count(*) from public.mme_warranty_retention_notification_outbox where status in ('queued','retry','failed')) as notification_backlog,
 now() as measured_at;

create or replace view public.mme_warranty_compliance_retention_calendar with (security_invoker=true) as
select rr.retention_record_id,rr.evidence_id,rr.retained_from,rr.retain_until,rr.retention_status,
 p.policy_code,p.policy_version,p.legal_basis_code,
 case when rr.retain_until<=now() then 'overdue' when rr.retain_until<=now()+interval '7 days' then 'within_7_days' when rr.retain_until<=now()+interval '30 days' then 'within_30_days' else 'future' end as due_window,
 exists(select 1 from public.mme_warranty_evidence_legal_holds h where h.evidence_id=rr.evidence_id and h.hold_status='active') as has_active_legal_hold,
 exists(select 1 from public.mme_warranty_evidence_retention_exceptions x where x.evidence_id=rr.evidence_id and x.status='approved' and x.expires_at>now()) as has_active_exception
from public.mme_warranty_evidence_retention_records rr
join public.mme_warranty_evidence_retention_policies p on p.policy_id=rr.policy_id
where rr.retention_status not in ('deleted');

create or replace view public.mme_warranty_compliance_approval_queue with (security_invoker=true) as
select j.deletion_job_id,j.evidence_id,j.status,j.reason_code,j.created_at,j.approved_at,j.failure_code,
 rr.retain_until, (j.status='queued') as requires_approval,
 exists(select 1 from public.mme_warranty_evidence_legal_holds h where h.evidence_id=j.evidence_id and h.hold_status='active') as has_active_legal_hold,
 exists(select 1 from public.mme_warranty_evidence_retention_exceptions x where x.evidence_id=j.evidence_id and x.status='approved' and x.expires_at>now()) as has_active_exception
from public.mme_warranty_evidence_deletion_jobs j
join public.mme_warranty_evidence_retention_records rr on rr.retention_record_id=j.retention_record_id
where j.status in ('queued','blocked','approved','failed');

create or replace view public.mme_warranty_compliance_alert_feed with (security_invoker=true) as
select a.alert_id,a.alert_key,a.alert_type,a.severity,a.status,a.title,a.detail_code,a.due_at,a.assigned_to,a.created_at,a.updated_at
from public.mme_warranty_retention_alerts a where a.status in ('open','acknowledged');

create or replace view public.mme_warranty_compliance_department_summary with (security_invoker=true) as
select coalesce(a.assigned_to::text,'unassigned') as assignment_bucket,a.severity,a.status,count(*) as alert_count,
 min(a.created_at) as oldest_alert_at,max(a.updated_at) as latest_activity_at
from public.mme_warranty_retention_alerts a where a.status in ('open','acknowledged')
group by a.assigned_to,a.severity,a.status;

revoke all on public.mme_warranty_compliance_dashboard_kpis,public.mme_warranty_compliance_retention_calendar,public.mme_warranty_compliance_approval_queue,public.mme_warranty_compliance_alert_feed,public.mme_warranty_compliance_department_summary from public,anon,authenticated;
grant select on public.mme_warranty_compliance_dashboard_kpis,public.mme_warranty_compliance_retention_calendar,public.mme_warranty_compliance_approval_queue,public.mme_warranty_compliance_alert_feed,public.mme_warranty_compliance_department_summary to service_role;
commit;
