-- Build 004 canonical person/login identity bridge.
-- Additive compatibility phase: no inferred account linking and no destructive
-- replacement of the existing Supabase Auth UUID references.
begin;

create table public.mme_person_identities (
  person_id uuid primary key default gen_random_uuid(),
  lifecycle_status text not null default 'active'
    check (lifecycle_status in ('active','locked','merged','archived')),
  merged_into_person_id uuid references public.mme_person_identities(person_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (lifecycle_status = 'merged' and merged_into_person_id is not null
      and merged_into_person_id <> person_id)
    or (lifecycle_status <> 'merged' and merged_into_person_id is null)
  )
);

create table public.mme_login_identities (
  login_identity_id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.mme_person_identities(person_id) on delete restrict,
  provider_key text not null
    check (provider_key ~ '^[a-z][a-z0-9_-]{1,31}$'),
  provider_subject text not null
    check (length(provider_subject) between 1 and 512),
  auth_user_id uuid references auth.users(id) on delete restrict,
  link_status text not null default 'pending'
    check (link_status in ('pending','verified','revoked','conflicted')),
  verified_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider_key, provider_subject),
  check (
    (provider_key = 'supabase' and auth_user_id is not null
      and provider_subject = auth_user_id::text)
    or (provider_key <> 'supabase' and auth_user_id is null)
  ),
  check (
    (link_status = 'verified' and verified_at is not null and revoked_at is null)
    or (link_status = 'revoked' and revoked_at is not null)
    or (link_status in ('pending','conflicted') and revoked_at is null)
  )
);

create unique index mme_login_identities_auth_user_uidx
  on public.mme_login_identities(auth_user_id)
  where auth_user_id is not null;

create index mme_login_identities_person_status_idx
  on public.mme_login_identities(person_id, link_status);

-- Nullable compatibility references intentionally remain unpopulated until a
-- separately reviewed, proofed identity mapping/backfill is approved.
alter table public.employee_relationships
  add column person_id uuid references public.mme_person_identities(person_id) on delete restrict;
create index employee_relationships_person_id_idx
  on public.employee_relationships(person_id)
  where person_id is not null;

alter table public.employee_permission_grants
  add column person_id uuid references public.mme_person_identities(person_id) on delete restrict,
  add column granted_by_person_id uuid references public.mme_person_identities(person_id) on delete restrict,
  add column revoked_by_person_id uuid references public.mme_person_identities(person_id) on delete restrict;
create index employee_permission_grants_person_permission_idx
  on public.employee_permission_grants(person_id, permission_key)
  where person_id is not null and revoked_at is null;

alter table public.employee_security_settings
  add column ceo_person_id uuid references public.mme_person_identities(person_id) on delete restrict;

alter table public.employee_access_audit_events
  add column actor_person_id uuid references public.mme_person_identities(person_id) on delete restrict,
  add column target_employee_person_id uuid references public.mme_person_identities(person_id) on delete restrict;

create function public.mme_person_identity_set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger mme_person_identities_updated_at
before update on public.mme_person_identities
for each row execute function public.mme_person_identity_set_updated_at();

create trigger mme_login_identities_updated_at
before update on public.mme_login_identities
for each row execute function public.mme_person_identity_set_updated_at();

-- Server-only compatibility resolver. The input must be derived by trusted
-- server code from the validated provider session; never accept browser input.
create function public.mme_resolve_person_for_auth_subject(p_auth_user_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_person_id uuid;
begin
  if p_auth_user_id is null then
    return null;
  end if;

  select l.person_id
    into v_person_id
    from public.mme_login_identities l
    join public.mme_person_identities p
      on p.person_id = l.person_id
   where l.provider_key = 'supabase'
     and l.auth_user_id = p_auth_user_id
     and l.provider_subject = p_auth_user_id::text
     and l.link_status = 'verified'
     and l.verified_at is not null
     and l.revoked_at is null
     and p.lifecycle_status = 'active';

  if not found then
    return null;
  end if;

  return v_person_id;
end;
$$;

alter table public.mme_person_identities enable row level security;
alter table public.mme_person_identities force row level security;
alter table public.mme_login_identities enable row level security;
alter table public.mme_login_identities force row level security;

revoke all on public.mme_person_identities from public, anon, authenticated;
revoke all on public.mme_login_identities from public, anon, authenticated;
revoke all on function public.mme_resolve_person_for_auth_subject(uuid)
  from public, anon, authenticated;
grant execute on function public.mme_resolve_person_for_auth_subject(uuid)
  to service_role;

comment on table public.mme_person_identities is
  'Build 004 stable MME person identity; private, server-governed, distinct from provider login subjects.';
comment on table public.mme_login_identities is
  'Build 004 verified provider-subject-to-person mapping; no email-based auto-linking.';
comment on function public.mme_resolve_person_for_auth_subject(uuid) is
  'Server-only compatibility resolver. Returns only an active person with one verified, non-revoked Supabase login mapping.';

commit;
