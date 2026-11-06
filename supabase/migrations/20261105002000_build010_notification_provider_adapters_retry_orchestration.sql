begin;
alter table public.mme_security_incident_notifications
 add column if not exists delivery_max_attempts integer not null default 10 check(delivery_max_attempts between 1 and 10),
 add column if not exists delivery_lease_expires_at timestamptz,
 add column if not exists last_delivery_status text;
create table public.mme_security_notification_dead_letters(
 dead_letter_id uuid primary key default gen_random_uuid(),
 notification_id uuid not null unique references public.mme_security_incident_notifications(notification_id) on delete restrict,
 final_attempt integer not null,
 reason text not null check(length(reason)<=1000),
 provider text not null default 'unconfigured',
 quarantined_at timestamptz not null default now(),
 replayed_at timestamptz,
 replayed_by uuid
);
create table public.mme_security_notification_provider_health(
 provider text primary key,
 channel text not null check(channel in ('email','sms','pager','push')),
 enabled boolean not null default false,
 consecutive_failures integer not null default 0,
 last_success_at timestamptz,
 last_failure_at timestamptz,
 circuit_state text not null default 'closed' check(circuit_state in ('closed','open','half_open')),
 updated_at timestamptz not null default now()
);
alter table public.mme_security_notification_dead_letters enable row level security;
alter table public.mme_security_notification_provider_health enable row level security;
revoke all on public.mme_security_notification_dead_letters,public.mme_security_notification_provider_health from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_dead_letters,public.mme_security_notification_provider_health to service_role;
create index mme_security_notification_lease_idx on public.mme_security_incident_notifications(status,delivery_lease_expires_at,next_attempt_at);
create or replace function public.mme_security_notification_claim_due(p_limit integer default 25)
returns setof public.mme_security_incident_notifications
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query
 with due as (
  select n.notification_id
  from public.mme_security_incident_notifications n
  where n.status in ('pending','failed')
    and coalesce(n.next_attempt_at,n.created_at)<=now()
    and (n.delivery_lease_expires_at is null or n.delivery_lease_expires_at<now())
    and n.acknowledged_at is null
    and n.delivery_attempts<n.delivery_max_attempts
  order by coalesce(n.next_attempt_at,n.created_at),n.created_at
  for update skip locked limit greatest(1,least(p_limit,100))
 )
 update public.mme_security_incident_notifications n
 set status='pending',delivery_claimed_at=now(),delivery_lease_expires_at=now()+interval '2 minutes',
     delivery_attempts=n.delivery_attempts+1,last_delivery_status='claimed'
 from due where n.notification_id=due.notification_id
 returning n.*;
end $$;
create or replace function public.mme_security_notification_quarantine(p_notification uuid,p_reason text,p_provider text default 'unconfigured')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare n public.mme_security_incident_notifications%rowtype; d uuid;
begin
 select * into n from public.mme_security_incident_notifications where notification_id=p_notification for update;
 if not found then raise exception 'notification_not_found'; end if;
 if n.delivery_attempts<n.delivery_max_attempts then raise exception 'retry_budget_remaining'; end if;
 insert into public.mme_security_notification_dead_letters(notification_id,final_attempt,reason,provider)
 values(n.notification_id,n.delivery_attempts,left(coalesce(p_reason,'delivery failed'),1000),left(coalesce(p_provider,'unconfigured'),80))
 on conflict(notification_id) do update set reason=excluded.reason,final_attempt=excluded.final_attempt
 returning dead_letter_id into d;
 update public.mme_security_incident_notifications set status='failed',delivery_lease_expires_at=null,last_delivery_status='dead_letter' where notification_id=p_notification;
 return d;
end $$;
revoke all on function public.mme_security_notification_claim_due(integer) from public,anon,authenticated;
revoke all on function public.mme_security_notification_quarantine(uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_security_notification_claim_due(integer),public.mme_security_notification_quarantine(uuid,text,text) to service_role;
commit;