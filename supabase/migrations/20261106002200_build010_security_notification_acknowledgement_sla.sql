begin;
alter table public.mme_security_incident_notification_queue
 add column if not exists acknowledgement_due_at timestamptz,
 add column if not exists acknowledgement_status text not null default 'pending',
 add column if not exists acknowledged_at timestamptz,
 add column if not exists acknowledged_by uuid,
 add column if not exists acknowledgement_note text,
 add column if not exists acknowledgement_escalated_at timestamptz,
 add column if not exists acknowledgement_escalation_level integer not null default 0;
do $$
begin
 if not exists(select 1 from pg_constraint where conname='mme_security_notification_ack_status_check') then
  alter table public.mme_security_incident_notification_queue
   add constraint mme_security_notification_ack_status_check
   check(acknowledgement_status in ('pending','acknowledged','escalated'));
 end if;
 if not exists(select 1 from pg_constraint where conname='mme_security_notification_ack_level_check') then
  alter table public.mme_security_incident_notification_queue
   add constraint mme_security_notification_ack_level_check
   check(acknowledgement_escalation_level between 0 and 5);
 end if;
end $$;
create index if not exists mme_security_notification_ack_due_idx
 on public.mme_security_incident_notification_queue(acknowledgement_due_at,acknowledgement_escalation_level)
 where acknowledgement_status='pending';

alter table public.mme_security_incident_response_events
 drop constraint if exists mme_security_incident_response_events_event_type_check;
alter table public.mme_security_incident_response_events
 add constraint mme_security_incident_response_events_event_type_check
 check(event_type in ('case_opened','owner_assigned','escalated','recovery_verified','closure_requested','closure_approved'));

create or replace function public.mme_security_incident_queue_notifications()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_case public.mme_security_incident_response_cases%rowtype;
begin
 select * into v_case from public.mme_security_incident_response_cases where case_id=new.case_id;
 if not found then return new; end if;
 insert into public.mme_security_incident_notification_queue(
  event_id,case_id,recipient_person_id,audience_role,channel,template_key,locale,payload,acknowledgement_due_at
 )
 select new.event_id,v_case.case_id,s.person_id,s.audience_role,s.channel,'security_incident_event',s.locale,
  jsonb_build_object(
   'eventType',new.event_type,'severity',v_case.severity,'caseId',v_case.case_id,
   'status',v_case.status,'slaDueAt',v_case.sla_due_at,'escalationLevel',v_case.escalation_level,
   'rationale',new.rationale,'occurredAt',new.created_at
  ),
  now()+case v_case.severity when 'critical' then interval '5 minutes' when 'warning' then interval '15 minutes' else interval '60 minutes' end
 from public.mme_security_incident_notification_subscriptions s
 join public.mme_person_identities i on i.person_id=s.person_id and i.lifecycle_status='active'
 where s.enabled
  and case v_case.severity
   when 'critical' then s.audience_role in ('ceo','cio','it_admin')
   when 'warning' then s.audience_role in ('cio','it_admin','manager')
   else s.audience_role in ('it_admin','manager')
  end
  and new.event_type in ('case_opened','escalated','recovery_verified','closure_requested','closure_approved','notification_ack_overdue')
 on conflict(event_id,recipient_person_id,channel) do nothing;
 return new;
end;
$$;

