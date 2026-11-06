-- Build 009.70: customer warranty portal data and secure request workflows
begin;
create table public.mme_warranty_portal_access (
 access_id uuid primary key default gen_random_uuid(), customer_identity_id uuid not null, auth_user_id uuid not null,
 status text not null default 'active' check(status in ('active','suspended','revoked')), verified_at timestamptz,
 created_at timestamptz not null default now(), unique(customer_identity_id,auth_user_id)
);
create table public.mme_warranty_portal_preferences (
 customer_identity_id uuid primary key, email_notifications boolean not null default true, sms_notifications boolean not null default false,
 marketing_opt_in boolean not null default false, preferred_channel text not null default 'email' check(preferred_channel in ('email','sms','in_app')),
 updated_at timestamptz not null default now()
);
create table public.mme_warranty_portal_claim_views (
 view_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 customer_identity_id uuid not null, claim_reference text not null, status_label text not null, customer_message text,
 next_update_due_at timestamptz, last_updated_at timestamptz not null default now(), unique(lifecycle_id,claim_reference)
);
create table public.mme_warranty_portal_requests (
 request_id uuid primary key default gen_random_uuid(), customer_identity_id uuid not null, lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 request_type text not null check(request_type in ('repair','claim_status','transfer','cancellation','document_copy','correction')),
 status text not null default 'submitted' check(status in ('submitted','triaged','in_progress','awaiting_customer','resolved','rejected','withdrawn')),
 customer_description text not null, idempotency_key text not null unique, assigned_to uuid, resolution_code text, resolution_message text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), resolved_at timestamptz
);
create index mme_warranty_portal_requests_queue_idx on public.mme_warranty_portal_requests(status,created_at);
create table public.mme_warranty_portal_documents (
 document_id uuid primary key default gen_random_uuid(), request_id uuid not null references public.mme_warranty_portal_requests(request_id) on delete restrict,
 customer_identity_id uuid not null, storage_object_reference text not null, document_type text not null,
 file_name text not null, mime_type text not null, byte_size bigint not null check(byte_size between 1 and 20971520),
 checksum_sha256 text not null, scan_status text not null default 'pending' check(scan_status in ('pending','clean','rejected','error')),
 visibility text not null default 'private' check(visibility in ('private','staff_only','customer_visible')),
 uploaded_at timestamptz not null default now(), unique(storage_object_reference)
);
create table public.mme_warranty_portal_activity (
 activity_id bigint generated always as identity primary key, customer_identity_id uuid not null, lifecycle_id uuid,
 activity_type text not null, safe_summary text not null, occurred_at timestamptz not null default now()
);
do $$ declare t text; begin foreach t in array array['mme_warranty_portal_access','mme_warranty_portal_preferences','mme_warranty_portal_claim_views','mme_warranty_portal_requests','mme_warranty_portal_documents','mme_warranty_portal_activity'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from public,anon,authenticated',t); end loop; end $$;
grant select,insert,update on public.mme_warranty_portal_access,public.mme_warranty_portal_preferences,public.mme_warranty_portal_claim_views,public.mme_warranty_portal_requests,public.mme_warranty_portal_documents to service_role;
grant select,insert on public.mme_warranty_portal_activity to service_role;
commit;