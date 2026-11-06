begin;
create table public.mme_security_notification_escalation_channel_deliveries(
 channel_delivery_id uuid primary key default gen_random_uuid(),
 dispatch_id uuid not null references public.mme_security_notification_escalation_dispatch_events(dispatch_id) on delete restrict,
 channel text not null check(channel in ('email','sms','pager','push')),
 status text not null default 'queued' check(status in ('queued','processing','accepted','delivered','retry','failed','skipped','dead_letter')),
 attempt_count integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 locked_at timestamptz,locked_by uuid,provider text,provider_reference text,last_error text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(dispatch_id,channel)
);
create table public.mme_security_notification_escalation_channel_attempts(
 attempt_id bigint generated always as identity primary key,
 channel_delivery_id uuid not null references public.mme_security_notification_escalation_channel_deliveries(channel_delivery_id) on delete restrict,
 attempt_number integer not null,provider text not null,outcome text not null check(outcome in ('accepted','delivered','failed','skipped')),
 provider_reference text,error_code text,request_id uuid not null,attempted_at timestamptz not null default now(),
 unique(channel_delivery_id,attempt_number)
);
create index mme_security_notification_channel_due on public.mme_security_notification_escalation_channel_deliveries(status,next_attempt_at) where status in ('queued','retry');
alter table public.mme_security_notification_escalation_channel_deliveries enable row level security;
alter table public.mme_security_notification_escalation_channel_attempts enable row level security;
revoke all on public.mme_security_notification_escalation_channel_deliveries,public.mme_security_notification_escalation_channel_attempts from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_escalation_channel_deliveries,public.mme_security_notification_escalation_channel_attempts to service_role;
insert into public.mme_security_notification_escalation_channel_deliveries(dispatch_id,channel)
select d.dispatch_id,c.channel from public.mme_security_notification_escalation_dispatch_events d
cross join (values('email'),('sms'),('pager'),('push')) c(channel)
where d.dispatch_status in ('queued','retry','processing')
on conflict(dispatch_id,channel) do nothing;
create or replace function public.mme_security_notification_materialize_escalation_channels(p_channels text[])
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 if coalesce(array_length(p_channels,1),0)=0 or exists(select 1 from unnest(p_channels) c where c not in ('email','sms','pager','push')) then raise exception 'invalid_channels'; end if;
 insert into public.mme_security_notification_escalation_channel_deliveries(dispatch_id,channel)
 select d.dispatch_id,c from public.mme_security_notification_escalation_dispatch_events d cross join unnest(p_channels) c
 where d.dispatch_status in ('queued','retry','processing')
 on conflict(dispatch_id,channel) do nothing;
 get diagnostics n=row_count;return n;
end $$;
create or replace function public.mme_security_notification_claim_escalation_channels(p_worker uuid,p_limit integer default 40)
returns table(channel_delivery_id uuid,dispatch_id uuid,alert_id uuid,target_role text,channel text,attempt_count integer,title text,summary text,severity text,escalation_level integer)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query with picked as(select c.channel_delivery_id from public.mme_security_notification_escalation_channel_deliveries c join public.mme_security_notification_escalation_dispatch_events d using(dispatch_id) where c.status in ('queued','retry') and c.next_attempt_at<=now() and (c.locked_at is null or c.locked_at<now()-interval '5 minutes') and d.dispatch_status not in ('cancelled','dispatched','dead_letter') order by c.next_attempt_at,c.created_at for update of c skip locked limit least(greatest(coalesce(p_limit,40),1),100)),
 claimed as(update public.mme_security_notification_escalation_channel_deliveries c set status='processing',locked_at=now(),locked_by=p_worker,attempt_count=c.attempt_count+1,updated_at=now() from picked p where c.channel_delivery_id=p.channel_delivery_id returning c.*)
 select c.channel_delivery_id,c.dispatch_id,d.alert_id,d.target_role,c.channel,c.attempt_count,a.title,a.summary,a.severity,e.escalation_level from claimed c join public.mme_security_notification_escalation_dispatch_events d using(dispatch_id) join public.mme_security_notification_escalation_alerts a on a.alert_id=d.alert_id join public.mme_security_notification_acknowledgement_escalations e on e.escalation_id=d.escalation_id;
end $$;
create or replace function public.mme_security_notification_finish_escalation_channel(p_channel_delivery uuid,p_worker uuid,p_provider text,p_outcome text,p_reference text,p_error text,p_request uuid)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.mme_security_notification_escalation_channel_deliveries%rowtype; n integer; result text; all_terminal boolean; any_dead boolean;
begin
 select * into c from public.mme_security_notification_escalation_channel_deliveries where channel_delivery_id=p_channel_delivery and status='processing' and locked_by=p_worker for update;
 if not found then raise exception 'channel_delivery_lease_invalid'; end if;
 if p_outcome not in ('accepted','delivered','failed','skipped') then raise exception 'invalid_channel_outcome'; end if;
 n:=c.attempt_count;
 result:=case when p_outcome in ('accepted','delivered','skipped') then p_outcome when n>=5 then 'dead_letter' else 'retry' end;
 update public.mme_security_notification_escalation_channel_deliveries set status=result,provider=p_provider,provider_reference=p_reference,last_error=left(p_error,250),next_attempt_at=now()+make_interval(secs=>least(3600,30*(2^least(n,6))::integer)),locked_at=null,locked_by=null,updated_at=now() where channel_delivery_id=p_channel_delivery;
 insert into public.mme_security_notification_escalation_channel_attempts(channel_delivery_id,attempt_number,provider,outcome,provider_reference,error_code,request_id) values(p_channel_delivery,n,p_provider,p_outcome,p_reference,left(p_error,250),p_request);
 select bool_and(status in ('accepted','delivered','skipped','dead_letter')),(bool_or(status='dead_letter')) into all_terminal,any_dead from public.mme_security_notification_escalation_channel_deliveries where dispatch_id=c.dispatch_id;
 if all_terminal then update public.mme_security_notification_escalation_dispatch_events set dispatch_status=case when any_dead then 'dead_letter' else 'dispatched' end,updated_at=now() where dispatch_id=c.dispatch_id; end if;
 return result;
end $$;
revoke all on function public.mme_security_notification_materialize_escalation_channels(text[]),public.mme_security_notification_claim_escalation_channels(uuid,integer),public.mme_security_notification_finish_escalation_channel(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_security_notification_materialize_escalation_channels(text[]),public.mme_security_notification_claim_escalation_channels(uuid,integer),public.mme_security_notification_finish_escalation_channel(uuid,uuid,text,text,text,text,uuid) to service_role;
commit;