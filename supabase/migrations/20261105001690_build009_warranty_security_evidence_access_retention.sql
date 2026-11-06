begin;
create table public.mme_warranty_api_security_evidence_retention_policies (
 policy_id uuid primary key default gen_random_uuid(),
 evidence_type text not null unique check(evidence_type in ('document','image','video','log','transaction','device','other')),
 retention_days integer not null check(retention_days between 1 and 36500),
 legal_hold_required boolean not null default false,
 enabled boolean not null default true,
 updated_by uuid not null,
 updated_at timestamptz not null default now()
);
create table public.mme_warranty_api_security_evidence_legal_holds (
 hold_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null references public.mme_warranty_api_security_case_evidence(evidence_id) on delete restrict,
 hold_reason text not null check(length(trim(hold_reason)) between 5 and 2000),
 placed_by uuid not null,
 placed_at timestamptz not null default now(),
 released_by uuid,
 released_at timestamptz,
 release_reason text,
 check((released_at is null and released_by is null) or (released_at is not null and released_by is not null and length(trim(coalesce(release_reason,'')))>=5)
);
create unique index mme_security_evidence_one_active_hold on public.mme_warranty_api_security_evidence_legal_holds(evidence_id) where released_at is null;
create table public.mme_warranty_api_security_evidence_access_events (
 access_id bigint generated always as identity primary key,
 evidence_id uuid not null references public.mme_warranty_api_security_case_evidence(evidence_id) on delete restrict,
 actor_id uuid not null,
 action text not null check(action in ('download_granted','download_denied','metadata_viewed','hold_placed','hold_released','retention_deleted','retention_skipped')) ,
 reason_code text not null,
 request_id uuid not null,
 occurred_at timestamptz not null default now()
);
create table public.mme_warranty_api_security_evidence_retention_jobs (
 job_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null unique references public.mme_warranty_api_security_case_evidence(evidence_id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','processing','deleted','held','failed')),
 due_at timestamptz not null,
 attempt_count integer not null default 0 check(attempt_count between 0 and 5),
 last_error text,
 updated_at timestamptz not null default now()
);
create index mme_security_evidence_retention_due on public.mme_warranty_api_security_evidence_retention_jobs(due_at) where status in ('pending','failed');
alter table public.mme_warranty_api_security_evidence_retention_policies enable row level security;
alter table public.mme_warranty_api_security_evidence_legal_holds enable row level security;
alter table public.mme_warranty_api_security_evidence_access_events enable row level security;
alter table public.mme_warranty_api_security_evidence_retention_jobs enable row level security;
revoke all on public.mme_warranty_api_security_evidence_retention_policies,public.mme_warranty_api_security_evidence_legal_holds,public.mme_warranty_api_security_evidence_access_events,public.mme_warranty_api_security_evidence_retention_jobs from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_evidence_retention_policies,public.mme_warranty_api_security_evidence_legal_holds to service_role;
grant select,insert,update on public.mme_warranty_api_security_evidence_access_events,public.mme_warranty_api_security_evidence_retention_jobs to service_role;
create or replace function public.mme_warranty_api_security_evidence_authorize_download(p_evidence_id uuid,p_actor_id uuid,p_roles text[],p_request_id uuid)
returns table(allowed boolean,storage_bucket text,storage_path text,content_type text,original_filename text,byte_size bigint)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.mme_warranty_api_security_case_evidence%rowtype; v_allowed boolean:=false; v_reason text:='access_denied';
begin
 select * into v from public.mme_warranty_api_security_case_evidence where evidence_id=p_evidence_id;
 if not found then raise exception 'evidence_not_found'; end if;
 if v.ingestion_status<>'clean' then v_reason:='evidence_not_clean';
 elsif exists(select 1 from public.mme_warranty_api_security_evidence_legal_holds h where h.evidence_id=p_evidence_id and h.released_at is null) then v_reason:='legal_hold_active';
 elsif 'ceo'=any(coalesce(p_roles,'{}'::text[])) or 'privacy_officer'=any(coalesce(p_roles,'{}'::text[])) then v_allowed:=true;v_reason:='privileged_role';
 elsif 'manager'=any(coalesce(p_roles,'{}'::text[])) and exists(select 1 from public.mme_warranty_api_security_investigation_cases c where c.case_id=v.case_id and (c.lead_investigator_id=p_actor_id or c.opened_by=p_actor_id)) then v_allowed:=true;v_reason:='assigned_case_access';
 end if;
 insert into public.mme_warranty_api_security_evidence_access_events(evidence_id,actor_id,action,reason_code,request_id) values(p_evidence_id,p_actor_id,case when v_allowed then 'download_granted' else 'download_denied' end,v_reason,p_request_id);
 if v_allowed then return query select true,v.storage_bucket,v.storage_path,v.content_type,v.original_filename,v.byte_size; else return query select false,null::text,null::text,null::text,null::text,null::bigint; end if;
end $$;
create or replace function public.mme_warranty_api_security_evidence_place_hold(p_evidence_id uuid,p_actor_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if p_reason is null or length(trim(p_reason)) not between 5 and 2000 then raise exception 'legal_hold_reason_required'; end if;
 insert into public.mme_warranty_api_security_evidence_legal_holds(evidence_id,hold_reason,placed_by) values(p_evidence_id,trim(p_reason),p_actor_id) returning hold_id into v_id;
 insert into public.mme_warranty_api_security_evidence_access_events(evidence_id,actor_id,action,reason_code,request_id) values(p_evidence_id,p_actor_id,'hold_placed','legal_hold_created',gen_random_uuid());
 return v_id;
end $$;
create or replace function public.mme_warranty_api_security_evidence_release_hold(p_hold_id uuid,p_actor_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_evidence uuid;
begin
 if p_reason is null or length(trim(p_reason))<5 then raise exception 'legal_hold_release_reason_required'; end if;
 update public.mme_warranty_api_security_evidence_legal_holds set released_by=p_actor_id,released_at=now(),release_reason=left(trim(p_reason),2000) where hold_id=p_hold_id and released_at is null returning evidence_id into v_evidence;
 if not found then raise exception 'active_legal_hold_not_found'; end if;
 insert into public.mme_warranty_api_security_evidence_access_events(evidence_id,actor_id,action,reason_code,request_id) values(v_evidence,p_actor_id,'hold_released','legal_hold_released',gen_random_uuid());
end $$;
create or replace function public.mme_warranty_api_security_evidence_claim_retention_jobs(p_batch_size integer default 25)
returns table(job_id uuid,evidence_id uuid,storage_bucket text,storage_path text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query with due as (select j.job_id from public.mme_warranty_api_security_evidence_retention_jobs j where j.status in ('pending','failed') and j.due_at<=now() and j.attempt_count<5 and not exists(select 1 from public.mme_warranty_api_security_evidence_legal_holds h where h.evidence_id=j.evidence_id and h.released_at is null) order by j.due_at for update skip locked limit greatest(1,least(p_batch_size,100))), claimed as (update public.mme_warranty_api_security_evidence_retention_jobs j set status='processing',attempt_count=j.attempt_count+1,updated_at=now() from due where j.job_id=due.job_id returning j.job_id,j.evidence_id) select c.job_id,e.evidence_id,e.storage_bucket,e.storage_path from claimed c join public.mme_warranty_api_security_case_evidence e on e.evidence_id=c.evidence_id;
end $$;
create or replace function public.mme_warranty_api_security_evidence_finish_retention(p_job_id uuid,p_deleted boolean,p_error text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v record;
begin
 select j.job_id,j.evidence_id,j.status,j.attempt_count,e.storage_bucket,e.storage_path into v from public.mme_warranty_api_security_evidence_retention_jobs j join public.mme_warranty_api_security_case_evidence e on e.evidence_id=j.evidence_id where j.job_id=p_job_id for update of j;
 if not found or v.status<>'processing' then raise exception 'retention_job_not_processing'; end if;
 if exists(select 1 from public.mme_warranty_api_security_evidence_legal_holds h where h.evidence_id=v.evidence_id and h.released_at is null) then update public.mme_warranty_api_security_evidence_retention_jobs set status='held',updated_at=now() where job_id=p_job_id; return; end if;
 update public.mme_warranty_api_security_evidence_retention_jobs set status=case when p_deleted then 'deleted' when v.attempt_count>=5 then 'failed' else 'failed' end,last_error=left(p_error,200),updated_at=now() where job_id=p_job_id;
 if p_deleted then insert into public.mme_warranty_api_security_evidence_access_events(evidence_id,actor_id,action,reason_code,request_id) values(v.evidence_id,'00000000-0000-0000-0000-000000000000','retention_deleted','retention_policy_expired',gen_random_uuid()); end if;
end $$;
do $$ declare f record; begin for f in select p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'mme_warranty_api_security_evidence_%' loop execute format('revoke all on function public.%I(%s) from public,anon,authenticated',f.proname,f.args); execute format('grant execute on function public.%I(%s) to service_role',f.proname,f.args); end loop; end $$;
commit;