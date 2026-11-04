-- Build 006: centralized task, assignment-history, and task-audit foundation.
-- Business task records remain in MME OS; GitHub Issues/Projects are not task storage.
begin;

create table public.mme_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) between 3 and 180),
  instructions text not null default '' check (length(instructions) <= 8000),
  department text not null check (department ~ '^[a-z][a-z0-9_-]{1,63}$'),
  location_id uuid,
  priority text not null default 'normal'
    check (priority in ('critical','high','normal','low')),
  status text not null default 'not_started'
    check (status in ('not_started','assigned','accepted','in_progress','pending_information',
                      'pending_approval','completed','rejected','cancelled')),
  starts_at timestamptz,
  due_at timestamptz,
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes between 1 and 10080),
  related_record_type text check (related_record_type is null or related_record_type ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  related_record_id text check (related_record_id is null or length(related_record_id) between 1 and 180),
  source_event_id text,
  idempotency_key text unique,
  created_by_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  check (due_at is null or starts_at is null or due_at >= starts_at),
  check ((related_record_type is null) = (related_record_id is null)),
  check ((status = 'completed') = (completed_at is not null)),
  check ((status = 'cancelled') = (cancelled_at is not null))
);

create index mme_tasks_department_status_due_idx
  on public.mme_tasks(department, status, due_at);
create index mme_tasks_location_status_idx
  on public.mme_tasks(location_id, status, created_at desc);
create index mme_tasks_created_by_idx
  on public.mme_tasks(created_by_user_id, created_at desc);
create unique index mme_tasks_source_event_uidx
  on public.mme_tasks(source_event_id) where source_event_id is not null;

create table public.mme_task_assignments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.mme_tasks(id) on delete restrict,
  assignee_user_id uuid not null references public.employee_relationships(user_id) on delete restrict,
  assigned_by_user_id uuid not null references auth.users(id) on delete restrict,
  assignment_scope jsonb not null default '{}'::jsonb
    check (jsonb_typeof(assignment_scope) = 'object'),
  assigned_at timestamptz not null default now(),
  accepted_at timestamptz,
  ended_at timestamptz,
  end_reason text check (end_reason is null or length(btrim(end_reason)) between 3 and 500),
  check ((ended_at is null and end_reason is null) or (ended_at is not null and end_reason is not null)),
  check (accepted_at is null or accepted_at >= assigned_at)
);
create unique index mme_task_assignments_one_active_idx
  on public.mme_task_assignments(task_id) where ended_at is null;
create index mme_task_assignments_assignee_active_idx
  on public.mme_task_assignments(assignee_user_id, assigned_at desc) where ended_at is null;

create table public.mme_task_events (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.mme_tasks(id) on delete restrict,
  assignment_id uuid references public.mme_task_assignments(id) on delete restrict,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  actor_user_id uuid references auth.users(id) on delete set null,
  reason text,
  event_data jsonb not null default '{}'::jsonb check (jsonb_typeof(event_data) = 'object'),
  correlation_id text,
  created_at timestamptz not null default now()
);
create index mme_task_events_task_created_idx on public.mme_task_events(task_id, created_at desc);

create function public.mme_task_events_immutable()
returns trigger language plpgsql set search_path = ''
as $$
begin
  raise exception 'Task events are append-only';
end;
$$;
create trigger mme_task_events_no_update_delete
before update or delete on public.mme_task_events
for each row execute function public.mme_task_events_immutable();

alter table public.mme_tasks enable row level security;
alter table public.mme_tasks force row level security;
alter table public.mme_task_assignments enable row level security;
alter table public.mme_task_assignments force row level security;
alter table public.mme_task_events enable row level security;
alter table public.mme_task_events force row level security;

revoke all on public.mme_tasks, public.mme_task_assignments, public.mme_task_events from public, anon, authenticated;
grant all on public.mme_tasks, public.mme_task_assignments, public.mme_task_events to service_role;
revoke all on function public.mme_task_events_immutable() from public, anon, authenticated;

comment on table public.mme_tasks is
  'Build 006 authoritative business task records; server-only access, Identity Matrix authorization required.';
comment on table public.mme_task_assignments is
  'Build 006 assignment history; at most one active assignee per task.';
comment on table public.mme_task_events is
  'Build 006 append-only task history; event payloads must exclude secrets and unnecessary personal data.';

commit;