create or replace function public.mme_security_notification_acknowledge(
 p_notification_id uuid,p_actor_id uuid,p_actor_role text,p_note text default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare n public.mme_security_incident_notification_queue%rowtype;
begin
 if p_actor_id is null or p_actor_role not in ('ceo','cio','it_admin','manager') then
  raise exception 'notification_ack_forbidden';
 end if;
 select * into n from public.mme_security_incident_notification_queue
 where notification_id=p_notification_id for update;
 if not found then raise exception 'notification_not_found'; end if;
 if p_actor_role<>n.audience_role and p_actor_role not in ('ceo','cio','it_admin') then raise exception 'notification_recipient_role_required'; end if;
 if n.acknowledgement_status='acknowledged' then
  return jsonb_build_object('notificationId',n.notification_id,'acknowledged',true,'alreadyAcknowledged',true,'acknowledgedAt',n.acknowledged_at);
 end if;
 update public.mme_security_incident_notification_queue
 set acknowledgement_status='acknowledged',acknowledged_at=now(),acknowledged_by=p_actor_id,
     acknowledgement_note=left(nullif(trim(p_note),''),1000),updated_at=now()
 where notification_id=n.notification_id;
 return jsonb_build_object('notificationId',n.notification_id,'acknowledged',true,'acknowledgedAt',now());
end;
$$;

create or replace function public.mme_security_notification_escalate_unacknowledged(p_batch_size integer default 100)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare n record; v_count integer:=0; v_events integer:=0;
begin
 if p_batch_size is null or p_batch_size not between 1 and 500 then
  raise exception 'batch_size_must_be_1_to_500' using errcode='22023';
 end if;
 for n in
  select q.notification_id,q.event_id,q.case_id,q.acknowledgement_escalation_level
  from public.mme_security_incident_notification_queue q
  where q.acknowledgement_status='pending'
    and q.acknowledgement_due_at is not null
    and q.acknowledgement_due_at<now()
    and q.acknowledgement_escalation_level<5
    and (q.acknowledgement_escalated_at is null or q.acknowledgement_escalated_at<now()-interval '5 minutes')
  order by q.acknowledgement_due_at
  for update skip locked limit p_batch_size
 loop
  update public.mme_security_incident_notification_queue
   set acknowledgement_escalation_level=least(acknowledgement_escalation_level+1,5),
       acknowledgement_escalated_at=now(),updated_at=now()
   where notification_id=n.notification_id;
  insert into public.mme_security_incident_response_events(
   case_id,actor_id,actor_role,event_type,rationale,event_data,request_id
  ) values(
   n.case_id,'00000000-0000-0000-0000-000000000000'::uuid,'system',
   'notification_ack_overdue',
   'Notification acknowledgement deadline elapsed without recipient acknowledgement.',
   jsonb_build_object('notificationId',n.notification_id,'originalEventId',n.event_id,
     'previousEscalationLevel',n.acknowledgement_escalation_level,
     'newEscalationLevel',least(n.acknowledgement_escalation_level+1,5)),
   'notification-ack-sla-worker'
  );
  v_count:=v_count+1; v_events:=v_events+1;
 end loop;
 return jsonb_build_object('escalatedNotifications',v_count,'escalationEvents',v_events,'processedAt',now());
end;
$$;

create or replace view public.mme_security_notification_acknowledgement_health
with (security_invoker=true) as
select acknowledgement_status,status delivery_status,count(*)::integer notification_count,
 count(*) filter(where acknowledgement_due_at<now() and acknowledgement_status='pending')::integer overdue_count,
 count(*) filter(where acknowledged_at>=now()-interval '24 hours')::integer acknowledged_last_24h,
 max(updated_at) latest_update
from public.mme_security_incident_notification_queue
group by acknowledgement_status,status;

revoke all on function public.mme_security_incident_queue_notifications() from public,anon,authenticated;
revoke all on function public.mme_security_notification_acknowledge(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_security_notification_escalate_unacknowledged(integer) from public,anon,authenticated;
revoke all on public.mme_security_notification_acknowledgement_health from public,anon,authenticated;
grant execute on function public.mme_security_notification_acknowledge(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_security_notification_escalate_unacknowledged(integer) to service_role;
grant select on public.mme_security_notification_acknowledgement_health to service_role;
comment on column public.mme_security_incident_notification_queue.acknowledgement_due_at is
 'Acknowledgement target: critical 5 minutes, warning 15 minutes, informational 60 minutes.';
commit;