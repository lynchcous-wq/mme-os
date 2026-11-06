begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('mme-security-evidence-quarantine','mme-security-evidence-quarantine',false,26214400,array['application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv','application/json','video/mp4'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
alter table public.mme_warranty_api_security_case_evidence
 add column if not exists ingestion_status text not null default 'pending_scan' check(ingestion_status in ('pending_scan','clean','quarantined','rejected','scan_error')),
 add column if not exists scanner_name text,
 add column if not exists scanned_at timestamptz,
 add column if not exists scan_result_code text,
 add column if not exists uploaded_at timestamptz not null default now();
create table public.mme_warranty_api_security_evidence_scan_jobs(
 job_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null unique references public.mme_warranty_api_security_case_evidence(evidence_id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','processing','clean','quarantined','rejected','failed')),
 attempt_count integer not null default 0 check(attempt_count between 0 and 5),
 next_attempt_at timestamptz not null default now(),
 scanner_name text,
 result_code text,
 last_error_code text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_warranty_evidence_scan_due_idx on public.mme_warranty_api_security_evidence_scan_jobs(next_attempt_at,created_at) where status in ('pending','failed');
alter table public.mme_warranty_api_security_evidence_scan_jobs enable row level security;
revoke all on public.mme_warranty_api_security_evidence_scan_jobs from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_evidence_scan_jobs to service_role;
create or replace function public.mme_warranty_api_security_evidence_register_upload(p_case_id uuid,p_actor_id uuid,p_evidence_type text,p_bucket text,p_path text,p_filename text,p_content_type text,p_byte_size bigint,p_sha256 text,p_description text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if p_bucket<>'mme-security-evidence-quarantine' then raise exception 'invalid_evidence_bucket'; end if;
 if p_path is null or p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}$' then raise exception 'invalid_evidence_path'; end if;
 v_id:=public.mme_warranty_api_security_case_add_evidence(p_case_id,p_actor_id,p_evidence_type,p_bucket,p_path,p_filename,p_content_type,p_byte_size,p_sha256,p_description);
 insert into public.mme_warranty_api_security_evidence_scan_jobs(evidence_id) values(v_id);
 return v_id;
end $$;
create or replace function public.mme_warranty_api_security_evidence_claim_scan_jobs(p_batch_size integer default 20)
returns table(job_id uuid,evidence_id uuid,storage_bucket text,storage_path text,sha256_hex text,content_type text,byte_size bigint)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_batch_size<1 or p_batch_size>100 then raise exception 'invalid_batch_size'; end if;
 return query with due as (
  select j.job_id from public.mme_warranty_api_security_evidence_scan_jobs j
  where j.status in ('pending','failed') and j.next_attempt_at<=now() and j.attempt_count<5
  order by j.next_attempt_at,j.created_at for update skip locked limit p_batch_size
 ), claimed as (
  update public.mme_warranty_api_security_evidence_scan_jobs j set status='processing',attempt_count=j.attempt_count+1,updated_at=now()
  from due where j.job_id=due.job_id returning j.job_id,j.evidence_id
 )
 select c.job_id,e.evidence_id,e.storage_bucket,e.storage_path,e.sha256_hex,e.content_type,e.byte_size
 from claimed c join public.mme_warranty_api_security_case_evidence e on e.evidence_id=c.evidence_id;
end $$;
create or replace function public.mme_warranty_api_security_evidence_finish_scan(p_job_id uuid,p_outcome text,p_scanner_name text,p_result_code text,p_error_code text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v record; v_status text;
begin
 if p_outcome not in ('clean','quarantined','rejected','failed') then raise exception 'invalid_scan_outcome'; end if;
 select j.job_id,j.status,j.attempt_count,j.evidence_id into v from public.mme_warranty_api_security_evidence_scan_jobs j where j.job_id=p_job_id for update;
 if not found or v.status<>'processing' then raise exception 'scan_job_not_processing'; end if;
 v_status:=case when p_outcome='failed' and v.attempt_count<5 then 'failed' else p_outcome end;
 update public.mme_warranty_api_security_evidence_scan_jobs set status=v_status,scanner_name=left(p_scanner_name,100),result_code=left(p_result_code,100),last_error_code=left(p_error_code,100),next_attempt_at=case when v_status='failed' then now()+make_interval(mins=>least(360,5*(2^least(v.attempt_count,6))::integer)) else next_attempt_at end,updated_at=now() where job_id=p_job_id;
 update public.mme_warranty_api_security_case_evidence set ingestion_status=case when v_status='failed' then 'scan_error' else v_status end,scanner_name=left(p_scanner_name,100),scanned_at=now(),scan_result_code=left(coalesce(p_result_code,p_error_code,'unknown'),100) where evidence_id=v.evidence_id;
end $$;
revoke all on function public.mme_warranty_api_security_evidence_register_upload(uuid,uuid,text,text,text,text,text,bigint,text,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_api_security_evidence_claim_scan_jobs(integer) from public,anon,authenticated;
revoke all on function public.mme_warranty_api_security_evidence_finish_scan(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_evidence_register_upload(uuid,uuid,text,text,text,text,text,bigint,text,text),public.mme_warranty_api_security_evidence_claim_scan_jobs(integer),public.mme_warranty_api_security_evidence_finish_scan(uuid,text,text,text,text) to service_role;
commit;