begin;
create table public.mme_warranty_api_security_dashboard_snapshots(
 snapshot_id bigint generated always as identity primary key,as_of timestamptz not null default now(),
 total_alerts bigint not null,open_alerts bigint not null,critical_open bigint not null,high_open bigint not null,
 acknowledged_alerts bigint not null,resolved_alerts bigint not null,dismissed_alerts bigint not null,
 queued_deliveries bigint not null,sent_deliveries bigint not null,delivered_count bigint not null,
 failed_deliveries bigint not null,skipped_deliveries bigint not null,unmatched_receipts bigint not null,
 provider_health jsonb not null default '{}'::jsonb,request_id uuid
);
alter table public.mme_warranty_api_security_dashboard_snapshots enable row level security;
revoke all on public.mme_warranty_api_security_dashboard_snapshots from public,anon,authenticated;
grant select,insert on public.mme_warranty_api_security_dashboard_snapshots to service_role;

create or replace function public.mme_warranty_api_security_dashboard_summary(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v jsonb; v_alerts jsonb; v_deliveries jsonb; v_receipts jsonb;
begin
 select jsonb_build_object(
 'total',count(*),'open',count(*) filter(where alert_status='open'),
 'criticalOpen',count(*) filter(where alert_status='open' and severity='critical'),
 'highOpen',count(*) filter(where alert_status='open' and severity='high'),
 'acknowledged',count(*) filter(where alert_status='acknowledged'),
 'resolved',count(*) filter(where alert_status='resolved'),
 'dismissed',count(*) filter(where alert_status='dismissed'),
 'overdueOpen',count(*) filter(where alert_status='open' and escalation_due_at<=now()),
 'bySeverity',jsonb_build_object(
  'critical',count(*) filter(where severity='critical'),'high',count(*) filter(where severity='high'),
  'medium',count(*) filter(where severity='medium'),'low',count(*) filter(where severity='low')))
 into v_alerts from public.mme_warranty_api_security_alerts;
 select jsonb_build_object('queued',count(*) filter(where delivery_status='queued'),
 'sent',count(*) filter(where delivery_status='sent'),'delivered',count(*) filter(where delivery_status='delivered'),
 'failed',count(*) filter(where delivery_status='failed'),'skipped',count(*) filter(where delivery_status='skipped'),
 'byChannel',coalesce(jsonb_object_agg(channel,counts),'{}'::jsonb))
 into v_deliveries from public.mme_warranty_api_security_alert_deliveries
 cross join lateral (select count(*) as counts from public.mme_warranty_api_security_alert_deliveries d2 where d2.channel=mme_warranty_api_security_alert_deliveries.channel) x;
 select jsonb_build_object('received',count(*),'unmatched',count(*) filter(where delivery_id is null),
 'providers',coalesce(jsonb_object_agg(provider,provider_counts),'{}'::jsonb))
 into v_receipts from public.mme_warranty_api_security_provider_receipts
 cross join lateral(select count(*) as provider_counts from public.mme_warranty_api_security_provider_receipts r2 where r2.provider=mme_warranty_api_security_provider_receipts.provider)x;
 v:=jsonb_build_object('asOf',now(),'alerts',coalesce(v_alerts,'{}'::jsonb),'deliveries',coalesce(v_deliveries,'{}'::jsonb),'receipts',coalesce(v_receipts,'{}'::jsonb),'requestId',p_request_id);
 insert into public.mme_warranty_api_security_dashboard_snapshots(total_alerts,open_alerts,critical_open,high_open,acknowledged_alerts,resolved_alerts,dismissed_alerts,queued_deliveries,sent_deliveries,delivered_count,failed_deliveries,skipped_deliveries,unmatched_receipts,request_id)
 values(coalesce((v_alerts->>'total')::bigint,0),coalesce((v_alerts->>'open')::bigint,0),coalesce((v_alerts->>'criticalOpen')::bigint,0),coalesce((v_alerts->>'highOpen')::bigint,0),coalesce((v_alerts->>'acknowledged')::bigint,0),coalesce((v_alerts->>'resolved')::bigint,0),coalesce((v_alerts->>'dismissed')::bigint,0),coalesce((v_deliveries->>'queued')::bigint,0),coalesce((v_deliveries->>'sent')::bigint,0),coalesce((v_deliveries->>'delivered')::bigint,0),coalesce((v_deliveries->>'failed')::bigint,0),coalesce((v_deliveries->>'skipped')::bigint,0),coalesce((v_receipts->>'unmatched')::bigint,0),p_request_id);
 return v;
end $$;
revoke all on function public.mme_warranty_api_security_dashboard_summary(uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_dashboard_summary(uuid) to service_role;
commit;