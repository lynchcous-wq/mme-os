begin;
alter table public.mme_security_notification_escalation_policies
 add column if not exists department text,
 add column if not exists notification_channels text[] not null default array['in_app']::text[],
 add column if not exists escalation_intervals_minutes integer[] not null default array[15,30]::integer[],
 add column if not exists policy_version integer not null default 1,
 add column if not exists updated_by uuid;
alter table public.mme_security_notification_escalation_alerts
 add column if not exists source_type text not null default 'manual',
 add column if not exists source_provider text,
 add column if not exists source_channel text;
create table public.mme_security_notification_policy_audit(
 audit_id uuid primary key default gen_random_uuid(),
 policy_id uuid not null references public.mme_security_notification_escalation_policies(policy_id) on delete restrict,
 policy_version integer not null,
 action text not null check(action in ('created','updated','enabled','disabled','simulated')),
 actor_id uuid,
 snapshot jsonb not null,
 created_at timestamptz not null default now()
);
create table public.mme_security_notification_outage_bridge_events(
 bridge_id uuid primary key default gen_random_uuid(),
 outage_id uuid not null references public.mme_security_notification_provider_outages(outage_id) on delete restrict,
 action text not null check(action in ('alert_created','alert_recovered','policy_missing','bridge_error')),
 alert_id uuid references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 detail text,
 created_at timestamptz not null default now(),
 unique(outage_id,action)
);
alter table public.mme_security_notification_policy_audit enable row level security;
alter table public.mme_security_notification_outage_bridge_events enable row level security;
revoke all on public.mme_security_notification_policy_audit,public.mme_security_notification_outage_bridge_events from public,anon,authenticated;
grant select,insert on public.mme_security_notification_policy_audit,public.mme_security_notification_outage_bridge_events to service_role;
create or replace function public.mme_security_notification_upsert_policy(
 p_policy_key text,p_severity text,p_department text,p_enabled boolean,
 p_acknowledge_minutes integer,p_roles text[],p_max_level integer,
 p_channels text[],p_intervals integer[],p_actor uuid,p_expected_version integer default null
) returns public.mme_security_notification_escalation_policies
language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.mme_security_notification_escalation_policies%rowtype;
begin
 if p_severity not in ('medium','high','critical') or p_acknowledge_minutes not between 1 and 1440 or p_max_level not between 1 and 5 then raise exception 'invalid_policy_bounds'; end if;
 if coalesce(array_length(p_roles,1),0)=0 or exists(select 1 from unnest(p_roles) r where r not in ('ceo','cio','it_admin','privacy_officer','operations_manager','store_manager')) then raise exception 'invalid_policy_roles'; end if;
 if coalesce(array_length(p_channels,1),0)=0 or exists(select 1 from unnest(p_channels) c where c not in ('in_app','email','sms','pager','push')) then raise exception 'invalid_policy_channels'; end if;
 if coalesce(array_length(p_intervals,1),0)=0 or exists(select 1 from unnest(p_intervals) i where i<1 or i>1440) then raise exception 'invalid_escalation_intervals'; end if;
 select * into p from public.mme_security_notification_escalation_policies where policy_key=p_policy_key for update;
 if found then
  if p_expected_version is null or p.policy_version<>p_expected_version then raise exception 'policy_version_conflict'; end if;
  update public.mme_security_notification_escalation_policies set severity=p_severity,department=nullif(left(p_department,100),''),enabled=p_enabled,acknowledge_within_minutes=p_acknowledge_minutes,escalation_roles=p_roles,max_escalation_level=p_max_level,notification_channels=p_channels,escalation_intervals_minutes=p_intervals,policy_version=policy_version+1,updated_by=p_actor,updated_at=now() where policy_id=p.policy_id returning * into p;
  insert into public.mme_security_notification_policy_audit(policy_id,policy_version,action,actor_id,snapshot) values(p.policy_id,p.policy_version,'updated',p_actor,to_jsonb(p));
 else
  if p_expected_version is not null then raise exception 'policy_version_conflict'; end if;
  insert into public.mme_security_notification_escalation_policies(policy_key,severity,department,enabled,acknowledge_within_minutes,escalation_roles,max_escalation_level,notification_channels,escalation_intervals_minutes,updated_by)
  values(left(p_policy_key,120),p_severity,nullif(left(p_department,100),''),p_enabled,p_acknowledge_minutes,p_roles,p_max_level,p_channels,p_intervals,p_actor) returning * into p;
  insert into public.mme_security_notification_policy_audit(policy_id,policy_version,action,actor_id,snapshot) values(p.policy_id,p.policy_version,'created',p_actor,to_jsonb(p));
 end if;
 return p;
