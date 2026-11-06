begin;
create table if not exists public.mme_security_notification_incident_ownership(
 ownership_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 owner_user_id uuid,owner_role text not null,assigned_by uuid not null,assignment_reason text,
 ownership_status text not null default 'active' check(ownership_status in ('active','transferred','resolved','unclaimed')),
 assigned_at timestamptz not null default now(),due_at timestamptz,resolved_at timestamptz,created_at timestamptz not null default now()
);
create unique index if not exists mme_security_notification_one_active_owner on public.mme_security_notification_incident_ownership(alert_id) where ownership_status='active';
create index if not exists mme_security_notification_ownership_due on public.mme_security_notification_incident_ownership(ownership_status,due_at);
create table if not exists public.mme_security_notification_escalation_dispatch_events(
 dispatch_id uuid primary key default gen_random_uuid(),
 escalation_id uuid not null references public.mme_security_notification_acknowledgement_escalations(escalation_id) on delete restrict,
 alert_id uuid not null references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 target_role text not null,dispatch_status text not null default 'queued' check(dispatch_status in ('queued','processing','dispatched','retry','failed','dead_letter','cancelled')),
 attempt_count integer not null default 0,next_attempt_at timestamptz not null default now(),claimed_at timestamptz,claimed_by uuid,last_error text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(escalation_id,target_role)
);
create table if not exists public.mme_security_notification_ownership_events(
 event_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 previous_owner uuid,new_owner uuid,actor_id uuid not null,
 event_type text not null check(event_type in ('assigned','transferred','unclaimed','resolved','executive_override')),reason text,occurred_at timestamptz not null default now()
);
create index if not exists mme_security_notification_dispatch_due on public.mme_security_notification_escalation_dispatch_events(dispatch_status,next_attempt_at);
alter table public.mme_security_notification_incident_ownership enable row level security;
alter table public.mme_security_notification_escalation_dispatch_events enable row level security;
alter table public.mme_security_notification_ownership_events enable row level security;
revoke all on public.mme_security_notification_incident_ownership,public.mme_security_notification_escalation_dispatch_events,public.mme_security_notification_ownership_events from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_incident_ownership,public.mme_security_notification_escalation_dispatch_events,public.mme_security_notification_ownership_events to service_role;
create or replace function public.mme_security_notification_claim_escalation_dispatch(p_worker uuid,p_limit integer default 20)
returns table(dispatch_id uuid,alert_id uuid,target_role text,title text,summary text,severity text,escalation_level integer)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query with picked as(select d.dispatch_id from public.mme_security_notification_escalation_dispatch_events d where d.dispatch_status in ('queued','retry') and d.next_attempt_at<=now() order by d.next_attempt_at,d.created_at for update skip locked limit least(greatest(coalesce(p_limit,20),1),50)),
 claimed as(update public.mme_security_notification_escalation_dispatch_events d set dispatch_status='processing',claimed_at=now(),claimed_by=p_worker,attempt_count=d.attempt_count+1,updated_at=now() from picked where d.dispatch_id=picked.dispatch_id returning d.*)
 select c.dispatch_id,c.alert_id,c.target_role,a.title,a.summary,a.severity,e.escalation_level from claimed c join public.mme_security_notification_escalation_alerts a on a.alert_id=c.alert_id join public.mme_security_notification_acknowledgement_escalations e on e.escalation_id=c.escalation_id;
end $$;
create or replace function public.mme_security_notification_finish_escalation_dispatch(p_dispatch uuid,p_worker uuid,p_success boolean,p_error text default null)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.mme_security_notification_escalation_dispatch_events%rowtype;
begin
 select * into d from public.mme_security_notification_escalation_dispatch_events where dispatch_id=p_dispatch for update;
 if not found or d.dispatch_status<>'processing' or d.claimed_by<>p_worker then raise exception 'dispatch_lease_invalid'; end if;
 if p_success then update public.mme_security_notification_escalation_dispatch_events set dispatch_status='dispatched',updated_at=now(),last_error=null where dispatch_id=p_dispatch; update public.mme_security_notification_acknowledgement_escalations set escalation_status='issued',issued_at=now() where escalation_id=d.escalation_id; return 'dispatched'; end if;
 update public.mme_security_notification_escalation_dispatch_events set dispatch_status=case when attempt_count>=5 then 'dead_letter' else 'retry' end,next_attempt_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempt_count,7))::integer)),last_error=left(coalesce(p_error,'dispatch_failed'),250),updated_at=now() where dispatch_id=p_dispatch;
 return case when d.attempt_count>=5 then 'dead_letter' else 'retry' end;
end $$;
create or replace function public.mme_security_notification_transfer_ownership(p_alert uuid,p_actor uuid,p_actor_roles text[],p_new_owner uuid,p_new_role text,p_reason text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare old public.mme_security_notification_incident_ownership%rowtype; new_id uuid;
begin
 if not (coalesce(p_actor_roles,'{}'::text[]) && array['ceo','cio','it_admin','operations_manager','store_manager']::text[]) then raise exception 'ownership_transfer_forbidden'; end if;
 if p_new_role not in ('ceo','cio','it_admin','operations_manager','store_manager') then raise exception 'invalid_owner_role'; end if;
 perform 1 from public.mme_security_notification_escalation_alerts where alert_id=p_alert for update;
 if not found then raise exception 'alert_not_found'; end if;
 if p_new_owner is not null and not exists(select 1 from auth.users where id=p_new_owner) then raise exception 'owner_user_not_found'; end if;
 select * into old from public.mme_security_notification_incident_ownership where alert_id=p_alert and ownership_status='active' for update;
 if found then update public.mme_security_notification_incident_ownership set ownership_status='transferred' where ownership_id=old.ownership_id; end if;
 insert into public.mme_security_notification_incident_ownership(alert_id,owner_user_id,owner_role,assigned_by,assignment_reason,due_at) values(p_alert,p_new_owner,p_new_role,p_actor,left(p_reason,1000),now()+interval '30 minutes') returning ownership_id into new_id;
 insert into public.mme_security_notification_ownership_events(alert_id,previous_owner,new_owner,actor_id,event_type,reason) values(p_alert,old.owner_user_id,p_new_owner,p_actor,case when p_actor_roles&&array['ceo','cio']::text[] then 'executive_override' else 'transferred' end,left(p_reason,1000));
 return jsonb_build_object('result','transferred','ownershipId',new_id);
end $$;
revoke all on function public.mme_security_notification_claim_escalation_dispatch(uuid,integer),public.mme_security_notification_finish_escalation_dispatch(uuid,uuid,boolean,text),public.mme_security_notification_transfer_ownership(uuid,uuid,text[],uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_security_notification_claim_escalation_dispatch(uuid,integer),public.mme_security_notification_finish_escalation_dispatch(uuid,uuid,boolean,text),public.mme_security_notification_transfer_ownership(uuid,uuid,text[],uuid,text,text,uuid) to service_role;
commit;