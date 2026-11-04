-- Build 006: notification inbox read API and access-state enforcement.
begin;

create function public.mme_employee_notification_access_allowed(p_actor_user_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select coalesce((
    select e.employment_status = 'active'
       and s.employee_access_frozen = false
       and s.ceo_user_id is not null
      from public.employee_relationships e
      cross join public.employee_security_settings s
     where e.user_id = p_actor_user_id
       and s.singleton = true
  ),false);
$$;

create function public.mme_list_employee_notifications(
  p_actor_user_id uuid,
  p_limit integer default 30,
  p_before timestamptz default null
)
returns setof public.mme_employee_notifications
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if p_actor_user_id is null or p_limit is null or p_limit not between 1 and 100 then
    raise exception 'Invalid notification inbox request' using errcode = '22023';
  end if;
  if not public.mme_employee_notification_access_allowed(p_actor_user_id) then
    raise exception 'Employee notification access is unavailable' using errcode = '42501';
  end if;

  return query
  select n.*
    from public.mme_employee_notifications n
   where n.recipient_user_id = p_actor_user_id
     and n.dismissed_at is null
     and (p_before is null or n.created_at < p_before)
   order by n.created_at desc, n.id desc
   limit p_limit;
end;
$$;

create or replace function public.mme_mark_employee_notification_read(
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
  if not public.mme_employee_notification_access_allowed(p_actor_user_id) then
    raise exception 'Employee notification access is unavailable' using errcode = '42501';
  end if;
  update public.mme_employee_notifications
     set read_at = coalesce(read_at,now())
   where id = p_notification_id
     and recipient_user_id = p_actor_user_id
     and dismissed_at is null;
  return found;
end;
$$;

create or replace function public.mme_dismiss_employee_notification(
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
  if not public.mme_employee_notification_access_allowed(p_actor_user_id) then
    raise exception 'Employee notification access is unavailable' using errcode = '42501';
  end if;
  update public.mme_employee_notifications
     set dismissed_at = coalesce(dismissed_at,now()),
         read_at = coalesce(read_at,now())
   where id = p_notification_id
     and recipient_user_id = p_actor_user_id
     and dismissed_at is null;
  return found;
end;
$$;

revoke all on function public.mme_employee_notification_access_allowed(uuid) from public,anon,authenticated;
revoke all on function public.mme_list_employee_notifications(uuid,integer,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_mark_employee_notification_read(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_dismiss_employee_notification(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_employee_notification_access_allowed(uuid) to service_role;
grant execute on function public.mme_list_employee_notifications(uuid,integer,timestamptz) to service_role;
grant execute on function public.mme_mark_employee_notification_read(uuid,uuid) to service_role;
grant execute on function public.mme_dismiss_employee_notification(uuid,uuid) to service_role;

comment on function public.mme_list_employee_notifications(uuid,integer,timestamptz) is
  'Server-only, recipient-bound inbox query with bounded pagination; actor must be an active employee and employee access must not be frozen.';
commit;
