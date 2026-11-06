-- Build 009.49 — provider-neutral notification delivery infrastructure.
-- Provider credentials remain in runtime secret storage; this migration stores secret references only.
begin;

create table public.mme_notification_channel_preferences (
 person_id uuid not null,
 channel text not null check(channel in ('email','sms','push','in_app')),
 enabled boolean not null default true,
 quiet_hours_start time,
 quiet_hours_end time,
 timezone_name text not null default 'UTC',
 updated_at timestamptz not null default now(),
 primary key(person_id,channel),
 check((quiet_hours_start is null)=(quiet_hours_end is null))
);
create table public.mme_notification_provider_routes (
 id uuid primary key default gen_random_uuid(),
 channel text not null check(channel in ('email','sms','push')),
 provider_code text not null check(provider_code ~ '^[a-z][a-z0-9_]{1,39}$'),
 secret_reference text not null check(secret_reference ~ '^[A-Z][A-Z0-9_]{2,99}$'),
 priority smallint not null default 100 check(priority between 1 and 1000),
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 unique(channel,provider_code)
);
create index mme_notification_provider_routes_active_idx
 on public.mme_notification_provider_routes(channel,priority) where enabled;

create table public.mme_notification_templates (
 id uuid primary key default gen_random_uuid(),
 template_key text not null,
 channel text not null check(channel in ('email','sms','push','in_app')),
 locale text not null default 'en-US',
 version integer not null check(version>0),
 subject_template text,
 body_template text not null check(length(btrim(body_template)) between 1 and 10000),
 active boolean not null default false,
 created_at timestamptz not null default now(),
 unique(template_key,channel,locale,version)
);
create unique index mme_notification_templates_one_active_idx
 on public.mme_notification_templates(template_key,channel,locale) where active;

create table public.mme_notification_delivery_jobs (
 id uuid primary key default gen_random_uuid(),
 alert_notification_id uuid references public.mme_pos_financial_alert_notifications(id) on delete restrict,
 recipient_person_id uuid not null,
 channel text not null check(channel in ('email','sms','push','in_app')),
 template_key text not null,
 template_version integer not null,
 payload jsonb not null default '{}'::jsonb check(jsonb_typeof(payload)='object'),
 idempotency_key text not null unique,
 status text not null default 'pending' check(status in ('pending','processing','sent','failed','dead_letter','suppressed')),
 attempts integer not null default 0 check(attempts between 0 and 12),
 max_attempts integer not null default 8 check(max_attempts between 1 and 12),
 next_attempt_at timestamptz not null default now(),
 claimed_at timestamptz,
 provider_code text,
 provider_message_id text,
 last_error_code text,
 sent_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(attempts<=max_attempts)
);
create index mme_notification_delivery_jobs_claim_idx
 on public.mme_notification_delivery_jobs(channel,next_attempt_at,created_at)
 where status in ('pending','failed');
create index mme_notification_delivery_jobs_recipient_idx
 on public.mme_notification_delivery_jobs(recipient_person_id,created_at desc);

create table public.mme_notification_delivery_attempts (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.mme_notification_delivery_jobs(id) on delete restrict,
 attempt_number integer not null,
 provider_code text not null,
 outcome text not null check(outcome in ('sent','retryable_failure','permanent_failure','suppressed')),
 provider_message_id text,
 error_code text,
 latency_ms integer check(latency_ms is null or latency_ms>=0),
 occurred_at timestamptz not null default now(),
 unique(job_id,attempt_number)
);
create index mme_notification_delivery_attempts_job_idx
 on public.mme_notification_delivery_attempts(job_id,occurred_at desc);

alter table public.mme_notification_channel_preferences enable row level security;
alter table public.mme_notification_provider_routes enable row level security;
alter table public.mme_notification_templates enable row level security;
alter table public.mme_notification_delivery_jobs enable row level security;
alter table public.mme_notification_delivery_attempts enable row level security;
revoke all on public.mme_notification_channel_preferences,public.mme_notification_provider_routes,
 public.mme_notification_templates,public.mme_notification_delivery_jobs,
 public.mme_notification_delivery_attempts from public,anon,authenticated;
grant select,insert,update on public.mme_notification_channel_preferences to service_role;
grant select,insert,update on public.mme_notification_provider_routes,
 public.mme_notification_templates to service_role;
