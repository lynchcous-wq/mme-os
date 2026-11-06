-- Build 009.79: evidence scanner attestation, quarantine and registration gates
begin;
alter table public.mme_warranty_evidence_scan_jobs
 add column if not exists file_sha256 text,
 add column if not exists detected_content_type text,
 add column if not exists detected_byte_size bigint,
 add column if not exists signature_valid boolean,
 add column if not exists malware_engine text,
 add column if not exists malware_definition_version text,
 add column if not exists attested_at timestamptz,
 add column if not exists failure_reason_code text;

alter table public.mme_warranty_evidence_upload_intents
 add column if not exists content_sha256 text,
 add column if not exists detected_content_type text,
 add column if not exists detected_byte_size bigint,
 add column if not exists scanner_attested_at timestamptz;

create table public.mme_warranty_evidence_scan_attestations (
 attestation_id uuid primary key default gen_random_uuid(),
 upload_intent_id uuid not null references public.mme_warranty_evidence_upload_intents(upload_intent_id) on delete restrict,
 scan_job_id uuid not null references public.mme_warranty_evidence_scan_jobs(scan_job_id) on delete restrict,
 content_sha256 text not null check(content_sha256 ~ '^[0-9a-f]{64}$'),
 detected_content_type text not null,
 detected_byte_size bigint not null check(detected_byte_size between 1 and 52428800),
 signature_valid boolean not null,
 malware_engine text not null,
 malware_engine_version text not null,
 malware_definition_version text not null,
 verdict text not null check(verdict in ('clean','infected','invalid','error')),
 result_code text not null,
 scanner_identity text not null,
 attested_at timestamptz not null default now(),
 idempotency_key text not null unique,
 unique(upload_intent_id,content_sha256,malware_engine_version,malware_definition_version)
);
create index mme_warranty_evidence_attestations_intent_idx on public.mme_warranty_evidence_scan_attestations(upload_intent_id,attested_at desc);

create table public.mme_warranty_evidence_duplicate_matches (
 duplicate_match_id uuid primary key default gen_random_uuid(),
 upload_intent_id uuid not null references public.mme_warranty_evidence_upload_intents(upload_intent_id) on delete restrict,
 matched_evidence_id uuid references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 matched_sha256 text not null check(matched_sha256 ~ '^[0-9a-f]{64}$'),
 match_scope text not null check(match_scope in ('same_claim','same_customer','global_security')),
 disposition text not null default 'review_required' check(disposition in ('review_required','confirmed_duplicate','false_positive','dismissed')),
 reviewed_by uuid, reviewed_at timestamptz, review_reason_code text,
 created_at timestamptz not null default now(),
 unique(upload_intent_id,matched_sha256,match_scope)
);

alter table public.mme_warranty_evidence_scan_attestations enable row level security;
alter table public.mme_warranty_evidence_duplicate_matches enable row level security;
revoke all on public.mme_warranty_evidence_scan_attestations,public.mme_warranty_evidence_duplicate_matches from public,anon,authenticated;
grant select,insert on public.mme_warranty_evidence_scan_attestations to service_role;
grant select,insert,update on public.mme_warranty_evidence_duplicate_matches to service_role;
revoke update,delete,truncate on public.mme_warranty_evidence_scan_attestations from public,anon,authenticated,service_role;

