-- Build 009.76: governed warranty claims and resolution workflow
begin;
create table public.mme_warranty_claim_cases (
 claim_id uuid primary key default gen_random_uuid(),
 lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 customer_identity_id uuid not null,
 claim_number text not null unique,
 claim_type text not null check(claim_type in ('repair','replacement','refund_review','manufacturer_reimbursement','other')),
 status text not null default 'submitted' check(status in ('submitted','identity_review','eligibility_review','evidence_required','ready_for_provider','provider_submitted','provider_pending','repair_authorized','replacement_review','refund_review','resolved','rejected','withdrawn','closed')),
 issue_code text not null, customer_description text,
 purchase_reference text not null, serial_number_digest text, imei_digest text,
 submitted_at timestamptz not null default now(), resolved_at timestamptz,
 assigned_to uuid, priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
 idempotency_key text not null unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index mme_warranty_claim_cases_queue_idx on public.mme_warranty_claim_cases(status,priority,submitted_at);
create index mme_warranty_claim_cases_customer_idx on public.mme_warranty_claim_cases(customer_identity_id,submitted_at desc);
create table public.mme_warranty_claim_evidence (
 evidence_id uuid primary key default gen_random_uuid(),
 claim_id uuid not null references public.mme_warranty_claim_cases(claim_id) on delete restrict,
 evidence_type text not null check(evidence_type in ('receipt','product_photo','damage_photo','video','diagnostic','serial_verification','purchase_verification','other')),
 storage_object_reference text not null, content_sha256 text not null,
 content_type text not null, byte_size bigint not null check(byte_size>0),
 submitted_by uuid not null, submitted_at timestamptz not null default now(),
 verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected','quarantined')),
 verified_by uuid, verified_at timestamptz, rejection_code text,
 idempotency_key text not null unique
);
create table public.mme_warranty_claim_verifications (
 verification_id uuid primary key default gen_random_uuid(),
 claim_id uuid not null references public.mme_warranty_claim_cases(claim_id) on delete restrict,
 verification_type text not null check(verification_type in ('identity','purchase','serial','imei','coverage','fraud_review')),
 result text not null check(result in ('passed','failed','manual_review','unknown')),
 source_reference text not null, policy_version text not null,
 verified_by uuid, verified_at timestamptz not null default now(),
 details_digest text, idempotency_key text not null unique
);
create table public.mme_warranty_claim_provider_submissions (
 submission_id uuid primary key default gen_random_uuid(),
 claim_id uuid not null references public.mme_warranty_claim_cases(claim_id) on delete restrict,
 provider_id uuid not null, provider_claim_reference text,
 status text not null default 'prepared' check(status in ('prepared','submitted','acknowledged','more_information','approved','denied','cancelled','unknown')),
 submitted_at timestamptz, responded_at timestamptz, response_code text,
 request_digest text not null, response_digest text,
 submitted_by uuid, idempotency_key text not null unique,
 unique(provider_id,provider_claim_reference)
);
create table public.mme_warranty_claim_resolutions (
 resolution_id uuid primary key default gen_random_uuid(),
 claim_id uuid not null references public.mme_warranty_claim_cases(claim_id) on delete restrict,
 outcome text not null check(outcome in ('repair','replacement','refund','denied','customer_withdrawal')),
 estimated_cost numeric(14,2) check(estimated_cost is null or estimated_cost>=0),
 approved_amount numeric(14,2) check(approved_amount is null or approved_amount>=0),
 currency_code text check(currency_code is null or currency_code ~ '^[A-Z]{3}$'),
 rationale_code text not null, rationale text,
 recommended_by uuid not null, approved_by uuid, approved_at timestamptz,
 second_approver uuid, second_approved_at timestamptz,
 status text not null default 'proposed' check(status in ('proposed','pending_approval','approved','rejected','executed','cancelled')),
 policy_version text not null, idempotency_key text not null unique,
 check(approved_by is null or approved_by<>recommended_by),
 check(second_approver is null or (approved_by is not null and second_approver<>approved_by and second_approver<>recommended_by))
);
create table public.mme_warranty_claim_repair_events (
 repair_event_id uuid primary key default gen_random_uuid(),
 claim_id uuid not null references public.mme_warranty_claim_cases(claim_id) on delete restrict,
 event_type text not null check(event_type in ('authorized','received','diagnosed','parts_ordered','repair_started','repair_completed','quality_checked','shipped','delivered','failed')),
 provider_reference text, notes_digest text, occurred_at timestamptz not null,
 recorded_by uuid not null, idempotency_key text not null unique
);
create table public.mme_warranty_claim_audit_events (
 audit_event_id bigint generated always as identity primary key,
 claim_id uuid not null references public.mme_warranty_claim_cases(claim_id) on delete restrict,
 event_type text not null, actor_id uuid, prior_status text, new_status text,
 source_reference text not null, event_digest text not null, occurred_at timestamptz not null default now()
);
create index mme_warranty_claim_audit_timeline_idx on public.mme_warranty_claim_audit_events(claim_id,occurred_at);
do $$ declare t text; begin foreach t in array array['mme_warranty_claim_cases','mme_warranty_claim_evidence','mme_warranty_claim_verifications','mme_warranty_claim_provider_submissions','mme_warranty_claim_resolutions','mme_warranty_claim_repair_events','mme_warranty_claim_audit_events'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from public,anon,authenticated',t); end loop; end $$;
grant select,insert,update on public.mme_warranty_claim_cases,public.mme_warranty_claim_provider_submissions,public.mme_warranty_claim_resolutions to service_role;
grant select,insert on public.mme_warranty_claim_evidence,public.mme_warranty_claim_verifications,public.mme_warranty_claim_repair_events,public.mme_warranty_claim_audit_events to service_role;
revoke update,delete,truncate on public.mme_warranty_claim_audit_events from public,anon,authenticated,service_role;
revoke update,delete,truncate on public.mme_warranty_claim_verifications from public,anon,authenticated,service_role;
revoke update,delete,truncate on public.mme_warranty_claim_evidence from public,anon,authenticated,service_role;
commit;