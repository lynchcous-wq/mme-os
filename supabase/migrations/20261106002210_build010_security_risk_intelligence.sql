begin;
create or replace view public.mme_security_risk_exposure
with (security_invoker=true) as
select
 count(*) filter(where status<>'closed')::integer as open_incidents,
 count(*) filter(where status<>'closed' and severity='critical')::integer as open_critical,
 count(*) filter(where status<>'closed' and severity='warning')::integer as open_warning,
 count(*) filter(where status<>'closed' and severity='info')::integer as open_info,
 count(*) filter(where status<>'closed' and sla_due_at<now())::integer as overdue_incidents,
 count(*) filter(where status<>'closed' and created_at<now()-interval '24 hours')::integer as older_than_24h,
 coalesce(sum(case when status='closed' then 0 else
   (case severity when 'critical' then 40 when 'warning' then 20 else 5 end)
   + least(escalation_level,5)*5
   + case when sla_due_at<now() then 15 else 0 end end),0)::integer as exposure_score,
 max(updated_at) as latest_case_update
from public.mme_security_incident_response_cases;

create or replace view public.mme_security_incident_daily_trend
with (security_invoker=true) as
with days as (
 select generate_series(current_date-29,current_date,interval '1 day')::date as incident_day
), counts as (
 select created_at::date incident_day,
  count(*)::integer incident_count,
  count(*) filter(where severity='critical')::integer critical_count,
  count(*) filter(where severity='warning')::integer warning_count,
  count(*) filter(where severity='info')::integer info_count
 from public.mme_security_incident_response_cases
 where created_at>=current_date-29
 group by created_at::date
)
select d.incident_day,coalesce(c.incident_count,0)::integer incident_count,
 coalesce(c.critical_count,0)::integer critical_count,
 coalesce(c.warning_count,0)::integer warning_count,
 coalesce(c.info_count,0)::integer info_count
from days d left join counts c using(incident_day);

create or replace view public.mme_security_incident_intelligence_summary
with (security_invoker=true) as
with periods as (
 select
  count(*) filter(where created_at>=now()-interval '7 days')::integer as current_7d,
  count(*) filter(where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')::integer as previous_7d,
  count(*) filter(where created_at>=now()-interval '30 days')::integer as current_30d,
  count(*) filter(where severity='critical' and created_at>=now()-interval '30 days')::integer as critical_30d,
  avg(extract(epoch from (updated_at-created_at))/3600) filter(where status='closed' and created_at>=now()-interval '30 days') as avg_case_lifecycle_hours
 from public.mme_security_incident_response_cases
)
select *,
 case when previous_7d=0 and current_7d=0 then 0
      when previous_7d=0 then 100
      else round(((current_7d-previous_7d)::numeric/previous_7d)*100,1) end as weekly_change_pct,
 case when current_7d=0 then 0
      else round((current_7d::numeric/7)*30,1) end as simple_30d_run_rate
from periods;

revoke all on public.mme_security_risk_exposure from public,anon,authenticated;
revoke all on public.mme_security_incident_daily_trend from public,anon,authenticated;
revoke all on public.mme_security_incident_intelligence_summary from public,anon,authenticated;
grant select on public.mme_security_risk_exposure to service_role;
grant select on public.mme_security_incident_daily_trend to service_role;
grant select on public.mme_security_incident_intelligence_summary to service_role;
comment on view public.mme_security_risk_exposure is
 'Descriptive weighted exposure index based on open incident severity, escalation and SLA overdue status; not a probability of compromise.';
comment on view public.mme_security_incident_intelligence_summary is
 'Historical incident counts and simple run-rate indicator; not a predictive guarantee.';
commit;