-- Build 006: route approval requests and decisions into the employee inbox.
begin;

alter table public.mme_employee_notifications
  add column approval_request_id uuid references public.mme_task_approval_requests(id) on delete restrict,
  add column approval_event_id bigint references public.mme_task_approval_events(id) on delete restrict;

alter table public.mme_employee_notifications
  drop constraint if exists mme_employee_notifications_notification_type_check;
alter table public.mme_employee_notifications
  add constraint mme_employee_notifications_notification_type_check
  check (notification_type in (
    'task_assigned','task_created','task_status_changed','task_due_soon','task_overdue','task_reassigned',
    'approval_requested','approval_approved','approval_rejected','approval_cancelled','approval_expired'
  ));

create index mme_employee_notifications_approval_request_idx
  on public.mme_employee_notifications(approval_request_id,created_at desc)
  where approval_request_id is not null;

create function public.mme_emit_approval_notification(
  p_recipient_user_id uuid,
  p_request_id uuid,
  p_event_id bigint,
  p_type text,
  p_title text,
  p_body text,
  p_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
  v_notification_id uuid;
begin
  if p_recipient_user_id is null or p_request_id is null or p_event_id is null
     or p_type not in ('approval_requested','approval_approved','approval_rejected','approval_cancelled','approval_expired')
     or p_title is null or length(btrim(p_title)) not between 1 and 180
     or coalesce(length(p_body),0)>1000
     or p_key is null or length(btrim(p_key)) not between 8 and 240 then
    raise exception 'Invalid approval notification' using errcode='22023';
  end if;

  select task_id into v_task_id
    from public.mme_task_approval_requests where id=p_request_id;
  if v_task_id is null then raise exception 'Approval request not found' using errcode='P0002'; end if;

  insert into public.mme_employee_notifications(
    recipient_user_id,task_id,approval_request_id,approval_event_id,
    notification_type,title,body,payload,idempotency_key
  )
  select p_recipient_user_id,v_task_id,p_request_id,p_event_id,p_type,btrim(p_title),
         coalesce(p_body,''),'{}'::jsonb,btrim(p_key)
   where exists (
     select 1 from public.employee_relationships e
     cross join public.employee_security_settings s
      where e.user_id=p_recipient_user_id
        and e.employment_status='active'
        and s.singleton=true
        and s.employee_access_frozen=false
        and s.ceo_user_id is not null
   )
  on conflict (idempotency_key) do nothing
  returning id into v_notification_id;

  if v_notification_id is null then
    select id into v_notification_id from public.mme_employee_notifications
     where idempotency_key=btrim(p_key);
  end if;
  return v_notification_id;
end;
$$;

create function public.mme_task_approval_event_notify_employees()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.mme_task_approval_requests%rowtype;
  v_task public.mme_tasks%rowtype;
  v_recipient uuid;
  v_ceo_user_id uuid;
begin
  select * into v_request from public.mme_task_approval_requests
   where id=new.approval_request_id;
  if not found then return new; end if;

  select * into v_task from public.mme_tasks where id=v_request.task_id;
  if not found then return new; end if;

  if new.event_type='requested' then
    select ceo_user_id into v_ceo_user_id
      from public.employee_security_settings where singleton=true;

    for v_recipient in
      select distinct candidates.user_id
      from (
        select v_ceo_user_id as user_id
        union all
        select g.employee_user_id
          from public.employee_permission_grants g
         where g.permission_key='tasks.approval.decide'
           and g.revoked_at is null
           and (g.expires_at is null or g.expires_at>now())
           and (
             g.scope='{}'::jsonb
             or (
               (not (g.scope ? 'department') or g.scope->>'department'=v_task.department)
               and
               (not (g.scope ? 'location_id')
                 or (v_task.location_id is not null and g.scope->>'location_id'=v_task.location_id::text))
             )
           )
      ) candidates
      join public.employee_relationships e on e.user_id=candidates.user_id
      join public.employee_security_settings s on s.singleton=true
      where candidates.user_id is not null
        and candidates.user_id<>v_request.requested_by_user_id
        and e.employment_status='active'
        and s.employee_access_frozen=false
    loop
      perform public.mme_emit_approval_notification(
        v_recipient,v_request.id,new.id,'approval_requested',
        'Approval requested',v_task.title||' — '||v_request.approval_type,
        'approval-event:'||new.id::text||':recipient:'||v_recipient::text
      );
    end loop;

  elsif new.event_type in ('approved','rejected','cancelled','expired') then
    perform public.mme_emit_approval_notification(
      v_request.requested_by_user_id,v_request.id,new.id,
      case new.event_type
        when 'approved' then 'approval_approved'
        when 'rejected' then 'approval_rejected'
        when 'cancelled' then 'approval_cancelled'
        else 'approval_expired'
      end,
      case new.event_type
        when 'approved' then 'Approval approved'
        when 'rejected' then 'Approval rejected'
        when 'cancelled' then 'Approval request cancelled'
        else 'Approval request expired'
      end,
      v_task.title||' — '||v_request.approval_type,
      'approval-event:'||new.id::text||':requester'
    );
  end if;

  return new;
end;
$$;

create trigger mme_task_approval_event_notifications_after_insert
after insert on public.mme_task_approval_events
for each row execute function public.mme_task_approval_event_notify_employees();

revoke all on function public.mme_emit_approval_notification(uuid,uuid,bigint,text,text,text,text)
  from public,anon,authenticated;
revoke all on function public.mme_task_approval_event_notify_employees()
  from public,anon,authenticated;
grant execute on function public.mme_emit_approval_notification(uuid,uuid,bigint,text,text,text,text)
  to service_role;

comment on function public.mme_task_approval_event_notify_employees() is
  'Build 006: transactionally notifies scoped active approvers on request and requester on final decision; external delivery is handled separately.';
commit;
