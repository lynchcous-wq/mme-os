-- Build 004: Identity Matrix foundation (additive migration).
-- Apply to a dedicated development Supabase project only after review.
create extension if not exists pgcrypto;

create table public.mme_person_identities (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.mme_customer_relationships (
  id uuid primary key default gen_random_uuid(),
  person_identity_id uuid not null unique references public.mme_person_identities(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending','active','temporarily_suspended','frozen','archived')),
  created_at timestamptz not null default now()
);

create table public.mme_employee_relationships (
  id uuid primary key default gen_random_uuid(),
  person_identity_id uuid not null unique references public.mme_person_identities(id) on delete restrict,
  employee_number text not null unique,
  department_key text,
  position_title text,
  status text not null default 'pending'
    check (status in ('pending','active','temporarily_suspended','frozen','terminated','archived')),
  created_at timestamptz not null default now()
);

create table public.mme_roles (
  id uuid primary key default gen_random_uuid(),
  role_key text not null unique,
  display_name text not null,
  department_key text,
  version integer not null default 1 check (version > 0),
  active boolean not null default true
);

create table public.mme_role_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_relationship_id uuid not null references public.mme_employee_relationships(id) on delete restrict,
  role_id uuid not null references public.mme_roles(id) on delete restrict,
  scope jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending','active','revoked','expired')),
  effective_from timestamptz not null default now(),
  effective_until timestamptz
);

create table public.mme_permission_grants (
  id uuid primary key default gen_random_uuid(),
  role_assignment_id uuid not null references public.mme_role_assignments(id) on delete restrict,
  resource_key text not null,
  action_key text not null,
  scope jsonb not null default '{}'::jsonb,
  status text not null default 'active'
    check (status in ('active','revoked','expired'))
);

create table public.mme_integration_entitlements (
  id uuid primary key default gen_random_uuid(),
  employee_relationship_id uuid not null references public.mme_employee_relationships(id) on delete restrict,
  integration_key text not null,
  scope jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending','active','revoked','expired'))
);

create table public.mme_profile_appearance_preferences (
  id uuid primary key default gen_random_uuid(),
  employee_relationship_id uuid not null unique references public.mme_employee_relationships(id) on delete restrict,
  appearance_mode text not null default 'standard'
    check (appearance_mode in ('standard','role_based','personal_approved')),
  approved_color_token text
);

create table public.mme_role_color_registry (
  id uuid primary key default gen_random_uuid(),
  role_id uuid not null unique references public.mme_roles(id) on delete restrict,
  color_token text not null unique,
  color_value text not null unique,
  version integer not null default 1
);

create table public.mme_identity_audit_events (
  id bigint generated always as identity primary key,
  actor_identity_id uuid references public.mme_person_identities(id) on delete restrict,
  actor_service_key text,
  target_identity_id uuid references public.mme_person_identities(id) on delete restrict,
  action_key text not null,
  outcome text not null check (outcome in ('success','denied','failed')),
  reason text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now(),
  check (actor_identity_id is not null or actor_service_key is not null)
);

create index mme_role_assignments_employee_idx
  on public.mme_role_assignments(employee_relationship_id, status);
create index mme_permission_grants_lookup_idx
  on public.mme_permission_grants(resource_key, action_key, status);
create index mme_audit_target_idx
  on public.mme_identity_audit_events(target_identity_id, created_at desc);

alter table public.mme_person_identities enable row level security;
alter table public.mme_customer_relationships enable row level security;
alter table public.mme_employee_relationships enable row level security;
alter table public.mme_roles enable row level security;
alter table public.mme_role_assignments enable row level security;
alter table public.mme_permission_grants enable row level security;
alter table public.mme_integration_entitlements enable row level security;
alter table public.mme_profile_appearance_preferences enable row level security;
alter table public.mme_role_color_registry enable row level security;
alter table public.mme_identity_audit_events enable row level security;

revoke all on public.mme_person_identities from anon, authenticated;
revoke all on public.mme_customer_relationships from anon, authenticated;
revoke all on public.mme_employee_relationships from anon, authenticated;
revoke all on public.mme_roles from anon, authenticated;
revoke all on public.mme_role_assignments from anon, authenticated;
revoke all on public.mme_permission_grants from anon, authenticated;
revoke all on public.mme_integration_entitlements from anon, authenticated;
revoke all on public.mme_profile_appearance_preferences from anon, authenticated;
revoke all on public.mme_role_color_registry from anon, authenticated;
revoke all on public.mme_identity_audit_events from anon, authenticated;