end $$;
create or replace function public.mme_security_notification_simulate_policy(p_severity text,p_department text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.mme_security_notification_escalation_policies%rowtype;
begin
 select * into p from public.mme_security_notification_escalation_policies
 where enabled and severity=p_severity and (department is null or department=nullif(p_department,''))
 order by (department is not null) desc,updated_at desc limit 1;
 if not found then return jsonb_build_object('matched',false,'reason','no_enabled_policy_for_severity_department'); end if;
 return jsonb_build_object('matched',true,'policyKey',p.policy_key,'policyVersion',p.policy_version,'severity',p.severity,'department',p.department,'initialRecipients',p.escalation_roles,'acknowledgeWithinMinutes',p.acknowledge_within_minutes,'channels',p.notification_channels,'escalationIntervalsMinutes',p.escalation_intervals_minutes,'maximumLevel',p.max_escalation_level);
end $$;
create or replace function public.mme_security_notification_bridge_provider_outage()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.mme_security_notification_escalation_alerts%rowtype; k text;
begin
 if tg_op='INSERT' then
  k='provider-outage:'||new.provider||':'||new.outage_key;
  begin
   a:=public.mme_security_notification_create_escalation_alert(k,'Notification provider outage: '||new.provider,new.summary,new.severity,'IT');
   update public.mme_security_notification_escalation_alerts set source_type='provider_outage',source_provider=new.provider,source_channel=new.channel where alert_id=a.alert_id;
   insert into public.mme_security_notification_outage_bridge_events(outage_id,action,alert_id,detail) values(new.outage_id,'alert_created',a.alert_id,'Provider outage automatically created an executive escalation alert') on conflict(outage_id,action) do nothing;
  exception when others then
   insert into public.mme_security_notification_outage_bridge_events(outage_id,action,detail) values(new.outage_id,'policy_missing',sqlerrm) on conflict(outage_id,action) do update set detail=excluded.detail;
  end;
 elsif tg_op='UPDATE' and old.recovered_at is null and new.recovered_at is not null then
  k='provider-outage:'||new.provider||':'||new.outage_key;
  update public.mme_security_notification_escalation_alerts set status='resolved',resolved_at=new.recovered_at,summary=left(summary||' | Provider recovery confirmed.',2000)
   where source_key=k and status in ('open','acknowledged') returning * into a;
  insert into public.mme_security_notification_outage_bridge_events(outage_id,action,alert_id,detail) values(new.outage_id,'alert_recovered',a.alert_id,'Provider recovery automatically resolved the linked executive alert') on conflict(outage_id,action) do nothing;
 end if;
 return new;
end $$;
drop trigger if exists mme_security_notification_provider_outage_bridge on public.mme_security_notification_provider_outages;
create trigger mme_security_notification_provider_outage_bridge after insert or update of recovered_at on public.mme_security_notification_provider_outages for each row execute function public.mme_security_notification_bridge_provider_outage();
revoke all on function public.mme_security_notification_upsert_policy(text,text,text,boolean,integer,text[],integer,text[],integer[],uuid,integer),public.mme_security_notification_simulate_policy(text,text),public.mme_security_notification_bridge_provider_outage() from public,anon,authenticated;
grant execute on function public.mme_security_notification_upsert_policy(text,text,text,boolean,integer,text[],integer,text[],integer[],uuid,integer),public.mme_security_notification_simulate_policy(text,text) to service_role;
commit;