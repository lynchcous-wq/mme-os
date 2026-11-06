begin;
create table public.mme_security_notification_delivery_jobs(
 delivery_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 channel text not null check(channel in ('email','sms','pager','push')),
 recipient_role text not null,
 delivery_status text not null default 'queued' check(delivery_status in ('queued','processing','accepted','delivered','retry','failed','skipped','dead_letter')),
 attempt_count integer not null default 0,
 max_attempts integer not null default 5 check(max_attempts between 1 and 12),
 next_attempt_at timestamptz not null default now(),
 locked_at timestamptz,
 locked_by uuid,
 provider text,
 provider_reference text,
 last_error_code text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 delivered_at timestamptz,
 unique(alert_id,channel,recipient_role)
);
create table public.mme_security_notification_delivery_attempts(
 attempt_id bigint generated always as identity primary key,
 delivery_id uuid not null references public.mme_security_notification_delivery_jobs(delivery_id) on delete restrict,
 attempt_number integer not null,
 provider text not null,
 outcome text not null check(outcome in ('accepted','delivered','failed','skipped')),
 provider_reference text,
 error_code text,
 request_id uuid not null,
 attempted_at timestamptz not null default now(),
 unique(delivery_id,attempt_number)
);
create index mme_security_notification_delivery_claim_idx on public.mme_security_notification_delivery_jobs(delivery_status,next_attempt_at,created_at) where delivery_status in ('queued','retry');
create index mme_security_notification_delivery_attempt_history_idx on public.mme_security_notification_delivery_attempts(delivery_id,attempted_at desc);
alter table public.mme_security_notification_delivery_jobs enable row level security;
alter table public.mme_security_notification_delivery_attempts enable row level security;
revoke all on public.mme_security_notification_delivery_jobs,public.mme_security_notification_delivery_attempts from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_delivery_jobs,public.mme_security_notification_delivery_attempts to service_role;
create or replace function public.mme_security_notification_queue_alert_deliveries()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare channels text[];
begin
 select notification_channels into channels from public.mme_security_notification_escalation_policies where policy_id=new.policy_id and policy_version=new.policy_version;
 if channels is null then channels:=array['in_app']::text[]; end if;
 insert into public.mme_security_notification_delivery_jobs(alert_id,channel,recipient_role)
 select new.alert_id,c,r from unnest(channels) c cross join unnest(new.target_roles) r
 where c in ('email','sms','pager','push')
 on conflict(alert_id,channel,recipient_role) do nothing;
 return new;
end $$;
drop trigger if exists mme_security_notification_alert_delivery_queue on public.mme_security_notification_escalation_alerts;
create trigger mme_security_notification_alert_delivery_queue after insert or update of target_roles,escalation_level on public.mme_security_notification_escalation_alerts for each row execute function public.mme_security_notification_queue_alert_deliveries();
create or replace function public.mme_security_notification_claim_delivery_jobs(p_worker uuid,p_limit integer default 20)
returns table(delivery_id uuid,alert_id uuid,channel text,recipient_role text,attempt_count integer,max_attempts integer,title text,message text,severity text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query with picked as(
  select j.delivery_id from public.mme_security_notification_delivery_jobs j
  where j.delivery_status in ('queued','retry') and j.attempt_count<j.max_attempts and j.next_attempt_at<=now()
   and (j.locked_at is null or j.locked_at<now()-interval '5 minutes')
  order by j.created_at for update skip locked limit greatest(1,least(coalesce(p_limit,20),100))
 ), claimed as(
  update public.mme_security_notification_delivery_jobs j set delivery_status='processing',locked_at=now(),locked_by=p_worker,updated_at=now()
  from picked p where j.delivery_id=p.delivery_id returning j.*
 )
 select c.delivery_id,c.alert_id,c.channel,c.recipient_role,c.attempt_count,c.max_attempts,a.title,a.summary,a.severity
 from claimed c join public.mme_security_notification_escalation_alerts a on a.alert_id=c.alert_id;
end $$;
create or replace function public.mme_security_notification_finish_delivery(p_delivery uuid,p_worker uuid,p_provider text,p_outcome text,p_reference text,p_error text,p_request uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.mme_security_notification_delivery_jobs%rowtype; n integer; status_value text;
begin
 select * into j from public.mme_security_notification_delivery_jobs where delivery_id=p_delivery and locked_by=p_worker and delivery_status='processing' for update;
 if not found then raise exception 'delivery_lease_not_found'; end if;
 if p_outcome not in ('accepted','delivered','failed','skipped') then raise exception 'invalid_delivery_outcome'; end if;
 n:=j.attempt_count+1;
 status_value:=case when p_outcome='delivered' then 'delivered' when p_outcome='accepted' then 'accepted' when p_outcome='skipped' then 'skipped' when n>=j.max_attempts then 'dead_letter' else 'retry' end;
 update public.mme_security_notification_delivery_jobs set attempt_count=n,delivery_status=status_value,provider=p_provider,provider_reference=p_reference,last_error_code=p_error,delivered_at=case when p_outcome='delivered' then now() else delivered_at end,next_attempt_at=now()+make_interval(secs=>least(3600,30*(2^least(n,6))::integer)),locked_at=null,locked_by=null,updated_at=now() where delivery_id=p_delivery;
 insert into public.mme_security_notification_delivery_attempts(delivery_id,attempt_number,provider,outcome,provider_reference,error_code,request_id) values(p_delivery,n,p_provider,p_outcome,p_reference,p_error,p_request);
end $$;
revoke all on function public.mme_security_notification_queue_alert_deliveries(),public.mme_security_notification_claim_delivery_jobs(uuid,integer),public.mme_security_notification_finish_delivery(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_security_notification_claim_delivery_jobs(uuid,integer),public.mme_security_notification_finish_delivery(uuid,uuid,text,text,text,text,uuid) to service_role;
commit;