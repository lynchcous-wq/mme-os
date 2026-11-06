-- Build 009.48 — controlled financial alerts, recipient routing and acknowledgment.
-- Delivery is persisted to an outbox; no email provider is invoked by this migration.
begin;

create table public.mme_pos_financial_alert_subscriptions (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 recipient_person_id uuid not null,
 audience_role text not null check(audience_role in ('executive','finance','store_manager')),
 channel text not null check(channel in ('in_app','email')),
 enabled boolean not null default true,
 created_by_person_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(location_id,recipient_person_id,audience_role,channel)
);
create index mme_pos_financial_alert_subscriptions_route_idx
 on public.mme_pos_financial_alert_subscriptions(location_id,audience_role,enabled);

create table public.mme_pos_financial_alerts (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 currency char(3) check(currency is null or currency ~ '^[A-Z]{3}$'),
 alert_code text not null,
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','acknowledged','resolved','dismissed')),
 source_type text not null check(source_type in ('settlement_exception','financial_risk_run')),
 source_id uuid not null,
 dedupe_key text not null unique,
 title text not null check(length(btrim(title)) between 5 and 180),
 message text not null check(length(btrim(message)) between 10 and 2000),
 recommended_action text not null check(length(btrim(recommended_action)) between 8 and 1500),
 due_at timestamptz,
 escalation_level integer not null default 0 check(escalation_level between 0 and 3),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 acknowledged_by_person_id uuid,
 acknowledged_at timestamptz,
 resolved_by_person_id uuid,
 resolved_at timestamptz,
 check(status<>'acknowledged' or (acknowledged_by_person_id is not null and acknowledged_at is not null)),
 check(status not in ('resolved','dismissed') or (resolved_by_person_id is not null and resolved_at is not null))
);
create index mme_pos_financial_alert_queue_idx
 on public.mme_pos_financial_alerts(location_id,status,severity,created_at desc);
create index mme_pos_financial_alert_due_idx
 on public.mme_pos_financial_alerts(status,due_at) where status='open';

create table public.mme_pos_financial_alert_notifications (
 id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_pos_financial_alerts(id) on delete restrict,
 recipient_person_id uuid not null,
 channel text not null check(channel in ('in_app','email')),
 delivery_status text not null default 'pending' check(delivery_status in ('pending','queued','sent','failed','acknowledged')),
 delivery_attempts integer not null default 0 check(delivery_attempts between 0 and 20),
 last_error_code text,
 queued_at timestamptz,
 sent_at timestamptz,
 acknowledged_at timestamptz,
 created_at timestamptz not null default now(),
 unique(alert_id,recipient_person_id,channel)
);
create index mme_pos_financial_alert_notification_inbox_idx
 on public.mme_pos_financial_alert_notifications(recipient_person_id,delivery_status,created_at desc);

