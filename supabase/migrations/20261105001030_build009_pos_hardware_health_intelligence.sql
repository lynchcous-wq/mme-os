-- Build 009.22: device telemetry, explainable health scores, alerts, diagnostics and maintenance tasks.
begin;

create table public.mme_pos_device_telemetry (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 provider_event_id text not null check(length(btrim(provider_event_id)) between 1 and 160),
 observed_at timestamptz not null,
 received_at timestamptz not null default now(),
 metrics jsonb not null check(jsonb_typeof(metrics)='object'),
 unique(device_id,provider_event_id),
 check(observed_at<=now()+interval '60 seconds')
);
create index mme_pos_device_telemetry_recent_idx
 on public.mme_pos_device_telemetry(device_id,observed_at desc);

create table public.mme_pos_device_health_scores (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 score integer not null check(score between 0 and 100),
 health_band text not null check(health_band in ('excellent','healthy','attention','degraded','critical','unknown')),
 scored_at timestamptz not null default now(),
 factors jsonb not null check(jsonb_typeof(factors)='array'),
 scoring_version text not null default '1.0',
 unique(device_id,scored_at)
);
create index mme_pos_device_health_latest_idx on public.mme_pos_device_health_scores(device_id,scored_at desc);

create table public.mme_pos_device_health_alerts (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 health_score_id uuid references public.mme_pos_device_health_scores(id) on delete restrict,
 alert_type text not null check(alert_type in ('device_offline','heartbeat_stale','health_degraded','health_critical','telemetry_threshold')),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','acknowledged','resolved','suppressed')),
 title text not null,
 explanation text not null,
 created_at timestamptz not null default now(),
 resolved_at timestamptz
);
create unique index mme_pos_device_health_alert_active_once
 on public.mme_pos_device_health_alerts(device_id,alert_type)
 where status in ('open','acknowledged');
create index mme_pos_device_health_alert_queue_idx
 on public.mme_pos_device_health_alerts(status,severity,created_at desc);

create table public.mme_pos_device_diagnostics (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 diagnostic_type text not null check(diagnostic_type in ('connectivity','heartbeat','printer','drawer','payment_terminal','thermal','general')),
 result text not null check(result in ('pass','warning','fail','not_supported','unknown')),
 details jsonb not null default '{}'::jsonb check(jsonb_typeof(details)='object'),
 initiated_by text not null check(initiated_by in ('scheduled','it_user','health_engine')),
 created_at timestamptz not null default now()
);

create table public.mme_pos_device_maintenance_tasks (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 source_alert_id uuid references public.mme_pos_device_health_alerts(id) on delete restrict,
 priority text not null check(priority in ('low','normal','high','urgent')),
 status text not null default 'open' check(status in ('open','assigned','in_progress','blocked','completed','cancelled')),
 title text not null,
 recommended_action text not null,
 assigned_to_person_id uuid,
 created_at timestamptz not null default now(),
 due_at timestamptz,
 completed_at timestamptz,
 resolution_note text
);
create unique index mme_pos_device_maintenance_active_alert_once
 on public.mme_pos_device_maintenance_tasks(source_alert_id)
 where source_alert_id is not null and status in ('open','assigned','in_progress','blocked');

create table public.mme_pos_device_baselines (
 id uuid primary key default gen_random_uuid(),
 device_type text not null check(device_type in ('cash_drawer','receipt_printer','payment_terminal','register_controller')),
 metric_key text not null check(metric_key in ('latency_ms','packet_loss_pct','error_rate_pct','temperature_c','battery_pct','paper_remaining_pct')),
 warning_threshold numeric not null,
 critical_threshold numeric not null,
 unit text not null,
 threshold_direction text not null check(threshold_direction in ('higher_is_worse','lower_is_worse')),
 enabled boolean not null default true,
 updated_at timestamptz not null default now(),
 check(warning_threshold<>critical_threshold)
);
create unique index mme_pos_device_baseline_key_once on public.mme_pos_device_baselines(device_type,metric_key);

alter table public.mme_pos_device_telemetry enable row level security;
alter table public.mme_pos_device_health_scores enable row level security;
alter table public.mme_pos_device_health_alerts enable row level security;
alter table public.mme_pos_device_diagnostics enable row level security;
alter table public.mme_pos_device_maintenance_tasks enable row level security;
alter table public.mme_pos_device_baselines enable row level security;
revoke all on public.mme_pos_device_telemetry,public.mme_pos_device_health_scores,
 public.mme_pos_device_health_alerts,public.mme_pos_device_diagnostics,
 public.mme_pos_device_maintenance_tasks,public.mme_pos_device_baselines from public,anon,authenticated;
grant all on public.mme_pos_device_telemetry,public.mme_pos_device_health_scores,
 public.mme_pos_device_health_alerts,public.mme_pos_device_diagnostics,
 public.mme_pos_device_maintenance_tasks,public.mme_pos_device_baselines to service_role;

