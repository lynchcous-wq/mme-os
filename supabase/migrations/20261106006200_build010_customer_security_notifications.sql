-- Build 010.89 — customer security-alert preferences and idempotent email queue integration.
begin;
create table if not exists public.mme_customer_security_alert_preferences (
 auth_user_id uuid primary key,
 email_alerts_enabled boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.mme_customer_security_alert_preferences enable row level security;
revoke all on public.mme_customer_security_alert_preferences from public,anon,authenticated;
grant select on public.mme_customer_security_alert_preferences to authenticated;
create policy mme_customer_security_alert_preferences_self_read
 on public.mme_customer_security_alert_preferences for select to authenticated
 using(auth_user_id=auth.uid());
create or replace function public.mme_customer_security_alert_preference_update(p_auth_user_id uuid,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth
as $$
declare v_confirmed timestamptz;
begin
 if p_auth_user_id is null or auth.uid() is distinct from p_auth_user_id then
  raise exception 'Customer session does not match preference owner' using errcode='42501';
 end if;
 if p_enabled is null then raise exception 'Preference value is required' using errcode='22023'; end if;
 select email_confirmed_at into v_confirmed from auth.users where id=p_auth_user_id;
 if not found or v_confirmed is null then raise exception 'Verified account required' using errcode='42501'; end if;
 if not exists(select 1 from public.mme_customer_account_links l
  join public.mme_person_identities i on i.person_id=l.person_id
  where l.auth_user_id=p_auth_user_id and l.link_status='active' and i.lifecycle_status='active') then
  raise exception 'Active MME customer identity required' using errcode='42501';
 end if;
 insert into public.mme_customer_security_alert_preferences(auth_user_id,email_alerts_enabled)
 values(p_auth_user_id,p_enabled)
 on conflict(auth_user_id) do update set email_alerts_enabled=excluded.email_alerts_enabled,updated_at=now();
 return jsonb_build_object('email_alerts_enabled',p_enabled);
end;
$$;
revoke all on function public.mme_customer_security_alert_preference_update(uuid,boolean) from public,anon;
grant execute on function public.mme_customer_security_alert_preference_update(uuid,boolean) to authenticated;
alter table public.mme_notifications add column if not exists source_security_event_id bigint;
create unique index if not exists mme_notifications_security_event_once_idx
 on public.mme_notifications(source_security_event_id) where source_security_event_id is not null;
create or replace function public.mme_customer_security_event_email_alert()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth
as $$
declare v_email text; v_email_enabled boolean; v_security_enabled boolean; v_notification_id uuid;
begin
 if new.event_type not in ('sign_in_success','sessions_revoked','password_recovery_completed') then return new; end if;
 select u.email,coalesce(p.email_notifications_enabled,true),coalesce(s.email_alerts_enabled,true)
 into v_email,v_email_enabled,v_security_enabled
 from auth.users u
 left join public.mme_customer_profiles p on p.auth_user_id=u.id
 left join public.mme_customer_security_alert_preferences s on s.auth_user_id=u.id
 where u.id=new.auth_user_id and u.email_confirmed_at is not null;
 if v_email is null or not v_email_enabled or not v_security_enabled then return new; end if;
 insert into public.mme_notifications(
  customer_id,recipient,channel,purpose,subject,body,notification_status,
  scheduled_at,next_attempt_at,created_by_auth_user_id,source_security_event_id
 ) values(
  null,v_email,'email','transactional',
  case new.event_type
   when 'sign_in_success' then 'New sign-in to your MME account'
   when 'sessions_revoked' then 'MME account sessions signed out'
   else 'MME account recovery completed' end,
  case new.event_type
   when 'sign_in_success' then 'A successful sign-in to your Much More Electronics account was recorded. If this was not you, reset your password and sign out all sessions.'
   when 'sessions_revoked' then 'A global sign-out request was recorded for your Much More Electronics account. If you did not request this, reset your password.'
   else 'A password recovery completion was recorded for your Much More Electronics account. If this was not you, contact MME support.' end,
  'queued',now(),now(),new.auth_user_id,new.event_id
 ) on conflict(source_security_event_id) where source_security_event_id is not null do nothing
 returning notification_id into v_notification_id;
 return new;
end;
$$;
drop trigger if exists mme_customer_security_event_email_alert_trigger on public.mme_customer_security_events;
create trigger mme_customer_security_event_email_alert_trigger
 after insert on public.mme_customer_security_events
 for each row execute function public.mme_customer_security_event_email_alert();
revoke all on function public.mme_customer_security_event_email_alert() from public,anon,authenticated;
comment on table public.mme_customer_security_alert_preferences is 'Customer opt-out preference for transactional account-security email alerts; provider delivery is handled by existing MME notification workers.';
comment on column public.mme_notifications.source_security_event_id is 'Unique originating MME customer security event for idempotent account-alert queueing.';
commit;
