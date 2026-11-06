begin;
alter table public.mme_security_incident_notifications
 add column if not exists idempotency_key text,
 add column if not exists acknowledgement_due_at timestamptz,
 add column if not exists delivery_attempts integer not null default 0,
 add column if not exists next_attempt_at timestamptz,
 add column if not exists delivery_claimed_at timestamptz,
 add column if not exists recipient_user_id uuid,
 add column if not exists delivered_at timestamptz;
create unique index if not exists mme_security_incident_notifications_idempotency_idx
 on public.mme_security_incident_notifications(idempotency_key) where idempotency_key is not null;
create index if not exists mme_security_incident_notifications_retry_idx
 on public.mme_security_incident_notifications(status,next_attempt_at,created_at);
create table public.mme_security_notification_preferences(
 preference_id uuid primary key default gen_random_uuid(),
 user_id uuid not null,
 notification_type text not null check(notification_type in ('incident_created','deadline_warning','deadline_breached','escalation','assignment_required')),
 channel text not null check(channel in ('in_app','email','sms','pager')),
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(user_id,notification_type,channel)
);
create table public.mme_security_notification_delivery_attempts(
 attempt_id uuid primary key default gen_random_uuid(),
 notification_id uuid not null references public.mme_security_incident_notifications(notification_id) on delete restrict,
 attempt_number integer not null check(attempt_number between 1 and 10),
 channel text not null check(channel in ('in_app','email','sms','pager')),
 provider text not null default 'unconfigured',
 status text not null check(status in ('queued','accepted','delivered','failed','unknown')),
 provider_reference text,
 error_code text,
 error_message text,
 attempted_at timestamptz not null default now(),
 unique(notification_id,attempt_number)
);
create table public.mme_security_notification_ack_events(
 ack_id uuid primary key default gen_random_uuid(),
 notification_id uuid not null references public.mme_security_incident_notifications(notification_id) on delete restrict,
 acknowledged_by uuid not null,
 acknowledged_at timestamptz not null default now(),
 channel text not null default 'in_app',
 note text check(note is null or length(note)<=1000),
 unique(notification_id,acknowledged_by)
);
alter table public.mme_security_notification_preferences enable row level security;
alter table public.mme_security_notification_delivery_attempts enable row level security;
alter table public.mme_security_notification_ack_events enable row level security;
revoke all on public.mme_security_notification_preferences,public.mme_security_notification_delivery_attempts,public.mme_security_notification_ack_events from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_preferences to service_role;
grant select,insert on public.mme_security_notification_delivery_attempts,public.mme_security_notification_ack_events to service_role;
grant select,insert,update on public.mme_security_incident_notifications to service_role;
create or replace function public.mme_security_notification_claim_due(p_limit integer default 25)
returns setof public.mme_security_incident_notifications
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query
 with due as (
  select n.notification_id from public.mme_security_incident_notifications n
  where n.status in ('pending','failed') and coalesce(n.next_attempt_at,n.created_at)<=now()
    and n.acknowledged_at is null and n.delivery_attempts<10
  order by coalesce(n.next_attempt_at,n.created_at),n.created_at
  for update skip locked limit greatest(1,least(p_limit,100))
 )
 update public.mme_security_incident_notifications n
 set status='pending',delivery_claimed_at=now(),delivery_attempts=delivery_attempts+1
 from due where n.notification_id=due.notification_id
 returning n.*;
end $$;
revoke all on function public.mme_security_notification_claim_due(integer) from public,anon,authenticated;
grant execute on function public.mme_security_notification_claim_due(integer) to service_role;
commit;