create or replace function public.mme_pos_ingest_device_telemetry(
 p_device_id uuid,p_provider_event_id text,p_observed_at timestamptz,p_metrics jsonb
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_type text; v_key text; v_value numeric;
begin
 if p_device_id is null or p_provider_event_id is null
  or length(btrim(p_provider_event_id)) not between 1 and 160
  or p_observed_at is null or p_observed_at<now()-interval '24 hours'
  or p_observed_at>now()+interval '60 seconds'
  or p_metrics is null or jsonb_typeof(p_metrics)<>'object'
  or (select count(*) from jsonb_object_keys(p_metrics)) not between 1 and 12 then
  raise exception 'Invalid device telemetry envelope' using errcode='22023';
 end if;
 select device_type into v_type from public.mme_pos_register_devices
  where id=p_device_id and status<>'retired' for update;
 if not found then raise exception 'Registered device not found' using errcode='P0002'; end if;
 for v_key in select jsonb_object_keys(p_metrics) loop
  if v_key not in ('latency_ms','packet_loss_pct','error_rate_pct','temperature_c','battery_pct','paper_remaining_pct')
    or jsonb_typeof(p_metrics->v_key)<>'number' then
   raise exception 'Unsupported telemetry metric' using errcode='22023';
  end if;
  v_value:=(p_metrics->>v_key)::numeric;
  if (v_key='latency_ms' and v_value not between 0 and 120000)
   or (v_key in ('packet_loss_pct','error_rate_pct','battery_pct','paper_remaining_pct') and v_value not between 0 and 100)
   or (v_key='temperature_c' and v_value not between -40 and 150) then
   raise exception 'Telemetry metric outside supported range' using errcode='22023';
  end if;
 end loop;
 insert into public.mme_pos_device_telemetry(device_id,provider_event_id,observed_at,metrics)
 values(p_device_id,btrim(p_provider_event_id),p_observed_at,p_metrics)
 on conflict(device_id,provider_event_id) do nothing returning id into v_id;
 if v_id is null then
  select id into v_id from public.mme_pos_device_telemetry
   where device_id=p_device_id and provider_event_id=btrim(p_provider_event_id);
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_calculate_device_health(p_device_id uuid,p_scored_at timestamptz default now())
returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_device public.mme_pos_register_devices%rowtype;
 v_score integer:=100; v_band text; v_factor jsonb:='[]'::jsonb;
 v_age_seconds numeric; v_active_incidents integer:=0; v_id uuid;
 v_telemetry jsonb; v_metric record; v_alert_id uuid; v_alert_type text; v_severity text; v_task_priority text;
begin
 if p_device_id is null or p_scored_at is null or p_scored_at>now()+interval '60 seconds' then
  raise exception 'Invalid health scoring request' using errcode='22023';
 end if;
 select * into v_device from public.mme_pos_register_devices where id=p_device_id and status<>'retired' for update;
 if not found then raise exception 'Device not found' using errcode='P0002'; end if;

 if v_device.status='offline' then
  v_score:=v_score-55; v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor','device_status','impact',-55,'evidence','Device registry reports offline'));
 elsif v_device.status='maintenance' then
  v_score:=v_score-20; v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor','device_status','impact',-20,'evidence','Device is in maintenance'));
 elsif v_device.status='pending' then
  v_score:=v_score-10; v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor','device_status','impact',-10,'evidence','Device pairing or activation is pending'));
 end if;

 v_age_seconds:=extract(epoch from (p_scored_at-coalesce(v_device.last_heartbeat_at,v_device.last_seen_at,v_device.created_at)));
 if v_device.paired_at is not null and v_age_seconds>greatest(v_device.heartbeat_interval_seconds*3,180) then
  v_score:=v_score-30; v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor','heartbeat_staleness','impact',-30,'age_seconds',v_age_seconds));
 elsif v_device.paired_at is not null and v_age_seconds>greatest(v_device.heartbeat_interval_seconds*2,120) then
  v_score:=v_score-15; v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor','heartbeat_staleness','impact',-15,'age_seconds',v_age_seconds));
 end if;

 select count(*) into v_active_incidents from public.mme_pos_drawer_it_incidents
  where device_id=p_device_id and status in ('open','acknowledged','in_progress');
 if v_active_incidents>0 then
  v_score:=v_score-least(v_active_incidents*10,30);
  v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor','active_it_incidents','impact',-least(v_active_incidents*10,30),'count',v_active_incidents));
 end if;

 select metrics into v_telemetry from public.mme_pos_device_telemetry
  where device_id=p_device_id and observed_at>=p_scored_at-interval '30 minutes'
  order by observed_at desc limit 1;
 if v_telemetry is null then
  v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor','telemetry','impact',0,'evidence','No recent optional telemetry; score is based on available registry and incident evidence'));
 else
  for v_metric in select b.metric_key,b.warning_threshold,b.critical_threshold,b.threshold_direction,
    (v_telemetry->>b.metric_key)::numeric as metric_value,b.unit
    from public.mme_pos_device_baselines b
    where b.device_type=v_device.device_type and b.enabled and v_telemetry ? b.metric_key
  loop
   if (v_metric.threshold_direction='higher_is_worse'
       and v_metric.metric_value>=greatest(v_metric.warning_threshold,v_metric.critical_threshold))
     or (v_metric.threshold_direction='lower_is_worse'
       and v_metric.metric_value<=least(v_metric.warning_threshold,v_metric.critical_threshold)) then
    v_score:=v_score-20;
    v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor',v_metric.metric_key,'impact',-20,'value',v_metric.metric_value,'unit',v_metric.unit,'critical_threshold',v_metric.critical_threshold));
   elsif (v_metric.threshold_direction='higher_is_worse'
       and v_metric.metric_value>=least(v_metric.warning_threshold,v_metric.critical_threshold))
     or (v_metric.threshold_direction='lower_is_worse'
       and v_metric.metric_value<=greatest(v_metric.warning_threshold,v_metric.critical_threshold)) then
    v_score:=v_score-10;
    v_factor:=v_factor||jsonb_build_array(jsonb_build_object('factor',v_metric.metric_key,'impact',-10,'value',v_metric.metric_value,'unit',v_metric.unit,'warning_threshold',v_metric.warning_threshold));
   end if;
  end loop;
 end if;
 v_score:=greatest(0,least(100,v_score));
 v_band:=case when v_device.paired_at is null then 'unknown'
  when v_score>=95 then 'excellent' when v_score>=85 then 'healthy'
  when v_score>=70 then 'attention' when v_score>=50 then 'degraded' else 'critical' end;
 insert into public.mme_pos_device_health_scores(device_id,score,health_band,scored_at,factors)
 values(p_device_id,v_score,v_band,p_scored_at,v_factor) returning id into v_id;

 if v_band in ('degraded','critical','attention') then
  v_alert_type:=case when v_device.status='offline' then 'device_offline'
    when v_age_seconds>greatest(v_device.heartbeat_interval_seconds*3,180) then 'heartbeat_stale'
    when v_band='critical' then 'health_critical' else 'health_degraded' end;
  v_severity:=case when v_band='critical' then 'critical' when v_band='degraded' then 'high' else 'medium' end;
  insert into public.mme_pos_device_health_alerts(device_id,health_score_id,alert_type,severity,title,explanation)
  values(p_device_id,v_id,v_alert_type,v_severity,'POS device health requires attention',
   'Score '||v_score||'/100 ('||v_band||'). Evidence: '||left(v_factor::text,1800))
  on conflict(device_id,alert_type) where status in ('open','acknowledged') do nothing
  returning id into v_alert_id;
  if v_alert_id is not null then
   v_task_priority:=case when v_band='critical' then 'urgent' when v_band='degraded' then 'high' else 'normal' end;
   insert into public.mme_pos_device_maintenance_tasks(device_id,source_alert_id,priority,title,recommended_action)
   values(p_device_id,v_alert_id,v_task_priority,'Inspect POS device health',
    'Review the recorded health factors, run supported diagnostics, and repair or replace only after technician verification.')
   on conflict do nothing;
  end if;
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_sweep_device_health(p_limit integer default 200,p_scored_at timestamptz default now())
returns integer language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device record; v_count integer:=0;
begin
 if p_limit not between 1 and 1000 or p_scored_at is null then
  raise exception 'Invalid health sweep parameters' using errcode='22023';
 end if;
 for v_device in select id from public.mme_pos_register_devices
  where status<>'retired' order by updated_at asc limit p_limit
 loop
  perform public.mme_pos_calculate_device_health(v_device.id,p_scored_at);
  v_count:=v_count+1;
 end loop;
 return v_count;
end;
$$;

revoke all on function public.mme_pos_ingest_device_telemetry(uuid,text,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function public.mme_pos_calculate_device_health(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_pos_sweep_device_health(integer,timestamptz) from public,anon,authenticated;
grant execute on function public.mme_pos_ingest_device_telemetry(uuid,text,timestamptz,jsonb) to service_role;
grant execute on function public.mme_pos_calculate_device_health(uuid,timestamptz) to service_role;
grant execute on function public.mme_pos_sweep_device_health(integer,timestamptz) to service_role;

comment on table public.mme_pos_device_health_scores is 'Explainable deterministic health scores based only on observed registry, heartbeat, incident and optional telemetry evidence; not an AI diagnosis.';
comment on table public.mme_pos_device_health_alerts is 'Deduplicated actionable health alerts; alerts are not proof of misuse or employee misconduct.';
comment on table public.mme_pos_device_baselines is 'Versionable-by-update threshold configuration; threshold direction and units must be reviewed for each metric/device type before enabling.';
commit;
