begin;
create table public.mme_warranty_api_security_detections (
 detection_id bigint generated always as identity primary key,
 event_id bigint not null references public.mme_warranty_api_security_events(event_id) on delete restrict,
 rule_id uuid not null references public.mme_warranty_api_security_monitoring_rules(rule_id) on delete restrict,
 incident_id uuid not null references public.mme_warranty_api_security_incidents(incident_id) on delete restrict,
 matched_count integer not null, window_started_at timestamptz not null, detected_at timestamptz not null default now(),
 unique(event_id,rule_id)
);
create table public.mme_warranty_api_security_worker_runs (
 run_id uuid primary key default gen_random_uuid(),started_at timestamptz not null default now(),
 completed_at timestamptz,status text not null check(status in ('running','completed','failed')),
 scanned_events integer not null default 0,matched_rules integer not null default 0,incidents_created integer not null default 0,error_code text
);
alter table public.mme_warranty_api_security_detections enable row level security;
alter table public.mme_warranty_api_security_worker_runs enable row level security;
revoke all on public.mme_warranty_api_security_detections,public.mme_warranty_api_security_worker_runs from public,anon,authenticated;
grant select,insert on public.mme_warranty_api_security_detections to service_role;
grant select,insert,update on public.mme_warranty_api_security_worker_runs to service_role;
create or replace function public.mme_warranty_api_run_security_detection(p_batch_size integer default 250)
returns table(run_id uuid,scanned_events integer,matched_rules integer,incidents_created integer)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_run uuid; v_event record; v_rule record; v_incident uuid; v_matches integer:=0; v_created integer:=0; v_scanned integer:=0;
begin
 if p_batch_size<1 or p_batch_size>1000 then raise exception 'invalid_batch_size'; end if;
 insert into public.mme_warranty_api_security_worker_runs(status) values('running') returning mme_warranty_api_security_worker_runs.run_id into v_run;
 for v_event in select * from public.mme_warranty_api_security_events where status in ('open','investigating') order by last_seen_at desc limit p_batch_size loop
  v_scanned:=v_scanned+1;
  for v_rule in select * from public.mme_warranty_api_security_monitoring_rules where enabled and event_type=v_event.event_type and v_event.last_seen_at>=now()-make_interval(mins=>window_minutes) and v_event.occurrence_count>=threshold_count loop
   v_matches:=v_matches+1;
   if not exists(select 1 from public.mme_warranty_api_security_detections d where d.event_id=v_event.event_id and d.rule_id=v_rule.rule_id) then
    insert into public.mme_warranty_api_security_incidents(title,description,severity,status)
    values('Automated security detection: '||v_event.event_type,'Threshold rule matched. Event group='||v_event.event_id::text||'; occurrences='||v_event.occurrence_count::text||'; reason='||v_event.reason_code,
     case v_rule.severity when 'critical' then 'critical' when 'high' then 'high' when 'warning' then 'medium' else 'low' end,'open')
    returning incident_id into v_incident;
    insert into public.mme_warranty_api_security_detections(event_id,rule_id,incident_id,matched_count,window_started_at)
    values(v_event.event_id,v_rule.rule_id,v_incident,v_event.occurrence_count,now()-make_interval(mins=>v_rule.window_minutes)) on conflict(event_id,rule_id) do nothing;
    if found then v_created:=v_created+1; insert into public.mme_warranty_api_security_incident_events(incident_id,security_event_id,event_type,reason_code) values(v_incident,v_event.event_id,'created','automated_threshold_detection'); end if;
   end if;
  end loop;
 end loop;
 update public.mme_warranty_api_security_worker_runs set status='completed',completed_at=now(),scanned_events=v_scanned,matched_rules=v_matches,incidents_created=v_created where mme_warranty_api_security_worker_runs.run_id=v_run;
 return query select v_run,v_scanned,v_matches,v_created;
exception when others then
 if v_run is not null then update public.mme_warranty_api_security_worker_runs set status='failed',completed_at=now(),error_code='security_detection_failed' where mme_warranty_api_security_worker_runs.run_id=v_run; end if;
 raise;
end $$;
revoke all on function public.mme_warranty_api_run_security_detection(integer) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_run_security_detection(integer) to service_role;
commit;