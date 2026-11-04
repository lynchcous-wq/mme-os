-- Build 001: leased notification delivery worker, bounded retries and provider-result recording.
alter table public.mme_customer_notification_outbox
 add column if not exists locked_at timestamptz,
 add column if not exists locked_by text,
 add column if not exists next_attempt_at timestamptz not null default now(),
 add column if not exists delivered_at timestamptz,
 add column if not exists provider_status text,
 add column if not exists last_attempt_at timestamptz;
create index if not exists mme_customer_notification_worker_idx
 on public.mme_customer_notification_outbox(next_attempt_at,created_at)
 where delivery_status in ('queued','failed');

create or replace function public.mme_claim_customer_notifications(
 p_worker_id text,p_batch_size integer default 25,p_lease_seconds integer default 120
) returns setof public.mme_customer_notification_outbox
language plpgsql security definer set search_path='' as $$
begin
 if p_worker_id is null or length(btrim(p_worker_id)) not between 3 and 120
  or p_batch_size is null or p_batch_size not between 1 and 100
  or p_lease_seconds is null or p_lease_seconds not between 30 and 900 then
  raise exception 'Invalid notification worker claim request' using errcode='22023'; end if;
 return query
 with candidates as (
  select id from public.mme_customer_notification_outbox
  where (delivery_status in ('queued','failed') and next_attempt_at<=now())
    or (delivery_status='sending' and locked_at<now()-make_interval(secs=>p_lease_seconds))
  order by next_attempt_at,created_at
  for update skip locked limit p_batch_size
 ), claimed as (
  update public.mme_customer_notification_outbox o
  set delivery_status='sending',locked_at=now(),locked_by=btrim(p_worker_id),
      attempt_count=attempt_count+1,last_attempt_at=now(),updated_at=now()
  from candidates c where o.id=c.id
  returning o.*
 ) select * from claimed;
end; $$;

create or replace function public.mme_complete_customer_notification(
 p_notification_id uuid,p_worker_id text,p_provider text,p_provider_message_id text
) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_notification_id is null or p_worker_id is null or p_provider is null
  or length(btrim(p_provider)) not between 2 and 80
  or p_provider_message_id is null or length(btrim(p_provider_message_id)) not between 1 and 255 then
  raise exception 'Invalid notification completion' using errcode='22023'; end if;
 update public.mme_customer_notification_outbox
 set delivery_status='sent',provider=left(btrim(p_provider),80),
     provider_message_id=left(btrim(p_provider_message_id),255),
     sent_at=now(),delivered_at=now(),locked_at=null,locked_by=null,
     last_error_code=null,updated_at=now()
 where id=p_notification_id and delivery_status='sending' and locked_by=btrim(p_worker_id);
 return found;
end; $$;

create or replace function public.mme_fail_customer_notification(
 p_notification_id uuid,p_worker_id text,p_error_code text,p_retryable boolean default true
) returns boolean language plpgsql security definer set search_path='' as $$
declare v_attempt integer; v_status text; v_delay integer;
begin
 if p_notification_id is null or p_worker_id is null or p_error_code is null
  or length(btrim(p_error_code)) not between 1 and 120 then
  raise exception 'Invalid notification failure update' using errcode='22023'; end if;
 select attempt_count into v_attempt from public.mme_customer_notification_outbox
 where id=p_notification_id and delivery_status='sending' and locked_by=btrim(p_worker_id) for update;
 if not found then return false; end if;
 v_status:=case when p_retryable and v_attempt<8 then 'failed' else 'suppressed' end;
 v_delay:=least(21600,(30 * power(2,least(v_attempt,9)))::integer);
 update public.mme_customer_notification_outbox
 set delivery_status=v_status,last_error_code=left(btrim(p_error_code),120),
     next_attempt_at=now()+make_interval(secs=>v_delay),
     locked_at=null,locked_by=null,updated_at=now()
 where id=p_notification_id;
 return true;
end; $$;

revoke all on function public.mme_claim_customer_notifications(text,integer,integer) from public,anon,authenticated;
revoke all on function public.mme_complete_customer_notification(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_fail_customer_notification(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.mme_claim_customer_notifications(text,integer,integer) to service_role;
grant execute on function public.mme_complete_customer_notification(uuid,text,text,text) to service_role;
grant execute on function public.mme_fail_customer_notification(uuid,text,text,boolean) to service_role;
comment on function public.mme_claim_customer_notifications(text,integer,integer) is 'Atomically leases queued notifications with SKIP LOCKED; workers must not send outside a successful lease.';