create table public.mme_pos_financial_alert_events (
 id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_pos_financial_alerts(id) on delete restrict,
 actor_person_id uuid,
 event_type text not null check(event_type in ('created','routed','acknowledged','escalated','resolved','dismissed','delivery_queued','delivery_failed')),
 detail_code text not null,
 notes text check(notes is null or length(notes)<=2000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_alert_events_idx
 on public.mme_pos_financial_alert_events(alert_id,occurred_at desc);

alter table public.mme_pos_financial_alert_subscriptions enable row level security;
alter table public.mme_pos_financial_alerts enable row level security;
alter table public.mme_pos_financial_alert_notifications enable row level security;
alter table public.mme_pos_financial_alert_events enable row level security;
revoke all on public.mme_pos_financial_alert_subscriptions,public.mme_pos_financial_alerts,
 public.mme_pos_financial_alert_notifications,public.mme_pos_financial_alert_events
 from public,anon,authenticated;
grant select,insert on public.mme_pos_financial_alert_subscriptions to service_role;
grant select,insert on public.mme_pos_financial_alerts,public.mme_pos_financial_alert_notifications,
 public.mme_pos_financial_alert_events to service_role;
revoke update,delete,truncate on public.mme_pos_financial_alerts,
 public.mme_pos_financial_alert_notifications,public.mme_pos_financial_alert_events from service_role;
grant update on public.mme_pos_financial_alert_subscriptions to service_role;

create or replace function public.mme_pos_manage_financial_alert_subscription(
 p_location_id uuid,p_actor_person_id uuid,p_recipient_person_id uuid,
 p_audience_role text,p_channel text,p_enabled boolean
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if p_location_id is null or p_actor_person_id is null or p_recipient_person_id is null
  or p_audience_role not in ('executive','finance','store_manager')
  or p_channel not in ('in_app','email') or p_enabled is null then
  raise exception 'Valid location, actor, recipient, audience, channel and enabled state are required' using errcode='22023';
 end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,p_location_id,'pos.settlement.exception.manage') then
  raise exception 'Financial alert subscription permission denied' using errcode='42501';
 end if;
 if p_audience_role='executive' and not public.mme_pos_authorize_settlement_action(p_actor_person_id,p_location_id,'pos.settlement.approve') then
  raise exception 'Executive alert routing requires settlement approval permission' using errcode='42501';
 end if;
 if not exists(select 1 from public.mme_person_identities i
  where i.person_id=p_recipient_person_id and i.lifecycle_status='active') then
  raise exception 'Active notification recipient required' using errcode='22023';
 end if;
 if not public.mme_pos_authorize_settlement_action(p_recipient_person_id,p_location_id,
  case p_audience_role when 'executive' then 'pos.settlement.approve'
   when 'finance' then 'pos.settlement.exception.manage' else 'pos.store.manage' end) then
  raise exception 'Recipient does not hold the permission required for this alert audience' using errcode='42501';
 end if;
 insert into public.mme_pos_financial_alert_subscriptions(
  location_id,recipient_person_id,audience_role,channel,enabled,created_by_person_id
 ) values(p_location_id,p_recipient_person_id,p_audience_role,p_channel,p_enabled,p_actor_person_id)
 on conflict(location_id,recipient_person_id,audience_role,channel)
 do update set enabled=excluded.enabled,updated_at=now()
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_generate_financial_alerts(
 p_location_id uuid,p_actor_person_id uuid
) returns integer language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_case record; v_run record; v_alert uuid; v_count integer:=0;
 v_code text; v_severity text; v_title text; v_message text; v_action text;
 v_role text; v_recipient record; v_inserted integer;
begin
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,p_location_id,'pos.settlement.exception.manage') then
  raise exception 'Financial alert generation permission denied' using errcode='42501';
 end if;

 for v_case in
  select c.id,c.currency,c.severity,c.exception_type,c.description,c.due_at,c.status,c.discrepancy_code
  from public.mme_pos_stripe_settlement_exception_cases c
  where c.location_id=p_location_id and c.status not in ('resolved','accepted_variance','false_positive')
   and (c.severity in ('high','critical') or c.due_at<=now())
  order by case c.severity when 'critical' then 4 when 'high' then 3 else 2 end desc,c.due_at
 loop
  v_code:=case when v_case.due_at<=now() then 'settlement_exception_overdue' else 'settlement_exception_'||v_case.severity end;
  v_severity:=case when v_case.severity='critical' then 'critical' when v_case.due_at<=now() then 'high' else v_case.severity end;
  v_title:=case when v_case.due_at<=now() then 'Overdue settlement exception' else 'Settlement exception requires review' end;
  v_message:=left(v_case.description,1900);
  v_action:='Open the linked exception case, verify processor and settlement evidence, assign an owner and document the resolution.';
  insert into public.mme_pos_financial_alerts(
   location_id,currency,alert_code,severity,source_type,source_id,dedupe_key,title,message,recommended_action,due_at
  ) values(p_location_id,v_case.currency,v_code,v_severity,'settlement_exception',v_case.id,
   'exception:'||v_case.id::text||':'||v_code,v_title,v_message,v_action,v_case.due_at)
  on conflict(dedupe_key) do nothing returning id into v_alert;
  if v_alert is null then continue; end if;
  insert into public.mme_pos_financial_alert_events(alert_id,actor_person_id,event_type,detail_code)
   values(v_alert,p_actor_person_id,'created',v_code);
  v_count:=v_count+1;
  v_role:=case when v_severity='critical' then 'executive' else 'store_manager' end;
  for v_recipient in
   select s.recipient_person_id,s.channel from public.mme_pos_financial_alert_subscriptions s
   join public.mme_person_identities i on i.person_id=s.recipient_person_id and i.lifecycle_status='active'
   where s.location_id=p_location_id and s.enabled and s.audience_role in (v_role,'finance')
    and public.mme_pos_authorize_settlement_action(s.recipient_person_id,p_location_id,
     case s.audience_role when 'executive' then 'pos.settlement.approve'
      when 'finance' then 'pos.settlement.exception.manage' else 'pos.store.manage' end)
  loop
   insert into public.mme_pos_financial_alert_notifications(alert_id,recipient_person_id,channel)
    values(v_alert,v_recipient.recipient_person_id,v_recipient.channel) on conflict do nothing;
  end loop;
  if v_severity='critical' then
   for v_recipient in
    select s.recipient_person_id,s.channel from public.mme_pos_financial_alert_subscriptions s
    join public.mme_person_identities i on i.person_id=s.recipient_person_id and i.lifecycle_status='active'
    where s.location_id=p_location_id and s.enabled and s.audience_role='executive'
   loop
    insert into public.mme_pos_financial_alert_notifications(alert_id,recipient_person_id,channel)
     values(v_alert,v_recipient.recipient_person_id,v_recipient.channel) on conflict do nothing;
   end loop;
  end if;
 end loop;

 for v_run in
  select distinct on(r.currency) r.id,r.currency,r.risk_score,r.risk_band,r.unresolved_exposure_minor,r.generated_at
  from public.mme_pos_stripe_financial_intelligence_runs r
  where r.location_id=p_location_id and r.risk_band in ('high','critical')
  order by r.currency,r.generated_at desc
 loop
  v_code:='financial_risk_'||v_run.risk_band;
  insert into public.mme_pos_financial_alerts(
   location_id,currency,alert_code,severity,source_type,source_id,dedupe_key,title,message,recommended_action
  ) values(p_location_id,v_run.currency,v_code,v_run.risk_band,'financial_risk_run',v_run.id,
   'risk:'||v_run.id::text||':'||v_code,'Elevated financial risk detected',
   'The latest explainable financial intelligence snapshot reports a '||v_run.risk_band||
    ' risk band and a score of '||v_run.risk_score||'/100. Unresolved exposure is shown in currency minor units and is not a confirmed loss.',
   'Review the source risk signals, linked exception cases and settlement timing. Record an accountable Finance decision; do not move funds based on this alert.')
  on conflict(dedupe_key) do nothing returning id into v_alert;
  if v_alert is null then continue; end if;
  insert into public.mme_pos_financial_alert_events(alert_id,actor_person_id,event_type,detail_code)
   values(v_alert,p_actor_person_id,'created',v_code);
  v_count:=v_count+1;
  for v_recipient in
   select s.recipient_person_id,s.channel from public.mme_pos_financial_alert_subscriptions s
   join public.mme_person_identities i on i.person_id=s.recipient_person_id and i.lifecycle_status='active'
   where s.location_id=p_location_id and s.enabled
    and s.audience_role in ('executive','finance')
    and public.mme_pos_authorize_settlement_action(s.recipient_person_id,p_location_id,
     case s.audience_role when 'executive' then 'pos.settlement.approve' else 'pos.settlement.exception.manage' end)
  loop
   insert into public.mme_pos_financial_alert_notifications(alert_id,recipient_person_id,channel)
    values(v_alert,v_recipient.recipient_person_id,v_recipient.channel) on conflict do nothing;
  end loop;
 end loop;
 return v_count;
end;
$$;

create or replace function public.mme_pos_acknowledge_financial_alert(
 p_alert_id uuid,p_actor_person_id uuid,p_notes text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_alert public.mme_pos_financial_alerts%rowtype; v_notification uuid;
begin
 select * into v_alert from public.mme_pos_financial_alerts where id=p_alert_id for update;
 if not found then raise exception 'Financial alert not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,v_alert.location_id,'pos.settlement.exception.manage') then
  raise exception 'Financial alert acknowledgment permission denied' using errcode='42501';
 end if;
 if v_alert.status in ('resolved','dismissed') then
  raise exception 'Closed financial alert cannot be acknowledged' using errcode='55000';
 end if;
 if p_notes is not null and length(p_notes)>2000 then
  raise exception 'Acknowledgment note is too long' using errcode='22023';
 end if;
 update public.mme_pos_financial_alerts set status='acknowledged',
  acknowledged_by_person_id=p_actor_person_id,acknowledged_at=now(),updated_at=now()
 where id=p_alert_id;
 update public.mme_pos_financial_alert_notifications set
  delivery_status='acknowledged',acknowledged_at=now()
 where alert_id=p_alert_id and recipient_person_id=p_actor_person_id
 returning id into v_notification;
 insert into public.mme_pos_financial_alert_events(alert_id,actor_person_id,event_type,detail_code,notes)
 values(p_alert_id,p_actor_person_id,'acknowledged','alert_acknowledged',p_notes);
 return p_alert_id;
end;
$$;

create or replace function public.mme_pos_escalate_financial_alerts(
 p_location_id uuid,p_actor_person_id uuid
) returns integer language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_count integer;
begin
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,p_location_id,'pos.settlement.exception.manage') then
  raise exception 'Financial alert escalation permission denied' using errcode='42501';
 end if;
 with escalated as (
  update public.mme_pos_financial_alerts set escalation_level=least(escalation_level+1,3),updated_at=now()
  where location_id=p_location_id and status='open' and due_at<=now() and escalation_level<3
  returning id,severity,escalation_level
 )
 insert into public.mme_pos_financial_alert_events(alert_id,actor_person_id,event_type,detail_code,metadata)
 select id,p_actor_person_id,'escalated','financial_alert_sla_breached',
  jsonb_build_object('severity',severity,'escalation_level',escalation_level) from escalated;
 get diagnostics v_count=row_count;
 return v_count;
end;
$$;

create or replace function public.mme_pos_queue_financial_alert_deliveries(
 p_location_id uuid,p_actor_person_id uuid,p_batch_size integer default 100
) returns integer language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_count integer;
begin
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,p_location_id,'pos.settlement.exception.manage') then
  raise exception 'Financial alert delivery queue permission denied' using errcode='42501';
 end if;
 if p_batch_size is null or p_batch_size<1 or p_batch_size>500 then
  raise exception 'Delivery batch size must be between 1 and 500' using errcode='22023';
 end if;
 with queued as (
  update public.mme_pos_financial_alert_notifications n set
   delivery_status='queued',queued_at=now(),delivery_attempts=delivery_attempts+1
  from public.mme_pos_financial_alerts a
  where n.alert_id=a.id and a.location_id=p_location_id
   and n.delivery_status='pending'
  and n.id in (select n2.id from public.mme_pos_financial_alert_notifications n2
   join public.mme_pos_financial_alerts a2 on a2.id=n2.alert_id
   where a2.location_id=p_location_id and n2.delivery_status='pending'
   order by n2.created_at for update skip locked limit p_batch_size)
  returning n.id,n.alert_id
 )
 insert into public.mme_pos_financial_alert_events(alert_id,actor_person_id,event_type,detail_code,metadata)
 select alert_id,p_actor_person_id,'delivery_queued','notification_delivery_queued',jsonb_build_object('notification_id',id)
 from queued;
 get diagnostics v_count=row_count;
 return v_count;
