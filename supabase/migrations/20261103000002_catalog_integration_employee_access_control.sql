begin;

-- Employee access is a relationship layered on the person identity in auth.users.
-- It is deliberately separate from customer account status and customer data.
create table public.employee_relationships (
  user_id uuid primary key references auth.users(id) on delete restrict,
  employment_status text not null default 'active'
    check (employment_status in ('active','suspended','terminated')),
  employee_number text unique,
  department text,
  job_title text,
  hired_at timestamptz,
  terminated_at timestamptz,
  status_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (employment_status = 'terminated' and terminated_at is not null)
    or (employment_status <> 'terminated' and terminated_at is null)
  )
);

-- Direct grants are explicit, auditable and optionally scoped/expiring.
-- No role or permission can be self-assigned by an employee.
create table public.employee_permission_grants (
  id uuid primary key default gen_random_uuid(),
  employee_user_id uuid not null references public.employee_relationships(user_id) on delete restrict,
  permission_key text not null
    check (permission_key ~ '^[a-z][a-z0-9_.:-]{1,95}$'),
  scope jsonb not null default '{}'::jsonb
    check (jsonb_typeof(scope) = 'object'),
  granted_by_user_id uuid not null references auth.users(id) on delete restrict,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by_user_id uuid references auth.users(id) on delete restrict,
  reason text not null,
  check ((revoked_at is null and revoked_by_user_id is null)
      or (revoked_at is not null and revoked_by_user_id is not null)),
  check (expires_at is null or expires_at > granted_at)
);
create index employee_permission_grants_lookup_idx
  on public.employee_permission_grants(employee_user_id, permission_key)
  where revoked_at is null;

-- CEO identity is provisioned out-of-band after verifying the real CEO account.
-- A null CEO user_id intentionally leaves privileged actions disabled.
create table public.employee_security_settings (
  singleton boolean primary key default true check (singleton),
  ceo_user_id uuid references auth.users(id) on delete restrict,
  employee_access_frozen boolean not null default false,
  freeze_reason text,
  updated_at timestamptz not null default now(),
  check (
    (employee_access_frozen = false and freeze_reason is null)
    or (employee_access_frozen = true and freeze_reason is not null)
  )
);
insert into public.employee_security_settings(singleton, ceo_user_id)
values (true, null)
on conflict (singleton) do nothing;

create table public.employee_access_audit_events (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  target_employee_user_id uuid references public.employee_relationships(user_id) on delete restrict,
  event_type text not null,
  reason text not null,
  event_data jsonb not null default '{}'::jsonb
    check (jsonb_typeof(event_data) = 'object'),
  created_at timestamptz not null default now()
);
create index employee_access_audit_target_created_idx
  on public.employee_access_audit_events(target_employee_user_id, created_at desc);

create function public.mme_employee_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
create trigger employee_relationships_updated_at
before update on public.employee_relationships
for each row execute function public.mme_employee_set_updated_at();
create trigger employee_security_settings_updated_at
before update on public.employee_security_settings
for each row execute function public.mme_employee_set_updated_at();

create function public.mme_employee_audit_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'Employee access audit events are append-only';
end;
$$;
create trigger employee_access_audit_no_update_delete
before update or delete on public.employee_access_audit_events
for each row execute function public.mme_employee_audit_immutable();

-- Fail closed: no browser role receives direct table policies.
-- Trusted server code must verify identity, relationship status, grants,
-- CEO authority and object scope before using a server-only database client.
alter table public.employee_relationships enable row level security;
alter table public.employee_relationships force row level security;
alter table public.employee_permission_grants enable row level security;
alter table public.employee_permission_grants force row level security;
alter table public.employee_security_settings enable row level security;
alter table public.employee_security_settings force row level security;
alter table public.employee_access_audit_events enable row level security;
alter table public.employee_access_audit_events force row level security;

comment on table public.employee_relationships is
  'Employee relationship independent of customer account identity/status.';
comment on table public.employee_permission_grants is
  'Explicit server-enforced employee permission grants; never trust client role claims.';
comment on table public.employee_security_settings is
  'Singleton CEO control record; CEO must be provisioned out-of-band; null CEO fails closed.';
comment on table public.employee_access_audit_events is
  'Append-only audit trail for employee access and permission changes.';

commit;
