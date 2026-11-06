-- Build 009.51 — authoritative commerce event to customer notification automation.
-- Domain services publish events through the service-role RPC; no polling or provider calls occur in SQL.
begin;

create table public.mme_customer_order_notification_events (
 id uuid primary key default gen_random_uuid(),
 source_system text not null check(source_system ~ '^[a-z][a-z0-9_]{1,39}$'),
 source_event_id text not null check(length(source_event_id) between 1 and 200),
 event_type text not null check(event_type in (
  'order_placed','payment_succeeded','payment_failed','shipment_label_created',
  'shipment_in_transit','shipment_delivered','pickup_ready','pickup_reminder_due',
  'return_authorized','refund_initiated','refund_completed','refund_failed',
  'warranty_expiry_reminder_due','subscription_renewal_reminder_due'
 )),
 order_reference text not null check(length(order_reference) between 1 and 120),
 person_id uuid not null,
 location_id uuid,
 occurred_at timestamptz not null,
 received_at timestamptz not null default now(),
 event_payload jsonb not null default '{}'::jsonb check(jsonb_typeof(event_payload)='object'),
 processing_status text not null default 'received' check(processing_status in ('received','processing','completed','partially_dispatched','suppressed','failed')),
 processed_at timestamptz,
 last_error_code text,
 unique(source_system,source_event_id)
);
create index mme_customer_order_notification_events_queue_idx
 on public.mme_customer_order_notification_events(received_at,id)
 where processing_status in ('received','failed');
create index mme_customer_order_notification_events_order_idx
 on public.mme_customer_order_notification_events(order_reference,occurred_at desc);

create table public.mme_customer_order_notification_rules (
 event_type text not null,
 channel text not null check(channel in ('email','sms','push','in_app')),
 template_key text not null,
 locale text not null default 'en-US',
 enabled boolean not null default true,
 priority smallint not null default 100 check(priority between 1 and 1000),
 primary key(event_type,channel)
);
create index mme_customer_order_notification_rules_active_idx
 on public.mme_customer_order_notification_rules(event_type,priority) where enabled;

create table public.mme_customer_order_notification_dispatches (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.mme_customer_order_notification_events(id) on delete restrict,
 person_id uuid not null,
 channel text not null check(channel in ('email','sms','push','in_app')),
 delivery_job_id uuid references public.mme_notification_delivery_jobs(id) on delete restrict,
 dispatch_status text not null check(dispatch_status in ('queued','suppressed_preference','suppressed_inactive','failed')),
 suppression_reason text,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 unique(event_id,person_id,channel)
);
create index mme_customer_order_notification_dispatch_event_idx
 on public.mme_customer_order_notification_dispatches(event_id,dispatch_status);

alter table public.mme_customer_order_notification_events enable row level security;
alter table public.mme_customer_order_notification_rules enable row level security;
alter table public.mme_customer_order_notification_dispatches enable row level security;
revoke all on public.mme_customer_order_notification_events,public.mme_customer_order_notification_rules,
 public.mme_customer_order_notification_dispatches from public,anon,authenticated;
grant select,insert,update on public.mme_customer_order_notification_events to service_role;
grant select,insert,update on public.mme_customer_order_notification_rules to service_role;
grant select,insert,update on public.mme_customer_order_notification_dispatches to service_role;
revoke delete,truncate on public.mme_customer_order_notification_events,
 public.mme_customer_order_notification_rules,public.mme_customer_order_notification_dispatches
 from public,anon,authenticated;

