begin;
create table public.mme_warranty_security_intelligence_signals(
 signal_id uuid primary key default gen_random_uuid(),
 signal_key text not null unique,
 signal_type text not null check(signal_type in ('serial_mismatch','duplicate_serial','claim_velocity','repeat_claim_pattern','evidence_integrity_mismatch','unusual_evidence_access','policy_override_pattern','device_identity_conflict')),
 subject_fingerprint text not null check(subject_fingerprint ~ '^[a-f0-9]{64}$'),
 source_case_id uuid references public.mme_warranty_security_cases(case_id) on delete restrict,
 source_evidence_id uuid references public.mme_warranty_security_case_evidence(evidence_id) on delete restrict,
 source_system text not null check(length(trim(source_system)) between 2 and 80),
 occurrence_count integer not null default 1 check(occurrence_count between 1 and 100000),
 feature_data jsonb not null default '{}'::jsonb,
 observed_at timestamptz not null default now(),
 recorded_by uuid,
 created_at timestamptz not null default now()
);
create index mme_warranty_intel_signal_subject_idx on public.mme_warranty_security_intelligence_signals(subject_fingerprint,observed_at desc);
create index mme_warranty_intel_signal_type_idx on public.mme_warranty_security_intelligence_signals(signal_type,observed_at desc);
create table public.mme_warranty_security_intelligence_assessments(
 assessment_id uuid primary key default gen_random_uuid(),
 subject_fingerprint text not null check(subject_fingerprint ~ '^[a-f0-9]{64}$'),
 score integer not null check(score between 0 and 100),
 risk_band text not null check(risk_band in ('low','guarded','elevated','high','critical')),
 confidence text not null check(confidence in ('low','medium','high')),
 factor_breakdown jsonb not null,
 signal_count integer not null check(signal_count>=0),
 window_start timestamptz not null,
 window_end timestamptz not null,
 model_version text not null,
 review_required boolean not null default true,
 reviewed_by uuid,
 reviewed_at timestamptz,
 reviewer_outcome text check(reviewer_outcome in ('confirmed_pattern','benign','insufficient_evidence','escalated')),
 created_at timestamptz not null default now(),
 check(window_end>=window_start)
);
create index mme_warranty_intel_assessment_subject_idx on public.mme_warranty_security_intelligence_assessments(subject_fingerprint,created_at desc);
create table public.mme_warranty_security_intelligence_case_links(
 link_id uuid primary key default gen_random_uuid(),
 assessment_id uuid not null references public.mme_warranty_security_intelligence_assessments(assessment_id) on delete restrict,
 case_id uuid not null references public.mme_warranty_security_cases(case_id) on delete restrict,
 relationship text not null check(relationship in ('same_subject','same_signal_pattern','supporting_evidence')),
 created_at timestamptz not null default now(),
 unique(assessment_id,case_id,relationship)
);
create table public.mme_warranty_security_intelligence_reviews(
 review_id uuid primary key default gen_random_uuid(),
 assessment_id uuid not null references public.mme_warranty_security_intelligence_assessments(assessment_id) on delete restrict,
 reviewer_id uuid not null,
 outcome text not null check(outcome in ('confirmed_pattern','benign','insufficient_evidence','escalated')),
 rationale text not null check(length(trim(rationale)) between 10 and 3000),
 created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['mme_warranty_security_intelligence_signals','mme_warranty_security_intelligence_assessments','mme_warranty_security_intelligence_case_links','mme_warranty_security_intelligence_reviews'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update on public.%I to service_role',t);
 end loop;
end $$;
create or replace function public.mme_warranty_security_intelligence_review_guard()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if tg_op='UPDATE' then raise exception 'intelligence_reviews_are_append_only'; end if;
 return new;
end $$;
create trigger mme_warranty_intelligence_reviews_append_only before update or delete on public.mme_warranty_security_intelligence_reviews for each row execute function public.mme_warranty_security_intelligence_review_guard();
revoke all on function public.mme_warranty_security_intelligence_review_guard() from public,anon,authenticated;
commit;