begin;

create table if not exists public.mme_security_incident_notification_subscriptions (
 subscription_id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 audience_role text not null check(audience_role in ('ceo','cio','it_admin','manager')),
 channel text not null check(channel in ('email','sms','push','in_app')),
 enabled boolean not null default true,
 locale text not null default 'en-US',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(person_id,audience_role,channel)
);
create index if not exists mme_security_incident_notification_subscriptions_route_idx
 on public.mme_security_incident_notification_subscriptions(audience_role,channel)
 where enabled;

create table if not exists public.mme_security_incident_notification_queue (
 notification_id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.mme_security_incident_response_events(event_id) on delete restrict,
 case_id uuid not null references public.mme_security_incident_response_cases(case_id) on delete restrict,
 recipient_person_id uuid not null,
 audience_role text not null,
 channel text not null check(channel in ('email','sms','push','in_app')),
 template_key text not null default 'security_incident_event',
 locale text not null default 'en-US',
 payload jsonb not null default '{}'::jsonb check(jsonb_typeof(payload)='object'),
 delivery_job_id uuid references public.mme_notification_delivery_jobs(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','enqueued','suppressed','blocked_template','failed')),
 last_error_code text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(event_id,recipient_person_id,channel)
);
create index if not exists mme_security_incident_notification_queue_claim_idx
 on public.mme_security_incident_notification_queue(status,created_at)
 where status in ('pending','blocked_template');

alter table public.mme_security_incident_notification_subscriptions enable row level security;
alter table public.mme_security_incident_notification_queue enable row level security;
revoke all on public.mme_security_incident_notification_subscriptions,
 public.mme_security_incident_notification_queue from public,anon,authenticated;
grant select,insert,update on public.mme_security_incident_notification_subscriptions to service_role;
grant select,insert,update on public.mme_security_incident_notification_queue to service_role;
revoke delete,truncate on public.mme_security_incident_notification_subscriptions,
 public.mme_security_incident_notification_queue from public,anon,authenticated;

create or replace function public.mme_security_incident_queue_notifications()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_case public.mme_security_incident_response_cases%rowtype;
begin
 select * into v_case from public.mme_security_incident_response_cases where case_id=new.case_id;
 if not found then return new; end if;
 insert into public.mme_security_incident_notification_queue(
  event_id,case_id,recipient_person_id,audience_role,channel,template_key,locale,payload
 )
 select new.event_id,v_case.case_id,s.person_id,s.audience_role,s.channel,'security_incident_event',s.locale,
  jsonb_build_object(
   'eventType',new.event_type,'severity',v_case.severity,'caseId',v_case.case_id,
   'status',v_case.status,'slaDueAt',v_case.sla_due_at,'escalationLevel',v_case.escalation_level,
   'rationale',new.rationale,'occurredAt',new.created_at
  )
 from public.mme_security_incident_notification_subscriptions s
 join public.mme_person_identities i on i.person_id=s.person_id and i.lifecycle_status='active'
 where s.enabled
  and case v_case.severity
   when 'critical' then s.audience_role in ('ceo','cio','it_admin')
   when 'warning' then s.audience_role in ('cio','it_admin','manager')
   else s.audience_role in ('it_admin','manager')
  end
  and new.event_type in ('case_opened','escalated','recovery_verified','closure_requested','closure_approved')
 on conflict(event_id,recipient_person_id,channel) do nothing;
 return new;
end;
$$;
drop trigger if exists mme_security_incident_notification_event_trigger on public.mme_security_incident_response_events;
create trigger mme_security_incident_notification_event_trigger
 after insert on public.mme_security_incident_response_events
 for each row execute function public.mme_security_incident_queue_notifications();

create or replace function public.mme_security_incident_dispatch_notifications(p_batch_size integer default 100)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare r record; v_job uuid; v_enqueued integer:=0; v_suppressed integer:=0; v_blocked integer:=0;
begin
 if p_batch_size is null or p_batch_size not between 1 and 500 then
  raise exception 'batch_size_must_be_1_to_500' using errcode='22023';
 end if;
 for r in
  select q.* from public.mme_security_incident_notification_queue q
  where q.status in ('pending','blocked_template')
  order by q.created_at
  for update skip locked limit p_batch_size
 loop
  if exists(select 1 from public.mme_notification_channel_preferences p
    where p.person_id=r.recipient_person_id and p.channel=r.channel and not p.enabled) then
   update public.mme_security_incident_notification_queue
    set status='suppressed',last_error_code='recipient_channel_disabled',updated_at=now()
    where notification_id=r.notification_id;
   v_suppressed:=v_suppressed+1;
   continue;
  end if;
  begin
   v_job:=public.mme_notification_enqueue_delivery(
    null,r.recipient_person_id,r.channel,r.template_key,r.locale,r.payload,
    'security-incident:'||r.notification_id::text
   );
   update public.mme_security_incident_notification_queue
    set status='enqueued',delivery_job_id=v_job,last_error_code=null,updated_at=now()
    where notification_id=r.notification_id;
   v_enqueued:=v_enqueued+1;
  exception when others then
   update public.mme_security_incident_notification_queue
    set status='blocked_template',last_error_code=left(sqlstate||':'||sqlerrm,120),updated_at=now()
    where notification_id=r.notification_id;
   v_blocked:=v_blocked+1;
  end;
 end loop;
 return jsonb_build_object('enqueued',v_enqueued,'suppressed',v_suppressed,'blockedTemplate',v_blocked,'processedAt',now());
end;
$$;

create or replace view public.mme_security_incident_notification_health
with (security_invoker=true) as
select channel,status,count(*)::integer notification_count,
 count(*) filter(where created_at>=now()-interval '24 hours')::integer last_24h,
 max(updated_at) latest_update
from public.mme_security_incident_notification_queue
group by channel,status;

revoke all on function public.mme_security_incident_queue_notifications() from public,anon,authenticated;
revoke all on function public.mme_security_incident_dispatch_notifications(integer) from public,anon,authenticated;
revoke all on public.mme_security_incident_notification_health from public,anon,authenticated;
grant execute on function public.mme_security_incident_dispatch_notifications(integer) to service_role;
grant select on public.mme_security_incident_notification_health to service_role;

comment on table public.mme_security_incident_notification_subscriptions is
 'Role-routed security incident notification subscriptions; provider credentials are never stored here.';
comment on table public.mme_security_incident_notification_queue is
 'Security event fan-out queue connected to the shared Build 009 notification delivery outbox.';
commit;