create or replace function public.mme_customer_order_notification_ingest_event(
 p_source_system text,p_source_event_id text,p_event_type text,p_order_reference text,
 p_person_id uuid,p_location_id uuid,p_occurred_at timestamptz,p_event_payload jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if p_source_system is null or p_source_event_id is null or p_event_type is null
  or p_order_reference is null or p_person_id is null or p_occurred_at is null
  or p_event_payload is null or jsonb_typeof(p_event_payload)<>'object'
  or p_event_type not in ('order_placed','payment_succeeded','payment_failed','shipment_label_created',
   'shipment_in_transit','shipment_delivered','pickup_ready','pickup_reminder_due',
   'return_authorized','refund_initiated','refund_completed','refund_failed',
   'warranty_expiry_reminder_due','subscription_renewal_reminder_due') then
  raise exception 'Invalid commerce notification event' using errcode='22023';
 end if;
 if not exists(select 1 from public.mme_person_identities i
  where i.person_id=p_person_id and i.lifecycle_status='active') then
  raise exception 'Active customer identity required' using errcode='22023';
 end if;
 insert into public.mme_customer_order_notification_events(
  source_system,source_event_id,event_type,order_reference,person_id,location_id,
  occurred_at,event_payload
 ) values(p_source_system,p_source_event_id,p_event_type,p_order_reference,p_person_id,
  p_location_id,p_occurred_at,p_event_payload)
 on conflict(source_system,source_event_id) do update
 set source_event_id=excluded.source_event_id
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_customer_order_notification_dispatch_event(
 p_event_id uuid,p_batch_size integer default 4
) returns integer language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_event public.mme_customer_order_notification_events%rowtype;
 v_rule record; v_count integer:=0; v_status text; v_job uuid; v_key text;
begin
 if p_event_id is null or p_batch_size is null or p_batch_size not between 1 and 4 then
  raise exception 'Valid event and batch size (1-4) required' using errcode='22023';
 end if;
 select * into v_event from public.mme_customer_order_notification_events
 where id=p_event_id for update;
 if not found then raise exception 'Commerce event not found' using errcode='P0002'; end if;
 if v_event.processing_status='completed' then return 0; end if;
 if v_event.processing_status not in ('received','failed','partially_dispatched') then
  raise exception 'Commerce event is already being processed' using errcode='55000';
 end if;
 update public.mme_customer_order_notification_events set processing_status='processing',
  last_error_code=null where id=p_event_id;
 for v_rule in
  select r.channel,r.template_key,r.locale from public.mme_customer_order_notification_rules r
  where r.event_type=v_event.event_type and r.enabled
  order by r.priority,r.channel limit p_batch_size
 loop
  v_key:='commerce-event:'||v_event.id::text||':person:'||v_event.person_id::text||':channel:'||v_rule.channel;
  if not exists(select 1 from public.mme_person_identities i
   where i.person_id=v_event.person_id and i.lifecycle_status='active') then
   v_status:='suppressed_inactive';
  elsif exists(select 1 from public.mme_notification_channel_preferences p
   where p.person_id=v_event.person_id and p.channel=v_rule.channel and not p.enabled) then
   v_status:='suppressed_preference';
  else
   v_status:='queued';
  end if;
  if v_status='queued' then
   v_job:=public.mme_notification_enqueue_delivery(null,v_event.person_id,v_rule.channel,
    v_rule.template_key,v_rule.locale,
    jsonb_build_object('event_type',v_event.event_type,'order_reference',v_event.order_reference,
     'occurred_at',v_event.occurred_at,'event_data',v_event.event_payload),
    v_key);
  else v_job:=null; end if;
  insert into public.mme_customer_order_notification_dispatches(
   event_id,person_id,channel,delivery_job_id,dispatch_status,suppression_reason,idempotency_key
  ) values(p_event_id,v_event.person_id,v_rule.channel,v_job,v_status,
   case when v_status='suppressed_preference' then 'channel_disabled'
    when v_status='suppressed_inactive' then 'identity_inactive' else null end,v_key)
  on conflict(event_id,person_id,channel) do nothing;
  if found then v_count:=v_count+1; end if;
 end loop;
 update public.mme_customer_order_notification_events e set
  processing_status=case
   when not exists(select 1 from public.mme_customer_order_notification_rules r
    where r.event_type=e.event_type and r.enabled) then 'suppressed'
   when not exists(select 1 from public.mme_customer_order_notification_rules r
    where r.event_type=e.event_type and r.enabled
     and not exists(select 1 from public.mme_customer_order_notification_dispatches d
      where d.event_id=e.id and d.channel=r.channel))
   then case when exists(select 1 from public.mme_customer_order_notification_dispatches d
     where d.event_id=e.id and d.dispatch_status='queued') then 'completed' else 'suppressed' end
   else 'partially_dispatched' end,
  processed_at=case when not exists(select 1 from public.mme_customer_order_notification_rules r
    where r.event_type=e.event_type and r.enabled
     and not exists(select 1 from public.mme_customer_order_notification_dispatches d
      where d.event_id=e.id and d.channel=r.channel)) then now() else null end
 where e.id=p_event_id;
 return v_count;
exception when others then
 update public.mme_customer_order_notification_events set processing_status='failed',
  last_error_code=left(sqlstate||':'||sqlerrm,160) where id=p_event_id;
 raise;
end;
$$;

create or replace view public.mme_customer_order_notification_health
with (security_invoker=true) as
select e.event_type,e.processing_status,count(*)::integer event_count,
 count(d.id)::integer dispatch_count,
 count(d.id) filter(where d.dispatch_status='queued')::integer queued_count,
 count(d.id) filter(where d.dispatch_status like 'suppressed%')::integer suppressed_count,
 max(e.received_at) latest_received_at
from public.mme_customer_order_notification_events e
left join public.mme_customer_order_notification_dispatches d on d.event_id=e.id
group by e.event_type,e.processing_status;

revoke all on function public.mme_customer_order_notification_ingest_event(text,text,text,text,uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function public.mme_customer_order_notification_dispatch_event(uuid,integer) from public,anon,authenticated;
revoke all on public.mme_customer_order_notification_health from public,anon,authenticated;
grant execute on function public.mme_customer_order_notification_ingest_event(text,text,text,text,uuid,uuid,timestamptz,jsonb) to service_role;
grant execute on function public.mme_customer_order_notification_dispatch_event(uuid,integer) to service_role;
grant select on public.mme_customer_order_notification_health to service_role;

comment on table public.mme_customer_order_notification_events is
 'Idempotent inbox of authoritative order, payment, fulfillment, return, refund and lifecycle events.';
comment on table public.mme_customer_order_notification_dispatches is
 'Per-event channel dispatch outcome linked to the Build 009.49 delivery outbox.';
comment on view public.mme_customer_order_notification_health is
 'Operational event and dispatch health without exposing customer contact details.';

commit;
