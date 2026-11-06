begin;
create table if not exists public.mme_service_sla_policies(
 policy_id uuid primary key default gen_random_uuid(),
 service_type text not null check(service_type in('warranty_claim','repair','rma')),
 priority text not null default 'standard' check(priority in('low','standard','high','critical')),
 response_minutes integer not null check(response_minutes>0),
 resolution_minutes integer not null check(resolution_minutes>=response_minutes),
 escalation_minutes integer not null check(escalation_minutes>0),
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 unique(service_type,priority)
);
insert into public.mme_service_sla_policies(service_type,priority,response_minutes,resolution_minutes,escalation_minutes)
values ('warranty_claim','standard',1440,10080,2880),('repair','standard',1440,20160,2880),('rma','standard',1440,10080,2880)
on conflict(service_type,priority) do nothing;

create table if not exists public.mme_service_notification_outbox(
 notification_id uuid primary key default gen_random_uuid(),
 event_key text not null unique,
 event_type text not null check(event_type in('warranty_expiring_90','warranty_expiring_60','warranty_expiring_30','warranty_expiring_7','repair_sla_overdue','claim_sla_overdue','rma_sla_overdue')),
 entity_type text not null,
 entity_id uuid not null,
 customer_reference text,
 recipient_reference text,
 channel text not null default 'pending_provider' check(channel in('email','sms','in_app','pending_provider')),
 template_key text not null,
 payload jsonb not null default '{}'::jsonb,
 delivery_status text not null default 'queued' check(delivery_status in('queued','leased','sent','failed','cancelled','suppressed')),
 attempts integer not null default 0 check(attempts>=0),
 available_at timestamptz not null default now(),
 leased_at timestamptz,
 lease_owner text,
 delivered_at timestamptz,
 last_error text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists mme_service_outbox_ready_idx on public.mme_service_notification_outbox(delivery_status,available_at,created_at);
create index if not exists mme_service_outbox_entity_idx on public.mme_service_notification_outbox(entity_type,entity_id,created_at desc);

create table if not exists public.mme_service_automation_runs(
 run_id uuid primary key default gen_random_uuid(),
 worker_name text not null,
 run_status text not null check(run_status in('completed','failed')),
 warranties_queued integer not null default 0,
 sla_escalations_queued integer not null default 0,
 started_at timestamptz not null default now(),
 completed_at timestamptz not null default now(),
 detail jsonb not null default '{}'::jsonb
);
create index if not exists mme_service_automation_runs_recent_idx on public.mme_service_automation_runs(started_at desc);

create or replace function public.mme_service_automation_dispatch(p_limit integer default 500,p_actor uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_warranty integer:=0; v_sla integer:=0; v_run uuid:=gen_random_uuid(); v_limit integer:=greatest(1,least(coalesce(p_limit,500),2000));
begin
 with due as (
  select w.warranty_id,w.customer_reference,w.expires_on,days.day_count
  from public.mme_device_warranties w
  cross join (values(90),(60),(30),(7)) as days(day_count)
  where w.warranty_status='active'
    and w.expires_on=current_date+days.day_count
 ), inserted as (
  insert into public.mme_service_notification_outbox(event_key,event_type,entity_type,entity_id,customer_reference,template_key,payload)
  select 'warranty-expiry:'||warranty_id::text||':'||day_count::text,
    case day_count when 90 then 'warranty_expiring_90' when 60 then 'warranty_expiring_60' when 30 then 'warranty_expiring_30' else 'warranty_expiring_7' end,
    'warranty',warranty_id,customer_reference,'warranty-expiry-reminder',
    jsonb_build_object('warranty_id',warranty_id,'expires_on',expires_on,'days_remaining',day_count)
  from due on conflict(event_key) do nothing returning notification_id
 ) select count(*) into v_warranty from inserted;

 with candidates as (
  select 'claim'::text entity_type,c.claim_id entity_id,c.customer_reference,c.submitted_at created_at,
   coalesce(p.response_minutes,1440) response_minutes,coalesce(p.escalation_minutes,2880) escalation_minutes,
   c.claim_status status,'claim_sla_overdue'::text event_type
  from public.mme_warranty_claims c left join public.mme_service_sla_policies p on p.service_type='warranty_claim' and p.priority='standard' and p.enabled
  where c.claim_status in('submitted','under_review') and c.submitted_at+make_interval(mins=>coalesce(p.response_minutes,1440))<now()
  union all
  select 'repair',r.repair_ticket_id,r.customer_reference,r.opened_at,
   coalesce(p.response_minutes,1440),coalesce(p.escalation_minutes,2880),r.repair_status,'repair_sla_overdue'
  from public.mme_repair_tickets r left join public.mme_service_sla_policies p on p.service_type='repair' and p.priority='standard' and p.enabled
  where r.repair_status not in('completed','cancelled') and r.opened_at+make_interval(mins=>coalesce(p.response_minutes,1440))<now()
  union all
  select 'rma',a.rma_id,a.customer_reference,a.requested_at,
   coalesce(p.response_minutes,1440),coalesce(p.escalation_minutes,2880),a.rma_status,'rma_sla_overdue'
  from public.mme_return_authorizations a left join public.mme_service_sla_policies p on p.service_type='rma' and p.priority='standard' and p.enabled
  where a.rma_status not in('completed','rejected','cancelled') and a.requested_at+make_interval(mins=>coalesce(p.response_minutes,1440))<now()
 ), inserted as (
  insert into public.mme_service_notification_outbox(event_key,event_type,entity_type,entity_id,customer_reference,template_key,payload)
  select 'sla-overdue:'||entity_type||':'||entity_id::text||':'||to_char(date_trunc('day',now()),'YYYYMMDD'),
   event_type,entity_type,entity_id,customer_reference,'service-sla-escalation',
   jsonb_build_object('status',status,'opened_at',created_at,'response_minutes',response_minutes,'escalation_minutes',escalation_minutes)
  from candidates
  where created_at+make_interval(mins=>escalation_minutes)<now()
  on conflict(event_key) do nothing returning notification_id
 ) select count(*) into v_sla from inserted;

 insert into public.mme_service_automation_runs(run_id,worker_name,run_status,warranties_queued,sla_escalations_queued,detail)
 values(v_run,'warranty-service-automation','completed',v_warranty,v_sla,
 jsonb_build_object('limit',v_limit,'delivery','queued_only','provider_configured',false));
 return jsonb_build_object('run_id',v_run,'warranties_queued',v_warranty,'sla_escalations_queued',v_sla,'delivery_status','queued_only');
end $$;

do $$declare t text;begin
 foreach t in array array['mme_service_sla_policies','mme_service_notification_outbox','mme_service_automation_runs'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
revoke all on function public.mme_service_automation_dispatch(integer,uuid) from public,anon,authenticated;
grant execute on function public.mme_service_automation_dispatch(integer,uuid) to service_role;
commit;