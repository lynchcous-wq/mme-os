-- Build 009.80: warranty evidence retention, legal hold and controlled access
begin;
create table public.mme_warranty_evidence_retention_policies (
 policy_id uuid primary key default gen_random_uuid(),
 policy_code text not null unique,
 evidence_type text not null check(evidence_type in ('receipt','product_photo','damage_photo','video','diagnostic','serial_verification','purchase_verification','other','*')),
 retention_days integer not null check(retention_days between 1 and 36500),
 effective_from timestamptz not null,
 effective_until timestamptz,
 legal_basis_code text not null,
 policy_version text not null,
 enabled boolean not null default true,
 created_by uuid not null,
 created_at timestamptz not null default now(),
 check(effective_until is null or effective_until>effective_from)
);
create index mme_warranty_evidence_retention_policy_active_idx on public.mme_warranty_evidence_retention_policies(evidence_type,effective_from desc) where enabled;

create table public.mme_warranty_evidence_retention_records (
 retention_record_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null unique references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 upload_intent_id uuid references public.mme_warranty_evidence_upload_intents(upload_intent_id) on delete restrict,
 policy_id uuid not null references public.mme_warranty_evidence_retention_policies(policy_id) on delete restrict,
 policy_version text not null,
 retained_from timestamptz not null default now(),
 retain_until timestamptz not null,
 retention_status text not null default 'active' check(retention_status in ('active','legal_hold','eligible_for_deletion','deletion_queued','deleted','exception')),
 last_reviewed_at timestamptz,
 last_reviewed_by uuid,
 created_at timestamptz not null default now(),
 check(retain_until>retained_from)
);
create index mme_warranty_evidence_retention_due_idx on public.mme_warranty_evidence_retention_records(retain_until,retention_status);

create table public.mme_warranty_evidence_legal_holds (
 legal_hold_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 hold_reference text not null,
 hold_reason_code text not null,
 hold_status text not null default 'active' check(hold_status in ('active','released')),
 placed_by uuid not null,
 placed_at timestamptz not null default now(),
 released_by uuid,
 released_at timestamptz,
 release_reason_code text,
 check((hold_status='active' and released_at is null and released_by is null) or (hold_status='released' and released_at is not null and released_by is not null))
);
create index mme_warranty_evidence_legal_holds_active_idx on public.mme_warranty_evidence_legal_holds(evidence_id) where hold_status='active';

create table public.mme_warranty_evidence_access_grants (
 access_grant_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 principal_id uuid not null,
 principal_role text not null check(principal_role in ('customer','support','warranty_specialist','manager','privacy_officer','ceo','service_worker')),
 permission text not null check(permission in ('view_metadata','view_file','download_file','review_evidence')),
 granted_by uuid not null,
 grant_reason_code text not null,
 starts_at timestamptz not null default now(),
 expires_at timestamptz not null,
 revoked_at timestamptz,
 revoked_by uuid,
 check(expires_at>starts_at),
 check((revoked_at is null and revoked_by is null) or (revoked_at is not null and revoked_by is not null))
);
create index mme_warranty_evidence_access_grants_active_idx on public.mme_warranty_evidence_access_grants(evidence_id,principal_id,permission,expires_at) where revoked_at is null;

create table public.mme_warranty_evidence_access_events (
 access_event_id bigint generated always as identity primary key,
 evidence_id uuid not null references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 principal_id uuid,
 principal_role text,
 action text not null check(action in ('metadata_view','file_view','download_authorized','download_denied','grant_created','grant_revoked','legal_hold_placed','legal_hold_released','retention_review','deletion_queued','deletion_blocked','deletion_verified')),
 outcome text not null check(outcome in ('allowed','denied','recorded')),
 reason_code text not null,
 source_reference text not null,
 event_digest text not null,
 occurred_at timestamptz not null default now()
);
create index mme_warranty_evidence_access_events_timeline_idx on public.mme_warranty_evidence_access_events(evidence_id,occurred_at desc);

create table public.mme_warranty_evidence_deletion_jobs (
 deletion_job_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 retention_record_id uuid not null references public.mme_warranty_evidence_retention_records(retention_record_id) on delete restrict,
 status text not null default 'queued' check(status in ('queued','blocked','approved','processing','deleted','failed','cancelled')),
 reason_code text not null,
 object_key_digest text not null,
 requested_by uuid not null,
 approved_by uuid,
 approved_at timestamptz,
 lease_token uuid,
 lease_expires_at timestamptz,
 storage_delete_reference text,
 verified_deleted_at timestamptz,
 failure_code text,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>requested_by),
 check((status='processing')=(lease_token is not null and lease_expires_at is not null)),
 check(status<>'deleted' or verified_deleted_at is not null)
);
create index mme_warranty_evidence_deletion_queue_idx on public.mme_warranty_evidence_deletion_jobs(status,created_at) where status in ('queued','approved','failed');

create table public.mme_warranty_evidence_retention_exceptions (
 exception_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 exception_code text not null,
 rationale text not null,
 requested_by uuid not null,
 approved_by uuid,
 approved_at timestamptz,
 expires_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','expired','revoked')),
 idempotency_key text not null unique,
 check(approved_by is null or approved_by<>requested_by)
);

do $$ declare t text; begin foreach t in array array[
'mme_warranty_evidence_retention_policies','mme_warranty_evidence_retention_records','mme_warranty_evidence_legal_holds','mme_warranty_evidence_access_grants','mme_warranty_evidence_access_events','mme_warranty_evidence_deletion_jobs','mme_warranty_evidence_retention_exceptions'
] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from public,anon,authenticated',t); end loop; end $$;
grant select,insert,update on public.mme_warranty_evidence_retention_policies,public.mme_warranty_evidence_retention_records,public.mme_warranty_evidence_legal_holds,public.mme_warranty_evidence_access_grants,public.mme_warranty_evidence_deletion_jobs,public.mme_warranty_evidence_retention_exceptions to service_role;
grant select,insert on public.mme_warranty_evidence_access_events to service_role;
revoke update,delete,truncate on public.mme_warranty_evidence_access_events from public,anon,authenticated,service_role;
revoke delete,truncate on public.mme_warranty_evidence_legal_holds,public.mme_warranty_evidence_deletion_jobs from public,anon,authenticated,service_role;
commit;