begin;
create table if not exists public.mme_security_compliance_controls(
 control_id uuid primary key default gen_random_uuid(),
 control_key text not null unique,
 domain text not null,
 title text not null,
 description text not null,
 framework_mappings text[] not null default '{}',
 owner_role text not null default 'cio',
 review_frequency_days integer not null default 90 check(review_frequency_days between 1 and 365),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_security_policies(
 policy_id uuid primary key default gen_random_uuid(),
 policy_key text not null unique,
 title text not null,
 version text not null,
 body text not null,
 status text not null default 'draft' check(status in ('draft','published','retired')),
 effective_at timestamptz,
 acknowledgement_required boolean not null default true,
 owner_role text not null default 'cio',
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_security_policy_acknowledgements(
 acknowledgement_id uuid primary key default gen_random_uuid(),
 policy_id uuid not null references public.mme_security_policies(policy_id),
 policy_version text not null,
 person_id uuid not null,
 acknowledged_at timestamptz not null default now(),
 attestation text not null default 'I have read and acknowledge this policy.',
 unique(policy_id,policy_version,person_id)
);
create table if not exists public.mme_security_compliance_evidence(
 evidence_id uuid primary key default gen_random_uuid(),
 control_id uuid not null references public.mme_security_compliance_controls(control_id),
 evidence_type text not null check(evidence_type in ('document','system_record','review','attestation','external_reference')),
 title text not null,
 storage_reference text,
 source_system text,
 collected_by uuid not null,
 collected_at timestamptz not null default now(),
 review_due_at timestamptz,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create table if not exists public.mme_security_compliance_exceptions(
 exception_id uuid primary key default gen_random_uuid(),
 control_id uuid not null references public.mme_security_compliance_controls(control_id),
 title text not null,
 rationale text not null,
 risk_level text not null check(risk_level in ('low','moderate','high','critical')),
 status text not null default 'open' check(status in ('open','approved','rejected','remediated','expired')),
 requested_by uuid not null,
 reviewed_by uuid,
 review_note text,
 expires_at timestamptz,
 remediation_owner uuid,
 remediation_due_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_security_access_reviews(
 review_id uuid primary key default gen_random_uuid(),
 subject_person_id uuid not null,
 subject_role text not null,
 reviewer_person_id uuid not null,
 decision text not null check(decision in ('retain','modify','revoke','pending')),
 rationale text not null,
 reviewed_at timestamptz not null default now(),
 next_review_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_security_governance_audit(
 audit_id bigint generated always as identity primary key,
 actor_id uuid not null,
 actor_role text not null,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}',
 request_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_security_policy_ack_person_idx on public.mme_security_policy_acknowledgements(person_id,acknowledged_at desc);
create index if not exists mme_security_evidence_control_idx on public.mme_security_compliance_evidence(control_id,collected_at desc);
create index if not exists mme_security_exception_status_idx on public.mme_security_compliance_exceptions(status,risk_level,expires_at);
create index if not exists mme_security_access_review_due_idx on public.mme_security_access_reviews(next_review_at,decision);

insert into public.mme_security_compliance_controls(control_key,domain,title,description,framework_mappings,owner_role) values
 ('IAM-01','Identity & Access','Unique workforce identity','Maintain individually attributable workforce identities and role assignments.','{NIST-AC-2,SOC2-CC6.1}','cio'),
 ('IAM-02','Identity & Access','Privileged access review','Review privileged access periodically and record retain, modify or revoke decisions.','{NIST-AC-6,SOC2-CC6.2}','cio'),
 ('IAM-03','Identity & Access','Access termination','Revoke access promptly when workforce access is no longer authorized.','{NIST-AC-2,SOC2-CC6.3}','it_admin'),
 ('SEC-01','Security Operations','Incident response','Record, assign, escalate and close security incidents with evidence.','{NIST-IR-4,SOC2-CC7.4}','it_admin'),
 ('SEC-02','Security Operations','Security event monitoring','Monitor security events and retain reviewable operational records.','{NIST-SI-4,SOC2-CC7.2}','it_admin'),
 ('DATA-01','Data Protection','Sensitive data handling','Define and enforce approved handling of sensitive business and customer data.','{NIST-AC-4,SOC2-CC6.7}','cio'),
 ('OPS-01','Operations','Change management','Review and document material production changes and approvals.','{NIST-CM-3,SOC2-CC8.1}','cio'),
 ('BCP-01','Resilience','Backup and recovery','Maintain and periodically validate backup and recovery procedures.','{NIST-CP-9,NIST-CP-10,SOC2-A1.2}','cio')
on conflict(control_key) do nothing;

alter table public.mme_security_compliance_controls enable row level security;
alter table public.mme_security_policies enable row level security;
alter table public.mme_security_policy_acknowledgements enable row level security;
alter table public.mme_security_compliance_evidence enable row level security;
alter table public.mme_security_compliance_exceptions enable row level security;
alter table public.mme_security_access_reviews enable row level security;
alter table public.mme_security_governance_audit enable row level security;

do $$ declare t text; begin
 foreach t in array array['mme_security_compliance_controls','mme_security_policies','mme_security_policy_acknowledgements','mme_security_compliance_evidence','mme_security_compliance_exceptions','mme_security_access_reviews','mme_security_governance_audit'] loop
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.mme_security_governance_audit_audit_id_seq to service_role;
comment on table public.mme_security_compliance_controls is 'MME internal control catalogue; mappings are reference mappings, not certification claims.';
comment on table public.mme_security_compliance_evidence is 'Evidence metadata and references; binary evidence remains in approved private storage.';
comment on table public.mme_security_access_reviews is 'Recorded access review decisions; this ledger does not itself revoke application access.';
commit;