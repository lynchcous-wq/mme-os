begin;
create sequence if not exists public.mme_warranty_security_case_number_seq;
create table public.mme_warranty_security_cases (
 case_id uuid primary key default gen_random_uuid(),
 case_number text not null unique default ('WSC-'||to_char(now(),'YYYY')||'-'||lpad(nextval('public.mme_warranty_security_case_number_seq')::text,7,'0')),
 source_alert_id uuid unique references public.mme_warranty_api_security_alerts(alert_id) on delete restrict,
 title text not null check(length(trim(title)) between 5 and 180),
 summary text not null check(length(trim(summary)) between 10 and 4000),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','triage','investigating','pending_action','pending_approval','resolved','closed','reopened')),
 priority integer not null default 3 check(priority between 1 and 5),
 assigned_to uuid,
 assigned_role text,
 created_by uuid not null,
 resolution text,
 resolution_code text,
 opened_at timestamptz not null default now(),
 due_at timestamptz,
 resolved_at timestamptz,
 closed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((status in ('resolved','closed') and resolved_at is not null) or status not in ('resolved','closed'))
);
create index mme_warranty_security_cases_queue_idx on public.mme_warranty_security_cases(status,severity,due_at,created_at);
create table public.mme_warranty_security_case_events (
 event_id bigint generated always as identity primary key,case_id uuid not null references public.mme_warranty_security_cases(case_id) on delete restrict,
 event_type text not null,actor_id uuid,details jsonb not null default '{}'::jsonb,request_id uuid,occurred_at timestamptz not null default now()
);
create table public.mme_warranty_security_case_notes (
 note_id uuid primary key default gen_random_uuid(),case_id uuid not null references public.mme_warranty_security_cases(case_id) on delete restrict,
 author_id uuid not null,note text not null check(length(trim(note)) between 1 and 8000),visibility text not null default 'internal' check(visibility in ('internal','executive')),
 created_at timestamptz not null default now()
);
create table public.mme_warranty_security_case_evidence (
 evidence_id uuid primary key default gen_random_uuid(),case_id uuid not null references public.mme_warranty_security_cases(case_id) on delete restrict,
 uploaded_by uuid not null,storage_bucket text not null,storage_object_key text not null,file_name text not null check(length(file_name) between 1 and 255),
 content_type text not null,byte_size bigint not null check(byte_size between 1 and 52428800),sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 evidence_status text not null default 'registered' check(evidence_status in ('registered','quarantined','verified','rejected','retained')),
 created_at timestamptz not null default now(),unique(storage_bucket,storage_object_key)
);
create table public.mme_warranty_security_case_actions (
 action_id uuid primary key default gen_random_uuid(),case_id uuid not null references public.mme_warranty_security_cases(case_id) on delete restrict,
 title text not null check(length(trim(title)) between 3 and 180),description text not null check(length(trim(description)) between 1 and 3000),
 assigned_to uuid,due_at timestamptz,status text not null default 'open' check(status in ('open','in_progress','blocked','completed','cancelled')),
 completed_by uuid,completed_at timestamptz,created_by uuid not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['mme_warranty_security_cases','mme_warranty_security_case_events','mme_warranty_security_case_notes','mme_warranty_security_case_evidence','mme_warranty_security_case_actions'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.mme_warranty_security_case_number_seq to service_role;
create or replace function public.mme_warranty_security_case_create_from_alert(p_alert_id uuid,p_actor_id uuid,p_request_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.mme_warranty_api_security_alerts%rowtype; c uuid;
begin
 select * into a from public.mme_warranty_api_security_alerts where alert_id=p_alert_id for update;
 if not found then raise exception 'alert_not_found'; end if;
 insert into public.mme_warranty_security_cases(source_alert_id,title,summary,severity,priority,created_by)
 values(a.alert_id,a.title,a.message,a.severity,case a.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,p_actor_id)
 on conflict(source_alert_id) do update set source_alert_id=excluded.source_alert_id returning case_id into c;
 insert into public.mme_warranty_security_case_events(case_id,event_type,actor_id,details,request_id)
 values(c,'case_created_from_alert',p_actor_id,jsonb_build_object('alertId',p_alert_id),p_request_id);
 return c;
end $$;
revoke all on function public.mme_warranty_security_case_create_from_alert(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_security_case_create_from_alert(uuid,uuid,uuid) to service_role;
commit;