begin;
create or replace view public.mme_warranty_api_security_executive_kpis with (security_invoker=true) as
select
 count(*) filter(where status not in ('resolved','closed'))::integer as open_incidents,
 count(*) filter(where status in ('open','investigating') and severity='critical')::integer as critical_incidents,
 count(*) filter(where status in ('open','investigating') and severity='high')::integer as high_incidents,
 count(*) filter(where opened_at>=now()-interval '24 hours')::integer as incidents_last_24h,
 count(*) filter(where opened_at>=now()-interval '7 days')::integer as incidents_last_7d,
 count(*) filter(where status='resolved' and resolved_at>=now()-interval '7 days')::integer as resolved_last_7d
from public.mme_warranty_api_security_incidents;
create or replace view public.mme_warranty_api_security_executive_activity with (security_invoker=true) as
select e.event_id,e.incident_id,e.security_event_id,e.actor_id,e.event_type,e.reason_code,e.note,e.occurred_at,
 i.incident_number,i.title as incident_title,i.severity,i.status as incident_status
from public.mme_warranty_api_security_incident_events e
join public.mme_warranty_api_security_incidents i on i.incident_id=e.incident_id;
create or replace view public.mme_warranty_api_security_executive_event_feed with (security_invoker=true) as
select event_id,event_type,severity,source_resource,actor_role,reason_code,occurrence_count,first_seen_at,last_seen_at,status
from public.mme_warranty_api_security_events;
create or replace view public.mme_warranty_api_security_executive_incidents with (security_invoker=true) as
select i.incident_id,i.incident_number,i.title,i.description,i.severity,i.status,i.owner_id,i.opened_at,i.contained_at,i.resolved_at,i.closed_at,i.updated_at,
 (select count(*) from public.mme_warranty_api_security_incident_events e where e.incident_id=i.incident_id)::integer as timeline_count,
 (select count(*) from public.mme_warranty_api_security_incident_acknowledgements a where a.incident_id=i.incident_id)::integer as acknowledgement_count
from public.mme_warranty_api_security_incidents i;
revoke all on public.mme_warranty_api_security_executive_kpis,public.mme_warranty_api_security_executive_activity,public.mme_warranty_api_security_executive_event_feed,public.mme_warranty_api_security_executive_incidents from public,anon,authenticated;
grant select on public.mme_warranty_api_security_executive_kpis,public.mme_warranty_api_security_executive_activity,public.mme_warranty_api_security_executive_event_feed,public.mme_warranty_api_security_executive_incidents to service_role;
commit;