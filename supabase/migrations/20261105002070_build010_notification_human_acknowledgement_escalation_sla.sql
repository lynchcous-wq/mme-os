begin;
alter table public.mme_security_notification_escalation_alerts
 add column if not exists acknowledgement_due_at timestamptz,
 add column if not exists acknowledged_at timestamptz,
 add column if not exists acknowledged_by uuid,
 add column if not exists acknowledgement_status text not null default 'pending',
 add column if not exists acknowledgement_note text;
alter table public.mme_security_notification_escalation_alerts drop constraint if exists mme_security_notification_alert_ack_status_check;
alter table public.mme_security_notification_escalation_alerts add constraint mme_security_notification_alert_ack_status_check check(acknowledgement_status in ('pending','acknowledged','overdue','closed'));
update public.mme_security_notification_escalation_alerts a set acknowledgement_due_at=coalesce(a.acknowledgement_due_at,a.created_at+make_interval(mins=>coalesce(p.acknowledge_within_minutes,15))) from public.mme_security_notification_escalation_policies p where a.policy_id=p.policy_id and a.policy_version=p.policy_version and a.acknowledgement_due_at is null;
create table public.mme_security_notification_acknowledgement_events(
 event_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 actor_id uuid not null,
 actor_roles text[] not null default '{}',
 event_type text not null check(event_type in ('acknowledged','note_added','sla_breached','ownership_transferred','closed')),
 note text,
 request_id uuid not null,
 occurred_at timestamptz not null default now(),
 unique(alert_id,actor_id,event_type,request_id)
);
create table public.mme_security_notification_acknowledgement_escalations(
 escalation_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 escalation_level integer not null default 1,
 due_at timestamptz not null,
 escalation_status text not null default 'pending' check(escalation_status in ('pending','processing','issued','cancelled','failed')),
 claimed_at timestamptz,
 claimed_by uuid,
 issued_at timestamptz,
 created_at timestamptz not null default now(),
 unique(alert_id,escalation_level)
);
create index mme_security_notification_ack_due_idx on public.mme_security_notification_escalation_alerts(acknowledgement_due_at) where acknowledgement_status='pending';
create index mme_security_notification_ack_escalation_due_idx on public.mme_security_notification_acknowledgement_escalations(escalation_status,due_at);
alter table public.mme_security_notification_acknowledgement_events enable row level security;
alter table public.mme_security_notification_acknowledgement_escalations enable row level security;
revoke all on public.mme_security_notification_acknowledgement_events,public.mme_security_notification_acknowledgement_escalations from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_acknowledgement_events,public.mme_security_notification_acknowledgement_escalations to service_role;
create or replace function public.mme_security_notification_acknowledge_alert(p_alert uuid,p_actor uuid,p_roles text[],p_note text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.mme_security_notification_escalation_alerts%rowtype;
begin
 select * into a from public.mme_security_notification_escalation_alerts where alert_id=p_alert for update;
 if not found then raise exception 'alert_not_found'; end if;
 if a.acknowledgement_status='acknowledged' then return jsonb_build_object('result','already_acknowledged','acknowledgedAt',a.acknowledged_at); end if;
 if a.acknowledgement_status='closed' then raise exception 'alert_closed'; end if;
 if not (coalesce(a.target_roles,'{}'::text[]) && coalesce(p_roles,'{}'::text[])) then raise exception 'actor_not_assigned_to_alert'; end if;
 update public.mme_security_notification_escalation_alerts set acknowledgement_status='acknowledged',acknowledged_at=now(),acknowledged_by=p_actor,acknowledgement_note=nullif(left(p_note,2000),''),updated_at=now() where alert_id=p_alert;
 insert into public.mme_security_notification_acknowledgement_events(alert_id,actor_id,actor_roles,event_type,note,request_id) values(p_alert,p_actor,p_roles,'acknowledged',nullif(left(p_note,2000),''),p_request);
 update public.mme_security_notification_acknowledgement_escalations set escalation_status='cancelled' where alert_id=p_alert and escalation_status in ('pending','processing');
 return jsonb_build_object('result','acknowledged','alertId',p_alert,'acknowledgedAt',now());
end $$;
create or replace function public.mme_security_notification_claim_acknowledgement_sla(p_worker uuid,p_limit integer default 50)
returns table(alert_id uuid,severity text,title text,summary text,target_roles text[],acknowledgement_due_at timestamptz,escalation_level integer)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query with overdue as(
  update public.mme_security_notification_escalation_alerts a set acknowledgement_status='overdue',updated_at=now()
  where a.acknowledgement_status='pending' and a.acknowledgement_due_at<=now()
  returning a.alert_id,a.severity,a.title,a.summary,a.target_roles,a.acknowledgement_due_at
 ), inserted as(
  insert into public.mme_security_notification_acknowledgement_escalations(alert_id,escalation_level,due_at)
  select o.alert_id,1,now() from overdue o on conflict(alert_id,escalation_level) do nothing returning alert_id,escalation_level
 )
 select o.alert_id,o.severity,o.title,o.summary,o.target_roles,o.acknowledgement_due_at,1 from overdue o;
end $$;
revoke all on function public.mme_security_notification_acknowledge_alert(uuid,uuid,text[],text,uuid),public.mme_security_notification_claim_acknowledgement_sla(uuid,integer) from public,anon,authenticated;
grant execute on function public.mme_security_notification_acknowledge_alert(uuid,uuid,text[],text,uuid),public.mme_security_notification_claim_acknowledgement_sla(uuid,integer) to service_role;
commit;