grant select,insert,update on public.mme_notification_delivery_jobs to service_role;
grant select,insert on public.mme_notification_delivery_attempts to service_role;
revoke delete,truncate on all tables in schema public from public,anon,authenticated;

create or replace function public.mme_notification_enqueue_delivery(
 p_alert_notification_id uuid,p_recipient_person_id uuid,p_channel text,
 p_template_key text,p_locale text,p_payload jsonb,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_template public.mme_notification_templates%rowtype; v_id uuid;
begin
 if p_recipient_person_id is null or p_channel not in ('email','sms','push','in_app')
  or p_template_key is null or p_locale is null or p_idempotency_key is null
  or length(p_idempotency_key) not between 8 and 200
  or p_payload is null or jsonb_typeof(p_payload)<>'object' then
  raise exception 'Valid recipient, channel, template, payload and idempotency key are required' using errcode='22023';
 end if;
 if not exists(select 1 from public.mme_person_identities i
  where i.person_id=p_recipient_person_id and i.lifecycle_status='active') then
  raise exception 'Active recipient identity required' using errcode='22023';
 end if;
 select * into v_template from public.mme_notification_templates t
  where t.template_key=p_template_key and t.channel=p_channel and t.locale=p_locale and t.active
  order by t.version desc limit 1;
 if not found then raise exception 'No active template for requested channel and locale' using errcode='P0002'; end if;
 insert into public.mme_notification_delivery_jobs(
  alert_notification_id,recipient_person_id,channel,template_key,template_version,payload,idempotency_key
 ) values(p_alert_notification_id,p_recipient_person_id,p_channel,p_template_key,v_template.version,p_payload,p_idempotency_key)
 on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_notification_set_channel_preference(
 p_person_id uuid,p_actor_person_id uuid,p_channel text,p_enabled boolean,
 p_quiet_start time default null,p_quiet_end time default null,p_timezone text default 'UTC'
) returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_person_id is null or p_actor_person_id is null or p_channel not in ('email','sms','push','in_app')
  or p_enabled is null or p_timezone is null or length(p_timezone)>80
  or ((p_quiet_start is null)<>(p_quiet_end is null)) then
  raise exception 'Invalid notification preference' using errcode='22023';
 end if;
 if p_actor_person_id<>p_person_id and not exists(
  select 1 from public.mme_pos_financial_alert_subscriptions s
  where s.recipient_person_id=p_actor_person_id and s.enabled
   and public.mme_pos_authorize_settlement_action(p_actor_person_id,s.location_id,'pos.settlement.exception.manage')
 ) then raise exception 'Notification preference management denied' using errcode='42501'; end if;
 insert into public.mme_notification_channel_preferences(person_id,channel,enabled,quiet_hours_start,quiet_hours_end,timezone_name)
 values(p_person_id,p_channel,p_enabled,p_quiet_start,p_quiet_end,p_timezone)
 on conflict(person_id,channel) do update set enabled=excluded.enabled,
  quiet_hours_start=excluded.quiet_hours_start,quiet_hours_end=excluded.quiet_hours_end,
  timezone_name=excluded.timezone_name,updated_at=now();
end;
$$;

create or replace function public.mme_notification_claim_delivery_jobs(
 p_channel text,p_batch_size integer default 50
) returns setof public.mme_notification_delivery_jobs
language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_channel not in ('email','sms','push','in_app') or p_batch_size not between 1 and 200 then
  raise exception 'Valid channel and batch size (1-200) required' using errcode='22023';
 end if;
 return query
 with candidates as (
  select j.id from public.mme_notification_delivery_jobs j
  where j.channel=p_channel and j.status in ('pending','failed')
   and j.next_attempt_at<=now() and j.attempts<j.max_attempts
  order by j.next_attempt_at,j.created_at
  for update skip locked limit p_batch_size
 ), claimed as (
  update public.mme_notification_delivery_jobs j set status='processing',
   attempts=j.attempts+1,claimed_at=now(),updated_at=now()
  from candidates c where j.id=c.id returning j.*
 )
 select * from claimed;
end;
$$;

create or replace function public.mme_notification_complete_delivery(
 p_job_id uuid,p_provider_code text,p_outcome text,p_provider_message_id text default null,
 p_error_code text default null,p_latency_ms integer default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_job public.mme_notification_delivery_jobs%rowtype; v_attempt integer;
begin
 select * into v_job from public.mme_notification_delivery_jobs where id=p_job_id for update;
 if not found then raise exception 'Delivery job not found' using errcode='P0002'; end if;
 if v_job.status<>'processing' then raise exception 'Delivery job is not claimed' using errcode='55000'; end if;
 if p_provider_code is null or p_outcome not in ('sent','retryable_failure','permanent_failure','suppressed')
  or (p_latency_ms is not null and p_latency_ms<0) then
  raise exception 'Invalid provider result' using errcode='22023';
 end if;
 insert into public.mme_notification_delivery_attempts(job_id,attempt_number,provider_code,outcome,
  provider_message_id,error_code,latency_ms)
 values(v_job.id,v_job.attempts,p_provider_code,p_outcome,p_provider_message_id,left(p_error_code,120),p_latency_ms);
 update public.mme_notification_delivery_jobs set
  status=case p_outcome when 'sent' then 'sent' when 'suppressed' then 'suppressed'
   when 'permanent_failure' then 'dead_letter'
   when 'retryable_failure' then case when v_job.attempts>=v_job.max_attempts then 'dead_letter' else 'failed' end end,
  provider_code=p_provider_code,provider_message_id=p_provider_message_id,
  last_error_code=left(p_error_code,120),
  sent_at=case when p_outcome='sent' then now() else sent_at end,
  next_attempt_at=case when p_outcome='retryable_failure' and v_job.attempts<v_job.max_attempts
   then now()+make_interval(secs=>least(21600,30*power(2,least(v_job.attempts-1,9))::integer)) else next_attempt_at end,
  updated_at=now()
 where id=p_job_id;
 if v_job.alert_notification_id is not null and p_outcome='sent' then
  update public.mme_pos_financial_alert_notifications set delivery_status='sent',sent_at=now()
   where id=v_job.alert_notification_id and recipient_person_id=v_job.recipient_person_id;
 elsif v_job.alert_notification_id is not null and p_outcome in ('retryable_failure','permanent_failure') then
  update public.mme_pos_financial_alert_notifications set delivery_status='failed',
   delivery_attempts=least(20,delivery_attempts+1),last_error_code=left(p_error_code,120)
   where id=v_job.alert_notification_id and recipient_person_id=v_job.recipient_person_id;
 end if;
 return p_job_id;
end;
$$;

create or replace view public.mme_notification_delivery_health
with (security_invoker=true) as
select channel,status,count(*)::integer job_count,
 count(*) filter(where created_at>=now()-interval '24 hours')::integer last_24h,
 max(updated_at) latest_update
from public.mme_notification_delivery_jobs
group by channel,status;

revoke all on function public.mme_notification_enqueue_delivery(uuid,uuid,text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_notification_set_channel_preference(uuid,uuid,text,boolean,time,time,text) from public,anon,authenticated;
revoke all on function public.mme_notification_claim_delivery_jobs(text,integer) from public,anon,authenticated;
revoke all on function public.mme_notification_complete_delivery(uuid,text,text,text,text,integer) from public,anon,authenticated;
revoke all on public.mme_notification_delivery_health from public,anon,authenticated;
grant execute on function public.mme_notification_enqueue_delivery(uuid,uuid,text,text,text,jsonb,text) to service_role;
grant execute on function public.mme_notification_set_channel_preference(uuid,uuid,text,boolean,time,time,text) to service_role;
grant execute on function public.mme_notification_claim_delivery_jobs(text,integer) to service_role;
grant execute on function public.mme_notification_complete_delivery(uuid,text,text,text,text,integer) to service_role;
grant select on public.mme_notification_delivery_health to service_role;

comment on table public.mme_notification_provider_routes is
 'Provider adapter routing metadata; secret_reference names runtime secrets and never stores credentials.';
comment on table public.mme_notification_delivery_jobs is
 'Idempotent provider-neutral delivery outbox for email, SMS, push and in-app messages.';
comment on view public.mme_notification_delivery_health is
 'Operational delivery health by channel and lifecycle state; no recipient contact data exposed.';

commit;
