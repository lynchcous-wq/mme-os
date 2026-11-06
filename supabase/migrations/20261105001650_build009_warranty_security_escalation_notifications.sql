begin;
create table public.mme_warranty_api_security_notification_recipients(
 recipient_id uuid primary key default gen_random_uuid(),
 user_id uuid,
 role_key text not null check(role_key in ('ceo','privacy_officer','manager')),
 channel text not null check(channel in ('email','sms')),
 destination text not null,
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 unique(role_key,channel,destination)
);
create table public.mme_warranty_api_security_escalation_policies(
 policy_id uuid primary key default gen_random_uuid(),
 severity text not null check(severity in ('low','medium','high','critical')),
 initial_delay_minutes integer not null default 0 check(initial_delay_minutes between 0 and 10080),
 repeat_after_minutes integer not null default 30 check(repeat_after_minutes between 1 and 10080),
 max_attempts integer not null default 5 check(max_attempts between 1 and 20),
 notify_roles text[] not null default array['ceo','privacy_officer'],
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 unique(severity)
);
create table public.mme_warranty_api_security_notification_outbox(
 notification_id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_warranty_api_security_incidents(incident_id) on delete restrict,
 recipient_id uuid not null references public.mme_warranty_api_security_notification_recipients(recipient_id) on delete restrict,
 channel text not null check(channel in ('email','sms')),
 template_key text not null check(template_key in ('incident_opened','incident_escalated','incident_acknowledged','incident_resolved')),
 subject text,
 body text not null,
 status text not null default 'pending' check(status in ('pending','sending','sent','retry','failed','cancelled')),
 attempt_count integer not null default 0 check(attempt_count>=0),
 next_attempt_at timestamptz not null default now(),
 provider_message_id text,
 last_error_code text,
 created_at timestamptz not null default now(),
 sent_at timestamptz,
 unique(incident_id,recipient_id,template_key)
);
create table public.mme_warranty_api_security_notification_attempts(
 attempt_id bigint generated always as identity primary key,
 notification_id uuid not null references public.mme_warranty_api_security_notification_outbox(notification_id) on delete restrict,
 attempt_number integer not null,
 outcome text not null check(outcome in ('sent','retry','failed')),
 provider text not null,
 provider_message_id text,
 error_code text,
 attempted_at timestamptz not null default now(),
 unique(notification_id,attempt_number)
);
create table public.mme_warranty_api_security_incident_acknowledgements(
 acknowledgement_id bigint generated always as identity primary key,
 incident_id uuid not null references public.mme_warranty_api_security_incidents(incident_id) on delete restrict,
 actor_id uuid not null,
 acknowledged_at timestamptz not null default now(),
 note text,
 unique(incident_id,actor_id)
);
alter table public.mme_warranty_api_security_notification_recipients enable row level security;
alter table public.mme_warranty_api_security_escalation_policies enable row level security;
alter table public.mme_warranty_api_security_notification_outbox enable row level security;
alter table public.mme_warranty_api_security_notification_attempts enable row level security;
alter table public.mme_warranty_api_security_incident_acknowledgements enable row level security;
revoke all on public.mme_warranty_api_security_notification_recipients,public.mme_warranty_api_security_escalation_policies,public.mme_warranty_api_security_notification_outbox,public.mme_warranty_api_security_notification_attempts,public.mme_warranty_api_security_incident_acknowledgements from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_notification_recipients to service_role;
grant select,insert,update on public.mme_warranty_api_security_escalation_policies to service_role;
grant select,insert,update on public.mme_warranty_api_security_notification_outbox to service_role;
grant select,insert on public.mme_warranty_api_security_notification_attempts to service_role;
grant select,insert on public.mme_warranty_api_security_incident_acknowledgements to service_role;
insert into public.mme_warranty_api_security_escalation_policies(severity,initial_delay_minutes,repeat_after_minutes,max_attempts,notify_roles)
values('low',60,240,3,array['manager']),('medium',15,120,4,array['manager','privacy_officer']),('high',5,30,5,array['ceo','privacy_officer']),('critical',0,10,8,array['ceo','privacy_officer'])
on conflict(severity) do nothing;

create or replace function public.mme_warranty_api_enqueue_incident_notifications(p_batch_size integer default 100)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_incident record; v_policy record; v_recipient record; v_count integer:=0; v_template text;
begin
 if p_batch_size<1 or p_batch_size>500 then raise exception 'invalid_batch_size'; end if;
 for v_incident in select * from public.mme_warranty_api_security_incidents where status in ('open','investigating','contained') and opened_at<=now() order by opened_at desc limit p_batch_size loop
  select * into v_policy from public.mme_warranty_api_security_escalation_policies where severity=v_incident.severity and enabled;
  if not found or exists(select 1 from public.mme_warranty_api_security_incident_acknowledgements a where a.incident_id=v_incident.incident_id) then continue; end if;
  if now()<v_incident.opened_at+make_interval(mins=>v_policy.initial_delay_minutes) then continue; end if;
  v_template:=case when exists(select 1 from public.mme_warranty_api_security_notification_outbox o where o.incident_id=v_incident.incident_id and o.template_key='incident_opened') then 'incident_escalated' else 'incident_opened' end;
  if v_template='incident_escalated' and now()<v_incident.opened_at+make_interval(mins=>v_policy.repeat_after_minutes) then continue; end if;
  for v_recipient in select * from public.mme_warranty_api_security_notification_recipients where enabled and role_key=any(v_policy.notify_roles) loop
   insert into public.mme_warranty_api_security_notification_outbox(incident_id,recipient_id,channel,template_key,subject,body)
   values(v_incident.incident_id,v_recipient.recipient_id,v_recipient.channel,v_template,
    'MME security incident #'||v_incident.incident_number,
    'A '||v_incident.severity||' security incident requires attention. Incident #'||v_incident.incident_number||': '||left(v_incident.title,180))
   on conflict(incident_id,recipient_id,template_key) do nothing;
   if found then v_count:=v_count+1; end if;
  end loop;
 end loop;
 return v_count;
end $$;
create or replace function public.mme_warranty_api_acknowledge_security_incident(p_incident_id uuid,p_actor_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_actor_id is null then raise exception 'actor_required'; end if;
 if not exists(select 1 from public.mme_warranty_api_security_incidents where incident_id=p_incident_id and status in ('open','investigating','contained')) then raise exception 'incident_not_acknowledgeable'; end if;
 insert into public.mme_warranty_api_security_incident_acknowledgements(incident_id,actor_id,note)
 values(p_incident_id,p_actor_id,left(p_note,500)) on conflict(incident_id,actor_id) do nothing;
 insert into public.mme_warranty_api_security_incident_events(incident_id,actor_id,event_type,reason_code,note)
 values(p_incident_id,p_actor_id,'investigation_note','incident_acknowledged',left(coalesce(p_note,'Incident acknowledged'),500));
 update public.mme_warranty_api_security_notification_outbox set status='cancelled' where incident_id=p_incident_id and status in ('pending','retry');
 return true;
end $$;
revoke all on function public.mme_warranty_api_enqueue_incident_notifications(integer) from public,anon,authenticated;
revoke all on function public.mme_warranty_api_acknowledge_security_incident(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_enqueue_incident_notifications(integer) to service_role;
grant execute on function public.mme_warranty_api_acknowledge_security_incident(uuid,uuid,text) to service_role;
commit;