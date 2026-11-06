-- Build 009.69: warranty lifecycle orchestration
begin;
create table public.mme_warranty_lifecycle_records (
 lifecycle_id uuid primary key default gen_random_uuid(),
 warranty_id uuid not null references public.mme_serialized_warranties(id) on delete restrict,
 customer_identity_id uuid not null,
 lifecycle_status text not null default 'pending_registration' check(lifecycle_status in ('pending_registration','active','suspended','expired','cancel_pending','cancelled','transferred')),
 registration_source text not null check(registration_source in ('pos','online_order','manual','provider_sync')),
 purchase_reference text not null, purchase_at timestamptz, coverage_starts_at timestamptz, coverage_ends_at timestamptz,
 provider_id uuid, provider_program_id uuid, registration_reference text, last_provider_sync_at timestamptz,
 idempotency_key text not null unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(coverage_ends_at is null or coverage_starts_at is null or coverage_ends_at>=coverage_starts_at)
);
create index mme_warranty_lifecycle_customer_idx on public.mme_warranty_lifecycle_records(customer_identity_id,lifecycle_status,coverage_ends_at);
create table public.mme_warranty_lifecycle_events (
 event_id bigint generated always as identity primary key, lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 event_type text not null, actor_id uuid, event_reference text, event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'), occurred_at timestamptz not null default now()
);
create table public.mme_warranty_lifecycle_jobs (
 job_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 job_type text not null, status text not null default 'queued' check(status in ('queued','processing','succeeded','retry','failed','dead_letter','cancelled')),
 scheduled_for timestamptz not null default now(), attempts integer not null default 0 check(attempts>=0), idempotency_key text not null unique,
 payload jsonb not null default '{}'::jsonb, last_error_code text, created_at timestamptz not null default now()
);
create index mme_warranty_lifecycle_jobs_queue_idx on public.mme_warranty_lifecycle_jobs(status,scheduled_for) where status in ('queued','retry');
create table public.mme_warranty_customer_notifications (
 notification_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 customer_identity_id uuid not null, notification_type text not null, channel text not null check(channel in ('email','sms','in_app')),
 status text not null default 'queued' check(status in ('queued','sent','delivered','failed','suppressed','cancelled')), template_version text not null,
 idempotency_key text not null unique, scheduled_for timestamptz not null default now(), sent_at timestamptz, delivered_at timestamptz, failure_code text
);
create table public.mme_warranty_renewal_offers (
 offer_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 offer_code text not null, offer_version text not null, price numeric(14,2) not null check(price>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 valid_from timestamptz not null, valid_until timestamptz not null, status text not null default 'draft' check(status in ('draft','approved','presented','accepted','declined','expired','withdrawn')),
 approved_by uuid, approved_at timestamptz, customer_decision_at timestamptz, idempotency_key text not null unique, check(valid_until>valid_from)
);
create table public.mme_warranty_transfer_requests (
 transfer_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 from_customer_identity_id uuid not null, to_customer_identity_id uuid not null, status text not null default 'requested' check(status in ('requested','identity_verification','approved','rejected','completed','cancelled')),
 verification_reference text not null, decided_by uuid, decided_at timestamptz, idempotency_key text not null unique, check(from_customer_identity_id<>to_customer_identity_id)
);
create table public.mme_warranty_cancellation_requests (
 cancellation_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 requested_by uuid not null, reason_code text not null, status text not null default 'requested' check(status in ('requested','eligibility_review','approved','rejected','completed','withdrawn')),
 refund_amount numeric(14,2) check(refund_amount is null or refund_amount>=0), currency_code text, decided_by uuid, decided_at timestamptz, idempotency_key text not null unique
);
create table public.mme_warranty_eligibility_checks (
 eligibility_check_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 checked_at timestamptz not null default now(), result text not null check(result in ('eligible','ineligible','manual_review','unknown')), reason_code text not null,
 policy_version text not null, provider_submission_id uuid, checked_by uuid, source_reference text not null, idempotency_key text not null unique
);
create table public.mme_warranty_replacement_reviews (
 replacement_review_id uuid primary key default gen_random_uuid(), lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 repair_case_id uuid, recommendation text not null check(recommendation in ('repair','replace','refund_review','manual_review')), reason text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','completed')), estimated_repair_cost numeric(14,2), estimated_replacement_cost numeric(14,2),
 currency_code text, decided_by uuid, decided_at timestamptz, decision_notes text, idempotency_key text not null unique
);
do $$ declare t text; begin foreach t in array array['mme_warranty_lifecycle_records','mme_warranty_lifecycle_events','mme_warranty_lifecycle_jobs','mme_warranty_customer_notifications','mme_warranty_renewal_offers','mme_warranty_transfer_requests','mme_warranty_cancellation_requests','mme_warranty_eligibility_checks','mme_warranty_replacement_reviews'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from public,anon,authenticated',t); end loop; end $$;
grant select,insert,update on public.mme_warranty_lifecycle_records,public.mme_warranty_lifecycle_jobs,public.mme_warranty_customer_notifications,public.mme_warranty_renewal_offers,public.mme_warranty_transfer_requests,public.mme_warranty_cancellation_requests,public.mme_warranty_eligibility_checks,public.mme_warranty_replacement_reviews to service_role;
grant select,insert on public.mme_warranty_lifecycle_events to service_role;
revoke update,delete,truncate on public.mme_warranty_lifecycle_events from public,anon,authenticated,service_role;
commit;