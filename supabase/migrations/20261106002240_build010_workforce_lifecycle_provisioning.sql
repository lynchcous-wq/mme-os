begin;
create table if not exists public.mme_workforce_lifecycle_cases(
 case_id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 case_type text not null check(case_type in ('onboarding','transfer','promotion','leave','return','termination')),
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','in_progress','blocked','completed','cancelled')),
 effective_at timestamptz,
 department text,
 job_position text,
 manager_person_id uuid,
 reason text not null,
 initiated_by_auth_user_id uuid not null,
 approved_by_auth_user_id uuid,
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_workforce_lifecycle_tasks(
 task_id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_workforce_lifecycle_cases(case_id) on delete cascade,
 task_key text not null,
 title text not null,
 owner_role text not null,
 status text not null default 'pending' check(status in ('pending','in_progress','blocked','completed','waived')),
 due_at timestamptz,
 completed_by_auth_user_id uuid,
 completed_at timestamptz,
 completion_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(case_id,task_key)
);
create table if not exists public.mme_workforce_access_provisioning_requests(
 provisioning_id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_workforce_lifecycle_cases(case_id) on delete cascade,
 person_id uuid not null,
 requested_role text not null,
 access_scope text not null,
 action text not null check(action in ('grant','change','revoke')),
 status text not null default 'pending' check(status in ('pending','approved','rejected','queued','executed','failed','cancelled')),
 requested_by_auth_user_id uuid not null,
 reviewed_by_auth_user_id uuid,
 review_note text,
 execution_reference text,
 execution_result jsonb not null default '{}',
 requested_at timestamptz not null default now(),
 reviewed_at timestamptz,
 executed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_workforce_asset_assignments(
 assignment_id uuid primary key default gen_random_uuid(),
 case_id uuid references public.mme_workforce_lifecycle_cases(case_id) on delete set null,
 person_id uuid not null,
 asset_tag text not null,
 asset_type text not null,
 serial_number text,
 assignment_status text not null default 'assigned' check(assignment_status in ('assigned','returned','lost','damaged','retired')),
 assigned_at timestamptz not null default now(),
 returned_at timestamptz,
 assigned_by_auth_user_id uuid not null,
 notes text,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_workforce_lifecycle_audit(
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
create index if not exists mme_workforce_case_person_idx on public.mme_workforce_lifecycle_cases(person_id,created_at desc);
create index if not exists mme_workforce_case_status_idx on public.mme_workforce_lifecycle_cases(status,case_type,effective_at);
create index if not exists mme_workforce_task_due_idx on public.mme_workforce_lifecycle_tasks(status,due_at,owner_role);
create index if not exists mme_workforce_provision_status_idx on public.mme_workforce_access_provisioning_requests(status,requested_at);
create index if not exists mme_workforce_asset_person_idx on public.mme_workforce_asset_assignments(person_id,assignment_status);
alter table public.mme_workforce_lifecycle_cases enable row level security;
alter table public.mme_workforce_lifecycle_tasks enable row level security;
alter table public.mme_workforce_access_provisioning_requests enable row level security;
alter table public.mme_workforce_asset_assignments enable row level security;
alter table public.mme_workforce_lifecycle_audit enable row level security;
do $$ declare t text; begin
 foreach t in array array['mme_workforce_lifecycle_cases','mme_workforce_lifecycle_tasks','mme_workforce_access_provisioning_requests','mme_workforce_asset_assignments','mme_workforce_lifecycle_audit'] loop
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.mme_workforce_lifecycle_audit_audit_id_seq to service_role;
comment on table public.mme_workforce_access_provisioning_requests is 'HR-triggered access change request ledger; execution requires a verified identity-provider adapter and must not be inferred from approval.';
comment on table public.mme_workforce_lifecycle_cases is 'Workforce lifecycle case ledger; person identifiers must resolve to canonical MME workforce identities.';
comment on table public.mme_workforce_asset_assignments is 'Workforce equipment custody ledger; asset records are not device management enforcement.';
commit;