begin;
create table public.mme_warranty_api_security_investigation_cases (
 case_id uuid primary key default gen_random_uuid(),
 case_number bigint generated always as identity unique,
 incident_id uuid not null references public.mme_warranty_api_security_incidents(incident_id) on delete restrict,
 title text not null,
 summary text not null default '',
 status text not null default 'open' check(status in ('open','triage','investigating','pending_review','closed','cancelled')),
 priority text not null default 'medium' check(priority in ('low','medium','high','critical')),
 lead_investigator_id uuid,
 opened_by uuid not null,
 opened_at timestamptz not null default now(),
 due_at timestamptz,
 closed_by uuid,
 closed_at timestamptz,
 closure_code text,
 updated_at timestamptz not null default now(),
 unique(incident_id),
 check((status not in ('closed','cancelled')) or closed_at is not null)
);
create index mme_warranty_security_cases_queue_idx on public.mme_warranty_api_security_investigation_cases(status,priority,due_at);
create table public.mme_warranty_api_security_case_notes (
 note_id bigint generated always as identity primary key,
 case_id uuid not null references public.mme_warranty_api_security_investigation_cases(case_id) on delete restrict,
 author_id uuid not null,
 note_type text not null check(note_type in ('investigation','decision','handoff','closure')),
 body text not null check(length(body) between 1 and 10000),
 created_at timestamptz not null default now()
);
create table public.mme_warranty_api_security_case_evidence (
 evidence_id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_warranty_api_security_investigation_cases(case_id) on delete restrict,
 evidence_type text not null check(evidence_type in ('document','image','video','log','transaction','device','other')),
 storage_bucket text not null,
 storage_path text not null,
 original_filename text,
 content_type text,
 byte_size bigint check(byte_size is null or byte_size>=0),
 sha256_hex text not null check(sha256_hex ~ '^[0-9a-f]{64}$'),
 collected_by uuid not null,
 collected_at timestamptz not null default now(),
 description text not null default '',
 unique(storage_bucket,storage_path)
);
create table public.mme_warranty_api_security_evidence_custody (
 custody_id bigint generated always as identity primary key,
 evidence_id uuid not null references public.mme_warranty_api_security_case_evidence(evidence_id) on delete restrict,
 from_custodian uuid,
 to_custodian uuid not null,
 transferred_by uuid not null,
 transfer_reason text not null check(length(transfer_reason) between 1 and 1000),
 evidence_sha256_hex text not null check(evidence_sha256_hex ~ '^[0-9a-f]{64}$'),
 transferred_at timestamptz not null default now()
);
create table public.mme_warranty_api_security_case_events (
 event_id bigint generated always as identity primary key,
 case_id uuid not null references public.mme_warranty_api_security_investigation_cases(case_id) on delete restrict,
 actor_id uuid not null,
 event_type text not null check(event_type in ('case_created','assigned','status_changed','priority_changed','due_date_changed','evidence_added','custody_transferred','note_added','closed','reopened')),
 reason_code text not null,
 details jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default now()
);
alter table public.mme_warranty_api_security_investigation_cases enable row level security;
alter table public.mme_warranty_api_security_case_notes enable row level security;
alter table public.mme_warranty_api_security_case_evidence enable row level security;
alter table public.mme_warranty_api_security_evidence_custody enable row level security;
alter table public.mme_warranty_api_security_case_events enable row level security;
revoke all on public.mme_warranty_api_security_investigation_cases,public.mme_warranty_api_security_case_notes,public.mme_warranty_api_security_case_evidence,public.mme_warranty_api_security_evidence_custody,public.mme_warranty_api_security_case_events from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_investigation_cases to service_role;
grant select,insert on public.mme_warranty_api_security_case_notes,public.mme_warranty_api_security_case_evidence,public.mme_warranty_api_security_evidence_custody,public.mme_warranty_api_security_case_events to service_role;
revoke update,delete,truncate on public.mme_warranty_api_security_case_notes,public.mme_warranty_api_security_evidence_custody,public.mme_warranty_api_security_case_events from public,anon,authenticated,service_role;
create or replace function public.mme_warranty_api_security_case_create(p_incident_id uuid,p_title text,p_summary text,p_priority text,p_actor_id uuid,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_case uuid;
begin
 if p_title is null or length(trim(p_title)) not between 3 and 200 then raise exception 'invalid_case_title'; end if;
 if p_priority not in ('low','medium','high','critical') then raise exception 'invalid_case_priority'; end if;
 if not exists(select 1 from public.mme_warranty_api_security_incidents where incident_id=p_incident_id) then raise exception 'incident_not_found'; end if;
 insert into public.mme_warranty_api_security_investigation_cases(incident_id,title,summary,priority,opened_by,due_at)
 values(p_incident_id,trim(p_title),left(coalesce(p_summary,''),5000),p_priority,p_actor_id,p_due_at)
 returning case_id into v_case;
 insert into public.mme_warranty_api_security_case_events(case_id,actor_id,event_type,reason_code)
 values(v_case,p_actor_id,'case_created','investigation_case_opened');
 return v_case;
end $$;
create or replace function public.mme_warranty_api_security_case_assign(p_case_id uuid,p_investigator_id uuid,p_actor_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 update public.mme_warranty_api_security_investigation_cases set lead_investigator_id=p_investigator_id,updated_at=now() where case_id=p_case_id and status not in ('closed','cancelled');
 if not found then raise exception 'active_case_not_found'; end if;
 insert into public.mme_warranty_api_security_case_events(case_id,actor_id,event_type,reason_code,details)
 values(p_case_id,p_actor_id,'assigned','investigator_assigned',jsonb_build_object('investigator_id',p_investigator_id,'reason',left(coalesce(p_reason,''),500)));
end $$;
create or replace function public.mme_warranty_api_security_case_add_note(p_case_id uuid,p_actor_id uuid,p_note_type text,p_body text)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare v_note bigint;
begin
 if p_note_type not in ('investigation','decision','handoff','closure') or p_body is null or length(trim(p_body)) not between 1 and 10000 then raise exception 'invalid_case_note'; end if;
 if not exists(select 1 from public.mme_warranty_api_security_investigation_cases where case_id=p_case_id and status not in ('closed','cancelled')) then raise exception 'active_case_not_found'; end if;
 insert into public.mme_warranty_api_security_case_notes(case_id,author_id,note_type,body) values(p_case_id,p_actor_id,p_note_type,trim(p_body)) returning note_id into v_note;
 insert into public.mme_warranty_api_security_case_events(case_id,actor_id,event_type,reason_code,details)
 values(p_case_id,p_actor_id,'note_added','investigation_note_added',jsonb_build_object('note_id',v_note,'note_type',p_note_type));
 return v_note;
end $$;
create or replace function public.mme_warranty_api_security_case_add_evidence(p_case_id uuid,p_actor_id uuid,p_evidence_type text,p_bucket text,p_path text,p_filename text,p_content_type text,p_byte_size bigint,p_sha256 text,p_description text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if p_evidence_type not in ('document','image','video','log','transaction','device','other') or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid_evidence_metadata'; end if;
 if p_bucket is null or p_path is null or p_path like '/%' or p_path like '%..%' then raise exception 'invalid_evidence_storage_reference'; end if;
 if not exists(select 1 from public.mme_warranty_api_security_investigation_cases where case_id=p_case_id and status not in ('closed','cancelled')) then raise exception 'active_case_not_found'; end if;
 insert into public.mme_warranty_api_security_case_evidence(case_id,evidence_type,storage_bucket,storage_path,original_filename,content_type,byte_size,sha256_hex,collected_by,description)
 values(p_case_id,p_evidence_type,p_bucket,p_path,left(p_filename,255),left(p_content_type,120),p_byte_size,p_sha256,p_actor_id,left(coalesce(p_description,''),2000))
 returning evidence_id into v_id;
 insert into public.mme_warranty_api_security_case_events(case_id,actor_id,event_type,reason_code,details)
 values(p_case_id,p_actor_id,'evidence_added','evidence_metadata_registered',jsonb_build_object('evidence_id',v_id,'evidence_type',p_evidence_type,'sha256',p_sha256));
 return v_id;
end $$;
create or replace function public.mme_warranty_api_security_case_transfer_custody(p_evidence_id uuid,p_from uuid,p_to uuid,p_actor_id uuid,p_reason text,p_sha256 text)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id bigint; v_case uuid; v_hash text;
begin
 select case_id,sha256_hex into v_case,v_hash from public.mme_warranty_api_security_case_evidence where evidence_id=p_evidence_id;
 if not found then raise exception 'evidence_not_found'; end if;
 if p_sha256<>v_hash or p_reason is null or length(trim(p_reason)) not between 1 and 1000 then raise exception 'custody_integrity_validation_failed'; end if;
 if p_from is not null and not exists(select 1 from public.mme_warranty_api_security_evidence_custody where evidence_id=p_evidence_id and to_custodian=p_from) and (select collected_by from public.mme_warranty_api_security_case_evidence where evidence_id=p_evidence_id)<>p_from then raise exception 'custodian_mismatch'; end if;
 insert into public.mme_warranty_api_security_evidence_custody(evidence_id,from_custodian,to_custodian,transferred_by,transfer_reason,evidence_sha256_hex)
 values(p_evidence_id,p_from,p_to,p_actor_id,trim(p_reason),p_sha256) returning custody_id into v_id;
 insert into public.mme_warranty_api_security_case_events(case_id,actor_id,event_type,reason_code,details)
 values(v_case,p_actor_id,'custody_transferred','evidence_custody_transfer',jsonb_build_object('evidence_id',p_evidence_id,'from',p_from,'to',p_to,'custody_id',v_id));
 return v_id;
end $$;
create or replace function public.mme_warranty_api_security_case_set_status(p_case_id uuid,p_status text,p_actor_id uuid,p_reason text,p_closure_code text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_old text;
begin
 if p_status not in ('open','triage','investigating','pending_review','closed','cancelled') then raise exception 'invalid_case_status'; end if;
 select status into v_old from public.mme_warranty_api_security_investigation_cases where case_id=p_case_id for update;
 if not found then raise exception 'case_not_found'; end if;
 if v_old in ('closed','cancelled') then raise exception 'case_already_closed'; end if;
 if p_status in ('closed','cancelled') and (p_closure_code is null or length(trim(p_closure_code))<3) then raise exception 'closure_approval_reason_required'; end if;
 update public.mme_warranty_api_security_investigation_cases set status=p_status,closed_by=case when p_status in ('closed','cancelled') then p_actor_id else null end,closed_at=case when p_status in ('closed','cancelled') then now() else null end,closure_code=case when p_status in ('closed','cancelled') then left(p_closure_code,100) else null end,updated_at=now() where case_id=p_case_id;
 insert into public.mme_warranty_api_security_case_events(case_id,actor_id,event_type,reason_code,details)
 values(p_case_id,p_actor_id,case when p_status in ('closed','cancelled') then 'closed' when v_old='closed' then 'reopened' else 'status_changed' end,'case_status_transition',jsonb_build_object('from',v_old,'to',p_status,'reason',left(coalesce(p_reason,''),500)));
end $$;
do $$ declare f record; begin
 for f in select p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'mme_warranty_api_security_case_%' loop
  execute format('revoke all on function public.%I(%s) from public,anon,authenticated',f.proname,f.args);
  execute format('grant execute on function public.%I(%s) to service_role',f.proname,f.args);
 end loop;
end $$;
commit;