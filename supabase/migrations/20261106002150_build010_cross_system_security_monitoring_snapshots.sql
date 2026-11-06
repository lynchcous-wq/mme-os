begin;

-- Executive-safe, cross-system security monitoring snapshots.
create table if not exists public.mme_security_monitoring_snapshots (
  snapshot_id uuid primary key default gen_random_uuid(),
  generated_at timestamptz not null default now(),
  overall_status text not null check (overall_status in ('healthy','degraded','critical','unknown')),
  source_summary jsonb not null default '[]'::jsonb,
  delivery_summary jsonb not null default '{}'::jsonb,
  alert_summary jsonb not null default '{}'::jsonb,
  receipt_summary jsonb not null default '{}'::jsonb,
  snapshot_payload jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists mme_security_monitoring_snapshots_generated_idx
  on public.mme_security_monitoring_snapshots(generated_at desc);

alter table public.mme_security_monitoring_snapshots enable row level security;
revoke all on public.mme_security_monitoring_snapshots from public,anon,authenticated;
grant select,insert on public.mme_security_monitoring_snapshots to service_role;

create or replace function public.mme_security_monitoring_capture_snapshot()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  sources jsonb;
  delivery jsonb;
  alerts jsonb;
  receipts jsonb;
  overall text;
  payload jsonb;
  snapshot uuid;
  source_count integer;
  unhealthy_count integer;
  dead_count bigint;
  open_critical bigint;
  stale_count integer;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'source',source_system,
    'status',status,
    'lastEventAt',last_event_at,
    'lastSuccessAt',last_success_at,
    'lastFailureAt',last_failure_at,
    'consecutiveFailures',consecutive_failures,
    'acceptedCount',accepted_count,
    'rejectedCount',rejected_count,
    'lastErrorCode',last_error_code,
    'updatedAt',updated_at
  ) order by source_system),'[]'::jsonb),
  count(*)::integer,
  count(*) filter(where status in ('degraded','offline','misconfigured'))::integer,
  count(*) filter(where last_event_at is null or last_event_at<now()-interval '24 hours')::integer
  into sources,source_count,unhealthy_count,stale_count
  from public.mme_security_event_source_health;

  select jsonb_build_object(
    'eventQueue',jsonb_build_object(
      'pending',count(*) filter(where status='pending'),
      'processing',count(*) filter(where status='processing'),
      'retryWait',count(*) filter(where status='retry_wait'),
      'deadLetter',count(*) filter(where status='dead_letter')
    ),
    'notificationChannels',coalesce((
      select jsonb_object_agg(status,total) from (
        select status,count(*)::bigint as total
        from public.mme_security_notification_escalation_channel_deliveries
        group by status
      ) q
    ),'{}'::jsonb)
  ) into delivery
  from public.mme_warranty_security_event_delivery_queue;

  select jsonb_build_object(
    'open',count(*) filter(where status='open'),
    'acknowledged',count(*) filter(where status='acknowledged'),
    'criticalOpen',count(*) filter(where status='open' and severity='critical'),
    'warningOpen',count(*) filter(where status='open' and severity='warning')
  ),count(*) filter(where status='open' and severity='critical')
  into alerts,open_critical
  from public.mme_security_integration_alerts;

  select jsonb_build_object(
    'total',count(*),
    'processed',count(*) filter(where processing_status='processed'),
    'unmatched',count(*) filter(where processing_status='unmatched'),
    'ambiguous',count(*) filter(where processing_status='ambiguous'),
    'received',count(*) filter(where processing_status='received'),
    'last24Hours',count(*) filter(where received_at>=now()-interval '24 hours')
  ) into receipts
  from public.mme_security_notification_provider_receipt_events;

  select coalesce((delivery->'eventQueue'->>'deadLetter')::bigint,0) into dead_count;

  overall := case
    when open_critical>0 or dead_count>0 or exists (
      select 1 from public.mme_security_event_source_health where status='offline'
    ) then 'critical'
    when unhealthy_count>0 or stale_count>0
      or coalesce((delivery->'eventQueue'->>'retryWait')::bigint,0)>0
      or coalesce((receipts->>'ambiguous')::bigint,0)>0 then 'degraded'
    when source_count=0 then 'unknown'
    else 'healthy'
  end;

  payload:=jsonb_build_object(
    'overallStatus',overall,
    'generatedAt',now(),
    'sources',sources,
    'sourceCount',source_count,
    'unhealthySourceCount',unhealthy_count,
    'staleSourceCount',stale_count,
    'delivery',delivery,
    'alerts',alerts,
    'receipts',receipts
  );

  insert into public.mme_security_monitoring_snapshots(
    overall_status,source_summary,delivery_summary,alert_summary,receipt_summary,snapshot_payload
  ) values(overall,sources,delivery,alerts,receipts,payload)
  returning snapshot_id into snapshot;

  return payload||jsonb_build_object('snapshotId',snapshot);
end
$$;

revoke all on function public.mme_security_monitoring_capture_snapshot() from public,anon,authenticated;
grant execute on function public.mme_security_monitoring_capture_snapshot() to service_role;

commit;
