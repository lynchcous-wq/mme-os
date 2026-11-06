-- Build 009.81: retention eligibility and controlled deletion worker RPCs
begin;
create or replace function public.mme_warranty_retention_enqueue_due(p_actor uuid,p_limit integer default 200) returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare r record; n integer:=0; k text;
begin
 if p_limit<1 or p_limit>1000 then raise exception 'invalid_batch_limit'; end if;
 for r in select rr.retention_record_id,rr.evidence_id,rr.policy_id,rr.policy_version,e.storage_object_reference from public.mme_warranty_evidence_retention_records rr join public.mme_warranty_claim_evidence e on e.evidence_id=rr.evidence_id where rr.retention_status='active' and rr.retain_until<=now() and not exists(select 1 from public.mme_warranty_evidence_legal_holds h where h.evidence_id=rr.evidence_id and h.hold_status='active') and not exists(select 1 from public.mme_warranty_evidence_retention_exceptions x where x.evidence_id=rr.evidence_id and x.status='approved' and x.expires_at>now()) order by rr.retain_until for update of rr skip locked limit p_limit loop
  k:=encode(digest(r.retention_record_id::text||':'||r.policy_version,'sha256'),'hex');
  insert into public.mme_warranty_evidence_deletion_jobs(evidence_id,retention_record_id,reason_code,object_key_digest,requested_by,idempotency_key) values(r.evidence_id,r.retention_record_id,'retention_expired',encode(digest(r.storage_object_reference,'sha256'),'hex'),p_actor,k) on conflict(idempotency_key) do nothing;
  update public.mme_warranty_evidence_retention_records set retention_status='deletion_queued',last_reviewed_at=now(),last_reviewed_by=p_actor where retention_record_id=r.retention_record_id;
  insert into public.mme_warranty_evidence_access_events(evidence_id,principal_id,principal_role,action,outcome,reason_code,source_reference,event_digest) values(r.evidence_id,p_actor,'service_worker','deletion_queued','recorded','retention_expired',r.retention_record_id::text,k); n:=n+1;
 end loop; return n; end $$;
create or replace function public.mme_warranty_retention_approve_deletion(p_job uuid,p_approver uuid) returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.mme_warranty_evidence_deletion_jobs%rowtype;
begin
 select * into j from public.mme_warranty_evidence_deletion_jobs where deletion_job_id=p_job for update;
 if j.deletion_job_id is null or j.status not in ('queued','blocked','failed') or j.requested_by=p_approver then raise exception 'approval_not_permitted'; end if;
 if exists(select 1 from public.mme_warranty_evidence_legal_holds where evidence_id=j.evidence_id and hold_status='active') or exists(select 1 from public.mme_warranty_evidence_retention_exceptions where evidence_id=j.evidence_id and status='approved' and expires_at>now()) then update public.mme_warranty_evidence_deletion_jobs set status='blocked' where deletion_job_id=p_job; return false; end if;
 if not exists(select 1 from public.mme_warranty_evidence_retention_records where retention_record_id=j.retention_record_id and retention_status='deletion_queued' and retain_until<=now()) then raise exception 'retention_not_eligible'; end if;
 update public.mme_warranty_evidence_deletion_jobs set status='approved',approved_by=p_approver,approved_at=now() where deletion_job_id=p_job; return true; end $$;
create or replace function public.mme_warranty_retention_claim_job(p_worker uuid,p_lease_seconds integer default 300) returns setof public.mme_warranty_evidence_deletion_jobs language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.mme_warranty_evidence_deletion_jobs%rowtype;
begin
 if p_lease_seconds<30 or p_lease_seconds>1800 then raise exception 'invalid_lease_duration'; end if;
 select * into j from public.mme_warranty_evidence_deletion_jobs where status='approved' order by created_at for update skip locked limit 1;
 if j.deletion_job_id is null then return; end if;
 if exists(select 1 from public.mme_warranty_evidence_legal_holds where evidence_id=j.evidence_id and hold_status='active') or exists(select 1 from public.mme_warranty_evidence_retention_exceptions where evidence_id=j.evidence_id and status='approved' and expires_at>now()) then update public.mme_warranty_evidence_deletion_jobs set status='blocked' where deletion_job_id=j.deletion_job_id; return; end if;
 update public.mme_warranty_evidence_deletion_jobs set status='processing',lease_token=gen_random_uuid(),lease_expires_at=now()+make_interval(secs=>p_lease_seconds) where deletion_job_id=j.deletion_job_id returning * into j; return next j; end $$;
create or replace function public.mme_warranty_retention_confirm_deleted(p_job uuid,p_lease uuid,p_worker uuid,p_storage_reference text,p_object_absent boolean) returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.mme_warranty_evidence_deletion_jobs%rowtype;
begin
 select * into j from public.mme_warranty_evidence_deletion_jobs where deletion_job_id=p_job for update;
 if j.deletion_job_id is null or j.status<>'processing' or j.lease_token is distinct from p_lease or j.lease_expires_at<now() then raise exception 'deletion_lease_invalid'; end if;
 if p_object_absent is not true or p_storage_reference is null or length(p_storage_reference)<1 then raise exception 'storage_absence_not_verified'; end if;
 if exists(select 1 from public.mme_warranty_evidence_legal_holds where evidence_id=j.evidence_id and hold_status='active') or exists(select 1 from public.mme_warranty_evidence_retention_exceptions where evidence_id=j.evidence_id and status='approved' and expires_at>now()) then update public.mme_warranty_evidence_deletion_jobs set status='blocked',lease_token=null,lease_expires_at=null where deletion_job_id=p_job; return false; end if;
 update public.mme_warranty_evidence_deletion_jobs set status='deleted',storage_delete_reference=p_storage_reference,verified_deleted_at=now(),lease_token=null,lease_expires_at=null where deletion_job_id=p_job;
 update public.mme_warranty_evidence_retention_records set retention_status='deleted',last_reviewed_at=now(),last_reviewed_by=p_worker where retention_record_id=j.retention_record_id;
 insert into public.mme_warranty_evidence_access_events(evidence_id,principal_id,principal_role,action,outcome,reason_code,source_reference,event_digest) values(j.evidence_id,p_worker,'service_worker','deletion_verified','recorded','storage_object_absent',p_job::text,encode(digest(p_storage_reference,'sha256'),'hex')); return true; end $$;
revoke all on function public.mme_warranty_retention_enqueue_due(uuid,integer) from public,anon,authenticated;
revoke all on function public.mme_warranty_retention_approve_deletion(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_warranty_retention_claim_job(uuid,integer) from public,anon,authenticated;
revoke all on function public.mme_warranty_retention_confirm_deleted(uuid,uuid,uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.mme_warranty_retention_enqueue_due(uuid,integer) to service_role;
grant execute on function public.mme_warranty_retention_approve_deletion(uuid,uuid) to service_role;
grant execute on function public.mme_warranty_retention_claim_job(uuid,integer) to service_role;
grant execute on function public.mme_warranty_retention_confirm_deleted(uuid,uuid,uuid,text,boolean) to service_role;
commit;