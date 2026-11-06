begin;
create or replace function public.mme_security_notification_materialize_escalation_dispatch()
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 insert into public.mme_security_notification_escalation_dispatch_events(escalation_id,alert_id,target_role)
 select e.escalation_id,e.alert_id,r
 from public.mme_security_notification_acknowledgement_escalations e
 join public.mme_security_notification_escalation_alerts a on a.alert_id=e.alert_id
 cross join lateral unnest(coalesce(a.target_roles,'{}'::text[])) r
 where e.escalation_status in ('pending','processing')
 and a.acknowledgement_status='overdue'
 and e.due_at<=now()
 on conflict(escalation_id,target_role) do nothing;
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function public.mme_security_notification_materialize_escalation_dispatch() from public,anon,authenticated;
grant execute on function public.mme_security_notification_materialize_escalation_dispatch() to service_role;
create or replace function public.mme_security_notification_transfer_ownership(p_alert uuid,p_actor uuid,p_actor_roles text[],p_new_owner uuid,p_new_role text,p_reason text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare old public.mme_security_notification_incident_ownership%rowtype; new_id uuid; alert_roles text[];
begin
 if not (coalesce(p_actor_roles,'{}'::text[]) && array['ceo','cio','it_admin','operations_manager','store_manager']::text[]) then raise exception 'ownership_transfer_forbidden'; end if;
 if p_new_role not in ('ceo','cio','it_admin','operations_manager','store_manager') then raise exception 'invalid_owner_role'; end if;
 select target_roles into alert_roles from public.mme_security_notification_escalation_alerts where alert_id=p_alert for update;
 if not found then raise exception 'alert_not_found'; end if;
 if p_new_owner is not null and not exists(select 1 from auth.users where id=p_new_owner) then raise exception 'owner_user_not_found'; end if;
 select * into old from public.mme_security_notification_incident_ownership where alert_id=p_alert and ownership_status='active' for update;
 if found then update public.mme_security_notification_incident_ownership set ownership_status='transferred' where ownership_id=old.ownership_id; end if;
 insert into public.mme_security_notification_incident_ownership(alert_id,owner_user_id,owner_role,assigned_by,assignment_reason,due_at) values(p_alert,p_new_owner,p_new_role,p_actor,left(p_reason,1000),now()+interval '30 minutes') returning ownership_id into new_id;
 insert into public.mme_security_notification_ownership_events(alert_id,previous_owner,new_owner,actor_id,event_type,reason) values(p_alert,old.owner_user_id,p_new_owner,p_actor,case when p_actor_roles&&array['ceo','cio']::text[] then 'executive_override' else 'transferred' end,left(p_reason,1000));
 return jsonb_build_object('result','transferred','ownershipId',new_id);
end $$;
revoke all on function public.mme_security_notification_transfer_ownership(uuid,uuid,text[],uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_security_notification_transfer_ownership(uuid,uuid,text[],uuid,text,text,uuid) to service_role;
commit;