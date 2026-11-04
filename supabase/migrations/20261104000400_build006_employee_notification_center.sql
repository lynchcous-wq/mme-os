-- Build 006: employee in-app notification inbox, generated transactionally from task events.
begin;

create table public.mme_employee_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references public.employee_relationships(user_id) on delete restrict,
  task_id uuid references public.mme_tasks(id) on delete restrict,
  task_event_id bigint references public.mme_task_events(id) on delete restrict,
  notification_type text not null check (notification_type in (
    'task_assigned','task_created','task_status_changed','task_due_soon','task_overdue','task_reassigned'
  )),
  title text not null check (length(btrim(title)) between 1 and 180),
  body text not null default '' check (length(body) <= 1000),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  idempotency_key text not null unique check (length(btrim(idempotency_key)) between 8 and 240),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  dismissed_at timestamptz
);
create index mme_employee_notifications_inbox_idx
  on public.mme_employee_notifications(recipient_user_id, created_at desc)
  where dismissed_at is null;
create index mme_employee_notifications_unread_idx
  on public.mme_employee_notifications(recipient_user_id, created_at desc)
  where read_at is null and dismissed_at is null;

alter table public.mme_employee_notifications enable row level security;
alter table public.mme_employee_notifications force row level security;
revoke all on public.mme_employee_notifications from public, anon, authenticated;
grant all on public.mme_employee_notifications to service_role;

create function public.mme_emit_task_notification(
  p_recipient_user_id uuid,
  p_task_id uuid,
  p_task_event_id bigint,
  p_notification_type text,
  p_title text,
  p_body text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if p_recipient_user_id is null or p_task_id is null or p_task_event_id is null
     or p_notification_type not in ('task_assigned','task_created','task_status_changed','task_due_soon','task_overdue','task_reassigned')
     or p_title is null or length(btrim(p_title)) not between 1 and 180
     or coalesce(length(p_body),0) > 1000
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 8 and 240 then
    raise exception 'Invalid task notification' using errcode = '22023';
  end if;

  insert into public.mme_employee_notifications(
    recipient_user_id,task_id,task_event_id,notification_type,title,body,payload,idempotency_key
  )
  select p_recipient_user_id,p_task_id,p_task_event_id,p_notification_type,btrim(p_title),
         coalesce(p_body,''),'{}'::jsonb,btrim(p_idempotency_key)
   where exists (
     select 1 from public.employee_relationships e
      where e.user_id = p_recipient_user_id and e.employment_status = 'active'
   )
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.mme_employee_notifications
     where idempotency_key = btrim(p_idempotency_key);
  end if;
  return v_id;
end;
$$;

create function public.mme_task_event_notify_employees()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.mme_tasks%rowtype;
  v_assignee uuid;
  v_recipient uuid;
  v_type text;
  v_title text;
  v_body text;
begin
  select * into v_task from public.mme_tasks where id = new.task_id;
  if not found then return new; end if;

  if new.event_type = 'task.assigned' then
    select assignee_user_id into v_assignee
      from public.mme_task_assignments where id = new.assignment_id;
    if v_assignee is not null then
      perform public.mme_emit_task_notification(
        v_assignee,new.task_id,new.id,'task_assigned','A task was assigned to you',
        v_task.title,'task-event:'||new.id::text||':assignee'
      );
    end if;

  elsif new.event_type = 'task.created' then
    if new.actor_user_id is not null then
      perform public.mme_emit_task_notification(
        new.actor_user_id,new.task_id,new.id,'task_created','Task created',
        v_task.title,'task-event:'||new.id::text||':creator'
      );
    end if;

  elsif new.event_type = 'task.status_changed' then
    for v_recipient in
      select distinct recipient_id
      from (
        select v_task.created_by_user_id as recipient_id
        union all
        select a.assignee_user_id
          from public.mme_task_assignments a
         where a.task_id = new.task_id and a.ended_at is null
      ) recipients
      where recipient_id is not null
    loop
      perform public.mme_emit_task_notification(
        v_recipient,new.task_id,new.id,'task_status_changed','Task status updated',
        v_task.title||' — '||coalesce(new.event_data->>'to_status','updated'),
        'task-event:'||new.id::text||':user:'||v_recipient::text
      );
    end loop;
  end if;

  return new;
end;
$$;

create trigger mme_task_event_notifications_after_insert
after insert on public.mme_task_events
for each row execute function public.mme_task_event_notify_employees();

create function public.mme_mark_employee_notification_read(
  p_actor_user_id uuid,
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_actor_user_id is null or p_notification_id is null then return false; end if;
  update public.mme_employee_notifications
     set read_at = coalesce(read_at,now())
   where id = p_notification_id
     and recipient_user_id = p_actor_user_id
     and dismissed_at is null;
  return found;
end;
$$;

create function public.mme_dismiss_employee_notification(
  p_actor_user_id uuid,
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_actor_user_id is null or p_notification_id is null then return false; end if;
  update public.mme_employee_notifications
     set dismissed_at = coalesce(dismissed_at,now()),
         read_at = coalesce(read_at,now())
   where id = p_notification_id
     and recipient_user_id = p_actor_user_id
     and dismissed_at is null;
  return found;
end;
$$;

revoke all on function public.mme_emit_task_notification(uuid,uuid,bigint,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_task_event_notify_employees() from public,anon,authenticated;
revoke all on function public.mme_mark_employee_notification_read(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_dismiss_employee_notification(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_emit_task_notification(uuid,uuid,bigint,text,text,text,text) to service_role;
grant execute on function public.mme_mark_employee_notification_read(uuid,uuid) to service_role;
grant execute on function public.mme_dismiss_employee_notification(uuid,uuid) to service_role;

comment on table public.mme_employee_notifications is
  'Build 006 in-app employee inbox. Task events create deduplicated notifications transactionally; read/dismiss actions are recipient-bound and server-only.';
comment on function public.mme_task_event_notify_employees() is
  'Transactional task-event notification fan-out; no external provider calls occur in the database trigger.';

commit;
