begin;
create table public.mme_warranty_api_security_alerts (
 alert_id uuid primary key default gen_random_uuid(),
 signal_id uuid not null references public.mme_warranty_api_security_risk_signals(signal_id) on delete restrict,
 severity text not null check(severity in ('low','medium','high','critical')),
 alert_status text not null default 'open' check(alert_status in ('open','acknowledged','resolved','dismissed')),
 title text not null check(length(trim(title)) between 5 and 180),
 message text not null check(length(trim(message)) between 10 and 2000),
 routed_roles text[] not null default array['ceo','privacy_officer']::text[],
 acknowledged_by uuid,
 acknowledged_at timestamptz,
 acknowledgment_note text,
 escalation_due_at timestamptz not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(signal_id),
 check((alert_status='open' and acknowledged_by is null and acknowledged_at is null) or (alert_status<>'open' and acknowledged_by is not null and acknowledged_at is not null))
);
create index mme_warranty_security_alert_queue_idx on public.mme_warranty_api_security_alerts(alert_status,severity,escalation_due_at);
alter table public.mme_warranty_api_security_alerts enable row level security;
revoke all on public.mme_warranty_api_security_alerts from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_alerts to service_role;
revoke delete,truncate on public.mme_warranty_api_security_alerts from public,anon,authenticated,service_role;

create table public.mme_warranty_api_security_alert_events (
 event_id bigint generated always as identity primary key,
 alert_id uuid not null references public.mme_warranty_api_security_alerts(alert_id) on delete restrict,
 event_type text not null check(event_type in ('created','acknowledged','resolved','dismissed','escalated','delivery_attempted')),
 actor_id uuid,
 details jsonb not null default '{}'::jsonb,
 request_id uuid,
 occurred_at timestamptz not null default now()
);
alter table public.mme_warranty_api_security_alert_events enable row level security;
revoke all on public.mme_warranty_api_security_alert_events from public,anon,authenticated;
grant select,insert on public.mme_warranty_api_security_alert_events to service_role;

create table public.mme_warranty_api_security_alert_deliveries (
 delivery_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_warranty_api_security_alerts(alert_id) on delete restrict,
 channel text not null check(channel in ('in_app','email','sms','webhook')),
 recipient_role text not null,
 delivery_status text not null default 'queued' check(delivery_status in ('queued','sent','delivered','failed','skipped')),
 provider_reference text,
 attempt_count integer not null default 0 check(attempt_count>=0),
 last_attempt_at timestamptz,
 delivered_at timestamptz,
 last_error_code text,
 created_at timestamptz not null default now(),
 unique(alert_id,channel,recipient_role)
);
alter table public.mme_warranty_api_security_alert_deliveries enable row level security;
revoke all on public.mme_warranty_api_security_alert_deliveries from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_alert_deliveries to service_role;

create or replace function public.mme_warranty_api_security_create_alert()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_alert uuid; v_roles text[]; v_due timestamptz;
begin
 v_roles:=case when new.severity in ('high','critical') then array['ceo','privacy_officer','manager']::text[] else array['ceo','privacy_officer']::text[] end;
 v_due:=now()+case new.severity when 'critical' then interval '5 minutes' when 'high' then interval '15 minutes' when 'medium' then interval '4 hours' else interval '24 hours' end;
 insert into public.mme_warranty_api_security_alerts(signal_id,severity,title,message,routed_roles,escalation_due_at)
 values(new.signal_id,new.severity,initcap(replace(new.signal_type,'_',' ')),new.explanation,v_roles,v_due)
 on conflict(signal_id) do nothing returning alert_id into v_alert;
 if v_alert is not null then
  insert into public.mme_warranty_api_security_alert_deliveries(alert_id,channel,recipient_role,delivery_status)
  select v_alert,'in_app',r,'queued' from unnest(v_roles) r;
  insert into public.mme_warranty_api_security_alert_events(alert_id,event_type,details)
  values(v_alert,'created',jsonb_build_object('severity',new.severity,'signalType',new.signal_type));
 end if;
 return new;
end $$;
create trigger mme_warranty_security_signal_alert_trigger
after insert on public.mme_warranty_api_security_risk_signals
for each row execute function public.mme_warranty_api_security_create_alert();

create or replace function public.mme_warranty_api_security_alert_action(p_alert_id uuid,p_actor_id uuid,p_action text,p_note text,p_request_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_status text;
begin
 if p_action not in ('acknowledged','resolved','dismissed') then raise exception 'invalid_alert_action'; end if;
 if p_action in ('resolved','dismissed') and length(trim(coalesce(p_note,'')))<5 then raise exception 'alert_action_note_required'; end if;
 select alert_status into v_status from public.mme_warranty_api_security_alerts where alert_id=p_alert_id for update;
 if not found then raise exception 'alert_not_found'; end if;
 if v_status in ('resolved','dismissed') then raise exception 'alert_already_closed'; end if;
 update public.mme_warranty_api_security_alerts set alert_status=p_action,acknowledged_by=p_actor_id,acknowledged_at=coalesce(acknowledged_at,now()),acknowledgment_note=nullif(trim(coalesce(p_note,'')),''),updated_at=now() where alert_id=p_alert_id;
 insert into public.mme_warranty_api_security_alert_events(alert_id,event_type,actor_id,details,request_id)
 values(p_alert_id,p_action,p_actor_id,jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')),p_request_id);
end $$;
revoke all on function public.mme_warranty_api_security_alert_action(uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_alert_action(uuid,uuid,text,text,uuid) to service_role;
revoke all on function public.mme_warranty_api_security_create_alert() from public,anon,authenticated;
commit;