create or replace function public.mme_warranty_evidence_record_scan_attestation(
 p_upload_intent_id uuid,p_scan_job_id uuid,p_sha256 text,p_detected_type text,p_detected_size bigint,
 p_signature_valid boolean,p_engine text,p_engine_version text,p_definition_version text,
 p_verdict text,p_result_code text,p_scanner_identity text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_intent public.mme_warranty_evidence_upload_intents%rowtype; v_job public.mme_warranty_evidence_scan_jobs%rowtype; v_attestation uuid;
begin
 if p_sha256 !~ '^[0-9a-f]{64}$' or p_detected_size not between 1 and 52428800
   or p_verdict not in ('clean','infected','invalid','error') then
  raise exception 'invalid_scan_attestation' using errcode='22023';
 end if;
 select * into v_intent from public.mme_warranty_evidence_upload_intents where upload_intent_id=p_upload_intent_id for update;
 select * into v_job from public.mme_warranty_evidence_scan_jobs where scan_job_id=p_scan_job_id and upload_intent_id=p_upload_intent_id for update;
 if v_intent.upload_intent_id is null or v_job.scan_job_id is null or v_job.status<>'processing'
   or v_intent.status not in ('uploaded','quarantined','scanning') then
  raise exception 'scan_job_not_active' using errcode='55000';
 end if;
 if v_job.lease_expires_at<now() then raise exception 'scan_lease_expired' using errcode='55000'; end if;
 if p_verdict='clean' and (p_signature_valid is not true or p_detected_type not in ('image/jpeg','image/png','image/webp','application/pdf','video/mp4','video/quicktime','text/plain')) then
  p_verdict:='invalid'; p_result_code:='signature_or_type_rejected';
 end if;
 insert into public.mme_warranty_evidence_scan_attestations(upload_intent_id,scan_job_id,content_sha256,detected_content_type,detected_byte_size,signature_valid,malware_engine,malware_engine_version,malware_definition_version,verdict,result_code,scanner_identity,idempotency_key)
 values(p_upload_intent_id,p_scan_job_id,p_sha256,p_detected_type,p_detected_size,p_signature_valid,p_engine,p_engine_version,p_definition_version,p_verdict,p_result_code,p_scanner_identity,p_idempotency_key)
 on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key
 returning attestation_id into v_attestation;
 update public.mme_warranty_evidence_scan_jobs set status=case p_verdict when 'clean' then 'clean' when 'infected' then 'infected' else 'rejected' end,
  file_sha256=p_sha256,detected_content_type=p_detected_type,detected_byte_size=p_detected_size,
  signature_valid=p_signature_valid,scanner_name=p_engine,scanner_version=p_engine_version,
  malware_definition_version=p_definition_version,scan_result_code=p_result_code,scanned_at=now(),
  attested_at=now(),lease_token=null,lease_expires_at=null
 where scan_job_id=p_scan_job_id;
 update public.mme_warranty_evidence_upload_intents set
  status=case p_verdict when 'clean' then 'verified' when 'infected' then 'rejected' else 'quarantined' end,
  content_sha256=p_sha256,detected_content_type=p_detected_type,detected_byte_size=p_detected_size,
  scanner_attested_at=now()
 where upload_intent_id=p_upload_intent_id;
 return v_attestation;
end $$;

create or replace function public.mme_warranty_evidence_register_clean(p_upload_intent_id uuid,p_registration_key text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_intent public.mme_warranty_evidence_upload_intents%rowtype; v_evidence uuid;
begin
 select * into v_intent from public.mme_warranty_evidence_upload_intents where upload_intent_id=p_upload_intent_id for update;
 if v_intent.upload_intent_id is null or v_intent.status<>'verified' or v_intent.scanner_attested_at is null
  or v_intent.content_sha256 is null or v_intent.detected_byte_size is null then
  raise exception 'evidence_not_verified' using errcode='55000';
 end if;
 if exists(select 1 from public.mme_warranty_evidence_duplicate_matches d where d.upload_intent_id=p_upload_intent_id and d.disposition in ('review_required','confirmed_duplicate')) then
  raise exception 'duplicate_review_required' using errcode='55000';
 end if;
 insert into public.mme_warranty_claim_evidence(claim_id,evidence_type,storage_object_reference,content_sha256,content_type,byte_size,submitted_by,verification_status,idempotency_key)
 values(v_intent.claim_id,v_intent.evidence_type,v_intent.object_key,v_intent.content_sha256,v_intent.detected_content_type,v_intent.detected_byte_size,v_intent.created_by,'pending',p_registration_key)
 on conflict(idempotency_key) do nothing returning evidence_id into v_evidence;
 if v_evidence is null then select evidence_id into v_evidence from public.mme_warranty_claim_evidence where idempotency_key=p_registration_key; end if;
 update public.mme_warranty_evidence_upload_intents set status='registered' where upload_intent_id=p_upload_intent_id;
 insert into public.mme_warranty_evidence_upload_events(upload_intent_id,event_type,actor_reference,event_digest)
 values(p_upload_intent_id,'registered','trusted_scanner_pipeline',encode(digest(p_registration_key,'sha256'),'hex'));
 return v_evidence;
end $$;

revoke all on function public.mme_warranty_evidence_record_scan_attestation(uuid,uuid,text,text,bigint,boolean,text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_evidence_register_clean(uuid,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_evidence_record_scan_attestation(uuid,uuid,text,text,bigint,boolean,text,text,text,text,text,text,text) to service_role;
grant execute on function public.mme_warranty_evidence_register_clean(uuid,text) to service_role;
commit;