end;
$$;

create or replace view public.mme_pos_financial_alert_dashboard
with (security_invoker=true) as
select location_id,currency,severity,status,alert_code,count(*)::integer alert_count,
 count(*) filter(where due_at<=now() and status='open')::integer overdue_count,
 max(created_at) latest_alert_at
from public.mme_pos_financial_alerts
group by location_id,currency,severity,status,alert_code;

create or replace view public.mme_pos_financial_alert_inbox
with (security_invoker=true) as
select n.id notification_id,n.recipient_person_id,n.channel,n.delivery_status,n.created_at,
 a.id alert_id,a.location_id,a.currency,a.alert_code,a.severity,a.status,a.title,a.message,
 a.recommended_action,a.due_at,a.escalation_level
from public.mme_pos_financial_alert_notifications n
join public.mme_pos_financial_alerts a on a.id=n.alert_id;

revoke all on function public.mme_pos_manage_financial_alert_subscription(uuid,uuid,uuid,text,text,boolean) from public,anon,authenticated;
revoke all on function public.mme_pos_generate_financial_alerts(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_acknowledge_financial_alert(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_escalate_financial_alerts(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_queue_financial_alert_deliveries(uuid,uuid,integer) from public,anon,authenticated;
revoke all on public.mme_pos_financial_alert_dashboard,public.mme_pos_financial_alert_inbox from public,anon,authenticated;
grant execute on function public.mme_pos_manage_financial_alert_subscription(uuid,uuid,uuid,text,text,boolean) to service_role;
grant execute on function public.mme_pos_generate_financial_alerts(uuid,uuid) to service_role;
grant execute on function public.mme_pos_acknowledge_financial_alert(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_escalate_financial_alerts(uuid,uuid) to service_role;
grant execute on function public.mme_pos_queue_financial_alert_deliveries(uuid,uuid,integer) to service_role;
grant select on public.mme_pos_financial_alert_dashboard,public.mme_pos_financial_alert_inbox to service_role;

comment on table public.mme_pos_financial_alerts is
 'Deduplicated store-scoped financial alerts with accountable acknowledgment and SLA escalation.';
comment on table public.mme_pos_financial_alert_notifications is
 'In-app and email delivery outbox. Queued means ready for a separately deployed delivery worker, not delivered.';
comment on view public.mme_pos_financial_alert_inbox is
 'Recipient-scoped notification inbox joined to alert context; direct access remains service-role only.';

commit;
