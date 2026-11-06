begin;
alter table public.mme_warranty_api_security_alert_deliveries
 add column if not exists next_attempt_at timestamptz not null default now(),
 add column if not exists locked_at timestamptz,
 add column if not exists locked_by uuid,
 add column if not exists max_attempts integer not null default 5 check(max_attempts between 1 and 12);
create index if not exists mme_warranty_security_delivery_queue_idx
 on public.mme_warranty_api_security_alert_deliveries(delivery_status,next_attempt_at)
 where delivery_status in ('queued','failed');

create table public.mme_warranty_api_security_delivery_attempts (
 attempt_id bigint generated always as identity primary key,
 delivery_id uuid not null references public.mme_warranty_api_security_alert_deliveries(delivery_id) on delete restrict,
 attempt_number integer not null,
 provider text not null check(provider in ('resend','twilio','in_app')),
 outcome text not null check(outcome in ('accepted','delivered','failed','skipped')),
 provider_reference text,
 error_code text,
 request_id uuid,
 attempted_at timestamptz not null default now(),
 unique(delivery_id,attempt_number)
);
alter table public.mme_warranty_api_security_delivery_attempts enable row level security;
revoke all on public.mme_warranty_api_security_delivery_attempts from public,anon,authenticated;
grant select,insert on public.mme_warranty_api_security_delivery_attempts to service_role;

create or replace function public.mme_warranty_api_security_claim_deliveries(p_worker_id uuid,p_limit integer default 20)
returns table(delivery_id uuid,alert_id uuid,channel text,recipient_role text,attempt_count integer,max_attempts integer,title text,message text,severity text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query
 with picked as (
  select d.delivery_id from public.mme_warranty_api_security_alert_deliveries d
  where d.channel in ('email','sms') and d.delivery_status in ('queued','failed')
   and d.attempt_count<d.max_attempts and d.next_attempt_at<=now()
   and (d.locked_at is null or d.locked_at<now()-interval '10 minutes')
  order by d.created_at for update skip locked limit greatest(1,least(coalesce(p_limit,20),100))
 ), claimed as (
  update public.mme_warranty_api_security_alert_deliveries d
  set locked_at=now(),locked_by=p_worker_id
  from picked p where d.delivery_id=p.delivery_id returning d.*
 )
 select c.delivery_id,c.alert_id,c.channel,c.recipient_role,c.attempt_count,c.max_attempts,a.title,a.message,a.severity
 from claimed c join public.mme_warranty_api_security_alerts a on a.alert_id=c.alert_id;
end $$;
revoke all on function public.mme_warranty_api_security_claim_deliveries(uuid,integer) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_claim_deliveries(uuid,integer) to service_role;

create or replace function public.mme_warranty_api_security_finish_delivery(
 p_delivery_id uuid,p_worker_id uuid,p_provider text,p_outcome text,p_provider_reference text,p_error_code text,p_request_id uuid
) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_attempt integer; v_max integer; v_status text; v_alert uuid;
begin
 select attempt_count,max_attempts,alert_id into v_attempt,v_max,v_alert
 from public.mme_warranty_api_security_alert_deliveries
 where delivery_id=p_delivery_id and locked_by=p_worker_id for update;
 if not found then raise exception 'delivery_lease_not_found'; end if;
 if p_outcome not in ('accepted','delivered','failed','skipped') then raise exception 'invalid_delivery_outcome'; end if;
 v_attempt:=v_attempt+1;
 v_status:=case when p_outcome in ('accepted','delivered') then 'sent' when p_outcome='skipped' then 'skipped' when v_attempt>=v_max then 'failed' else 'queued' end;
 update public.mme_warranty_api_security_alert_deliveries
 set attempt_count=v_attempt,delivery_status=v_status,provider_reference=p_provider_reference,
  last_attempt_at=now(),last_error_code=p_error_code,delivered_at=case when p_outcome='delivered' then now() else delivered_at end,
  next_attempt_at=now()+make_interval(secs=>least(3600,30*(2^least(v_attempt,6))::integer)),
  locked_at=null,locked_by=null
 where delivery_id=p_delivery_id;
 insert into public.mme_warranty_api_security_delivery_attempts(delivery_id,attempt_number,provider,outcome,provider_reference,error_code,request_id)
 values(p_delivery_id,v_attempt,p_provider,p_outcome,p_provider_reference,p_error_code,p_request_id);
 insert into public.mme_warranty_api_security_alert_events(alert_id,event_type,details,request_id)
 values(v_alert,'delivery_attempted',jsonb_build_object('deliveryId',p_delivery_id,'attempt',v_attempt,'provider',p_provider,'outcome',p_outcome,'errorCode',p_error_code),p_request_id);
end $$;
revoke all on function public.mme_warranty_api_security_finish_delivery(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_finish_delivery(uuid,uuid,text,text,text,text,uuid) to service_role;
commit;