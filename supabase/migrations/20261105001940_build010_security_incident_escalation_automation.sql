begin;
create table public.mme_security_incident_escalation_jobs(
 job_id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_security_incidents(incident_id) on delete restrict,
 escalation_level integer not null default 1 check(escalation_level between 1 and 5),
 due_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','claimed','completed','cancelled','failed')),
 attempts integer not null default 0 check(attempts>=0),
 claimed_at timestamptz,
 completed_at timestamptz,
 last_error text,
 created_at timestamptz not null default now(),
 unique(incident_id,escalation_level)
);
create index mme_security_incident_escalation_jobs_due_idx on public.mme_security_incident_escalation_jobs(status,due_at);
create table public.mme_security_incident_notifications(
 notification_id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_security_incidents(incident_id) on delete restrict,
 recipient_role text not null check(recipient_role in ('it_admin','cio','ceo','privacy_officer')),
 notification_type text not null check(notification_type in ('incident_created','deadline_warning','deadline_breached','escalation','assignment_required')),
 status text not null default 'pending' check(status in ('pending','sent','failed','acknowledged')),
 channel text not null default 'in_app' check(channel in ('in_app','email','sms','pager')),
 payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 sent_at timestamptz,
 acknowledged_at timestamptz,
 provider_reference text,
 last_error text
);
create index mme_security_incident_notifications_pending_idx on public.mme_security_incident_notifications(status,created_at);
create table public.mme_security_incident_tasks(
 task_id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_security_incidents(incident_id) on delete restrict,
 title text not null check(length(trim(title)) between 3 and 200),
 description text not null default '' check(length(description)<=4000),
 assigned_role text not null check(assigned_role in ('it_admin','cio','ceo','privacy_officer')),
 status text not null default 'open' check(status in ('open','in_progress','blocked','completed','cancelled')),
 due_at timestamptz,
 created_at timestamptz not null default now(),
 completed_at timestamptz,
 created_by uuid not null
);
alter table public.mme_security_incident_escalation_jobs enable row level security;
alter table public.mme_security_incident_notifications enable row level security;
alter table public.mme_security_incident_tasks enable row level security;
revoke all on public.mme_security_incident_escalation_jobs,public.mme_security_incident_notifications,public.mme_security_incident_tasks from public,anon,authenticated;
grant select,insert,update on public.mme_security_incident_escalation_jobs,public.mme_security_incident_notifications,public.mme_security_incident_tasks to service_role;

create or replace function public.mme_security_incident_schedule_escalation(p_incident uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare i public.mme_security_incidents%rowtype; p public.mme_security_incident_escalation_policies%rowtype; j uuid;
begin
 select * into i from public.mme_security_incidents where incident_id=p_incident;
 if not found then raise exception 'incident_not_found'; end if;
 if i.status in ('resolved','closed') then return null; end if;
 select * into p from public.mme_security_incident_escalation_policies where severity=i.severity and enabled;
 if not found then return null; end if;
 insert into public.mme_security_incident_escalation_jobs(incident_id,escalation_level,due_at)
 values(i.incident_id,1,coalesce(i.due_at,now()+make_interval(mins=>p.response_minutes)))
 on conflict(incident_id,escalation_level) do update set due_at=excluded.due_at,status='pending',attempts=0,last_error=null
 returning job_id into j;
 return j;
end $$;

create or replace function public.mme_security_incident_claim_due_jobs(p_limit integer default 25)
returns setof public.mme_security_incident_escalation_jobs
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query
 with due as (
  select j.job_id from public.mme_security_incident_escalation_jobs j
  join public.mme_security_incidents i on i.incident_id=j.incident_id
  where j.status='pending' and j.due_at<=now() and i.status not in ('resolved','closed')
  order by j.due_at for update of j skip locked limit greatest(1,least(p_limit,100))
 )
 update public.mme_security_incident_escalation_jobs j
 set status='claimed',claimed_at=now(),attempts=attempts+1
 from due where j.job_id=due.job_id returning j.*;
end $$;

create or replace function public.mme_security_incident_process_escalation(p_job uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.mme_security_incident_escalation_jobs%rowtype; i public.mme_security_incidents%rowtype; target text; next_due timestamptz; next_level integer;
begin
 select * into j from public.mme_security_incident_escalation_jobs where job_id=p_job for update;
 if not found or j.status<>'claimed' then raise exception 'job_not_claimed'; end if;
 select * into i from public.mme_security_incidents where incident_id=j.incident_id for update;
 if i.status in ('resolved','closed') then
  update public.mme_security_incident_escalation_jobs set status='cancelled',completed_at=now() where job_id=p_job;
  return jsonb_build_object('status','cancelled');
 end if;
 target:=case when i.severity='critical' then 'ceo;cio' when i.severity='high' then 'cio' else 'it_admin' end;
 insert into public.mme_security_incident_notifications(incident_id,recipient_role,notification_type,payload)
 select i.incident_id,trim(role),'escalation',jsonb_build_object('incident_id',i.incident_id,'severity',i.severity,'status',i.status,'due_at',i.due_at,'escalation_level',j.escalation_level)
 from unnest(string_to_array(target,';')) role
 on conflict do nothing;
 insert into public.mme_security_incident_tasks(incident_id,title,description,assigned_role,due_at,created_by)
 values(i.incident_id,'Escalated incident response: '||i.title,'Review overdue incident, acknowledge escalation and record next actions.',case when i.severity='critical' then 'ceo' when i.severity='high' then 'cio' else 'it_admin' end,now()+interval '15 minutes',i.created_by);
 update public.mme_security_incident_escalation_jobs set status='completed',completed_at=now() where job_id=p_job;
 return jsonb_build_object('status','escalated','incident_id',i.incident_id,'notify',target);
end $$;
revoke all on function public.mme_security_incident_schedule_escalation(uuid) from public,anon,authenticated;
revoke all on function public.mme_security_incident_claim_due_jobs(integer) from public,anon,authenticated;
revoke all on function public.mme_security_incident_process_escalation(uuid) from public,anon,authenticated;
grant execute on function public.mme_security_incident_schedule_escalation(uuid),public.mme_security_incident_claim_due_jobs(integer),public.mme_security_incident_process_escalation(uuid) to service_role;

create or replace function public.mme_security_incident_create_from_alert(p_alert uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.mme_security_integration_alerts%rowtype; i uuid; mins integer;
begin
 select * into a from public.mme_security_integration_alerts where alert_id=p_alert for update;
 if not found then raise exception 'alert_not_found'; end if;
 insert into public.mme_security_incidents(alert_id,source_system,title,description,severity,created_by,due_at)
 values(a.alert_id,a.source_system,'Security alert: '||a.policy_key,a.message,
 case a.severity when 'critical' then 'critical' when 'warning' then 'high' else 'medium' end,p_actor,
 now()+make_interval(mins=>(select response_minutes from public.mme_security_incident_escalation_policies where severity=case a.severity when 'critical' then 'critical' when 'warning' then 'high' else 'medium' end)))
 on conflict(alert_id) do update set alert_id=excluded.alert_id returning incident_id into i;
 perform public.mme_security_incident_schedule_escalation(i);
 insert into public.mme_security_incident_audit(incident_id,actor_user_id,action,after_state)
 values(i,p_actor,'created',jsonb_build_object('alert_id',a.alert_id,'source_system',a.source_system,'severity',a.severity))
 on conflict do nothing;
 return i;
end $$;
revoke all on function public.mme_security_incident_create_from_alert(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_security_incident_create_from_alert(uuid,uuid) to service_role;
commit;