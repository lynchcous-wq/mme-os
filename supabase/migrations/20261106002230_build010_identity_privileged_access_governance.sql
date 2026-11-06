begin;
create table if not exists public.mme_identity_privileged_access_requests(
 request_id uuid primary key default gen_random_uuid(),
 person_id uuid not null references public.mme_person_identities(person_id),
 requested_role text not null,
 scope text not null,
 rationale text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','expired','revoked')),
 requested_by_auth_user_id uuid not null,
 reviewed_by_auth_user_id uuid,
 review_note text,
 requested_at timestamptz not null default now(),
 reviewed_at timestamptz,
 starts_at timestamptz,
 expires_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(expires_at is null or starts_at is null or expires_at>starts_at)
);
create table if not exists public.mme_identity_access_review_cycles(
 cycle_id uuid primary key default gen_random_uuid(),
 person_id uuid not null references public.mme_person_identities(person_id),
 role_snapshot text not null,
 reviewer_auth_user_id uuid not null,
 decision text not null check(decision in ('retain','modify','revoke','pending')),
 rationale text not null,
 reviewed_at timestamptz not null default now(),
 next_review_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_identity_emergency_freeze_requests(
 freeze_id uuid primary key default gen_random_uuid(),
 person_id uuid not null references public.mme_person_identities(person_id),
 status text not null default 'requested' check(status in ('requested','approved','rejected','lift_requested','lifted')),
 reason text not null,
 requested_by_auth_user_id uuid not null,
 reviewed_by_auth_user_id uuid,
 review_note text,
 requested_at timestamptz not null default now(),
 reviewed_at timestamptz,
 lifted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_identity_governance_audit(
 audit_id bigint generated always as identity primary key,
 actor_auth_user_id uuid not null,
 actor_role text not null,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}',
 request_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_identity_privileged_request_status_idx on public.mme_identity_privileged_access_requests(status,expires_at,requested_at desc);
create index if not exists mme_identity_access_review_due_idx on public.mme_identity_access_review_cycles(next_review_at,decision);
create index if not exists mme_identity_freeze_status_idx on public.mme_identity_emergency_freeze_requests(person_id,status,requested_at desc);
alter table public.mme_identity_privileged_access_requests enable row level security;
alter table public.mme_identity_access_review_cycles enable row level security;
alter table public.mme_identity_emergency_freeze_requests enable row level security;
alter table public.mme_identity_governance_audit enable row level security;
do $$ declare t text; begin
 foreach t in array array['mme_identity_privileged_access_requests','mme_identity_access_review_cycles','mme_identity_emergency_freeze_requests','mme_identity_governance_audit'] loop
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.mme_identity_governance_audit_audit_id_seq to service_role;
comment on table public.mme_identity_privileged_access_requests is 'Approval ledger for temporary elevated access; does not itself modify live role claims.';
comment on table public.mme_identity_emergency_freeze_requests is 'Emergency freeze request and approval ledger; actual auth enforcement requires verified identity-provider integration.';
comment on table public.mme_identity_access_review_cycles is 'Periodic role review ledger; decisions require a separate authorized permission change.';
commit;