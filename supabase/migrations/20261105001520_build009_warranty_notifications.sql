-- Build 009.73: consent-aware warranty notification orchestration
begin;
create table public.mme_warranty_notification_templates (
 template_id uuid primary key default gen_random_uuid(),
 template_code text not null, template_version text not null, channel text not null check(channel in ('email','sms','in_app')),
 locale_code text not null default 'en-US', subject_template text, body_template text not null,
 purpose text not null check(purpose in ('transactional','service_update','marketing')),
 status text not null default 'draft' check(status in ('draft','approved','retired')),
 approved_by uuid, approved_at timestamptz, created_at timestamptz not null default now(),
 unique(template_code,template_version,channel,locale_code)
);
create table public.mme_warranty_notification_consent_events (
 consent_event_id bigint generated always as identity primary key,
 customer_identity_id uuid not null, channel text not null check(channel in ('email','sms','in_app')),
 purpose text not null check(purpose in ('transactional','service_update','marketing')),
 consent_state text not null check(consent_state in ('granted','revoked','verified','unverified')),
 source text not null, evidence_reference text, recorded_at timestamptz not null default now(), recorded_by uuid
);
create index mme_warranty_notification_consent_latest_idx on public.mme_warranty_notification_consent_events(customer_identity_id,channel,purpose,recorded_at desc);
create table public.mme_warranty_notification_channel_preferences (
 customer_identity_id uuid not null, channel text not null check(channel in ('email','sms','in_app')),
 enabled boolean not null default false, quiet_hours_start time, quiet_hours_end time, timezone_name text not null default 'America/New_York',
 updated_at timestamptz not null default now(), primary key(customer_identity_id,channel),
 check((quiet_hours_start is null)=(quiet_hours_end is null))
);
create table public.mme_warranty_notification_delivery_attempts (
 attempt_id uuid primary key default gen_random_uuid(),
 notification_id uuid not null references public.mme_warranty_customer_notifications(notification_id) on delete restrict,
 attempt_number integer not null check(attempt_number>0), provider_code text not null,
 provider_message_reference text, status text not null check(status in ('submitted','accepted','delivered','temporary_failure','permanent_failure','unknown')),
 error_code text, attempted_at timestamptz not null default now(), next_retry_at timestamptz,
 idempotency_key text not null unique, response_digest text,
 unique(notification_id,attempt_number)
);
create index mme_warranty_notification_retry_idx on public.mme_warranty_notification_delivery_attempts(status,next_retry_at) where status='temporary_failure';
create table public.mme_warranty_notification_suppressions (
 suppression_id uuid primary key default gen_random_uuid(), customer_identity_id uuid not null,
 channel text not null check(channel in ('email','sms','in_app')), purpose text not null,
 reason_code text not null, source_reference text not null, active boolean not null default true,
 created_at timestamptz not null default now(), lifted_at timestamptz
);
create table public.mme_warranty_notification_provider_events (
 provider_event_id uuid primary key default gen_random_uuid(), provider_code text not null,
 provider_message_reference text, event_type text not null, event_at timestamptz not null,
 signature_verified boolean not null default false, payload_digest text not null,
 processed_at timestamptz, processing_status text not null default 'pending' check(processing_status in ('pending','processed','rejected','retry')),
 idempotency_key text not null unique
);
do $$ declare t text; begin foreach t in array array['mme_warranty_notification_templates','mme_warranty_notification_consent_events','mme_warranty_notification_channel_preferences','mme_warranty_notification_delivery_attempts','mme_warranty_notification_suppressions','mme_warranty_notification_provider_events'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from public,anon,authenticated',t); end loop; end $$;
grant select,insert,update on public.mme_warranty_notification_templates,public.mme_warranty_notification_channel_preferences,public.mme_warranty_notification_suppressions,public.mme_warranty_notification_provider_events to service_role;
grant select,insert on public.mme_warranty_notification_consent_events,public.mme_warranty_notification_delivery_attempts to service_role;
revoke update,delete,truncate on public.mme_warranty_notification_consent_events from public,anon,authenticated,service_role;
commit;