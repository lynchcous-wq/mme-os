-- Build 009.78: private evidence upload intents and scan pipeline
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('mme-warranty-evidence','mme-warranty-evidence',false,52428800,
 array['image/jpeg','image/png','image/webp','application/pdf','video/mp4','video/quicktime','text/plain'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create table public.mme_warranty_evidence_upload_intents (
 upload_intent_id uuid primary key default gen_random_uuid(),
 claim_id uuid not null references public.mme_warranty_claim_cases(claim_id) on delete restrict,
 customer_identity_id uuid not null,
 evidence_type text not null check(evidence_type in ('receipt','product_photo','damage_photo','video','diagnostic','serial_verification','purchase_verification','other')),
 object_key text not null unique,
 original_filename text not null,
 declared_content_type text not null,
 declared_byte_size bigint not null check(declared_byte_size between 1 and 52428800),
 status text not null default 'reserved' check(status in ('reserved','uploaded','quarantined','scanning','verified','rejected','expired','registered')),
 expires_at timestamptz not null,
 created_at timestamptz not null default now(),
 created_by uuid not null,
 idempotency_key text not null unique
);
create index mme_warranty_evidence_upload_intents_claim_idx on public.mme_warranty_evidence_upload_intents(claim_id,created_at desc);
create index mme_warranty_evidence_upload_intents_expiry_idx on public.mme_warranty_evidence_upload_intents(status,expires_at);

create table public.mme_warranty_evidence_scan_jobs (
 scan_job_id uuid primary key default gen_random_uuid(),
 upload_intent_id uuid not null unique references public.mme_warranty_evidence_upload_intents(upload_intent_id) on delete restrict,
 status text not null default 'queued' check(status in ('queued','processing','clean','infected','rejected','retry','dead_letter')),
 attempts integer not null default 0 check(attempts>=0),
 max_attempts integer not null default 5 check(max_attempts between 1 and 10),
 lease_token uuid, lease_expires_at timestamptz,
 scanner_name text, scanner_version text, scan_result_code text,
 scanned_at timestamptz, created_at timestamptz not null default now(),
 check((status='processing')=(lease_token is not null and lease_expires_at is not null))
);
create index mme_warranty_evidence_scan_queue_idx on public.mme_warranty_evidence_scan_jobs(created_at) where status in ('queued','retry');

create table public.mme_warranty_evidence_upload_events (
 event_id bigint generated always as identity primary key,
 upload_intent_id uuid not null references public.mme_warranty_evidence_upload_intents(upload_intent_id) on delete restrict,
 event_type text not null check(event_type in ('reserved','upload_confirmed','quarantined','scan_started','scan_clean','scan_infected','registered','rejected','expired')),
 actor_reference text not null, event_digest text not null, occurred_at timestamptz not null default now()
);
create index mme_warranty_evidence_upload_events_timeline_idx on public.mme_warranty_evidence_upload_events(upload_intent_id,occurred_at);

alter table public.mme_warranty_evidence_upload_intents enable row level security;
alter table public.mme_warranty_evidence_scan_jobs enable row level security;
alter table public.mme_warranty_evidence_upload_events enable row level security;
revoke all on public.mme_warranty_evidence_upload_intents,public.mme_warranty_evidence_scan_jobs,public.mme_warranty_evidence_upload_events from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_evidence_upload_intents,public.mme_warranty_evidence_scan_jobs to service_role;
grant select,insert on public.mme_warranty_evidence_upload_events to service_role;
revoke update,delete,truncate on public.mme_warranty_evidence_upload_events from public,anon,authenticated,service_role;
commit;