begin;
create or replace function public.mme_warranty_api_claim_security_notifications(p_batch_size integer default 50)
returns setof public.mme_warranty_api_security_notification_outbox language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_batch_size<1 or p_batch_size>200 then raise exception 'invalid_batch_size'; end if;
 return query with due as (
 select notification_id from public.mme_warranty_api_security_notification_outbox
 where status in ('pending','retry') and next_attempt_at<=now() and attempt_count<5
 order by next_attempt_at,created_at for update skip locked limit p_batch_size
 ) update public.mme_warranty_api_security_notification_outbox o
 set status='sending',attempt_count=o.attempt_count+1 from due
 where o.notification_id=due.notification_id returning o.*;
end $$;
create or replace function public.mme_warranty_api_finish_security_notification(p_notification_id uuid,p_success boolean,p_provider text,p_provider_message_id text default null,p_error_code text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v record; v_outcome text; v_status text;
begin
 select * into v from public.mme_warranty_api_security_notification_outbox where notification_id=p_notification_id for update;
 if not found or v.status<>'sending' then raise exception 'notification_not_sending'; end if;
 v_outcome:=case when p_success then 'sent' when v.attempt_count>=5 then 'failed' else 'retry' end;
 v_status:=v_outcome;
 update public.mme_warranty_api_security_notification_outbox set status=v_status,provider_message_id=case when p_success then p_provider_message_id else provider_message_id end,last_error_code=case when p_success then null else left(coalesce(p_error_code,'delivery_failed'),80) end,sent_at=case when p_success then now() else sent_at end,next_attempt_at=case when p_success then next_attempt_at else now()+make_interval(mins=>least(360,5*(2^least(v.attempt_count,6))::integer)) end where notification_id=p_notification_id;
 insert into public.mme_warranty_api_security_notification_attempts(notification_id,attempt_number,outcome,provider,provider_message_id,error_code)
 values(p_notification_id,v.attempt_count,v_outcome,coalesce(p_provider,'unconfigured'),p_provider_message_id,case when p_success then null else left(coalesce(p_error_code,'delivery_failed'),80) end) on conflict(notification_id,attempt_number) do nothing;
 insert into public.mme_warranty_api_security_escalation_events(incident_id,event_type,severity,reason_code)
 select v.incident_id,case when p_success then 'notification_sent' else 'notification_failed' end,i.severity,case when p_success then 'provider_accepted' else 'provider_delivery_failed' end from public.mme_warranty_api_security_incidents i where i.incident_id=v.incident_id;
end $$;
revoke all on function public.mme_warranty_api_claim_security_notifications(integer) from public,anon,authenticated;
revoke all on function public.mme_warranty_api_finish_security_notification(uuid,boolean,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_claim_security_notifications(integer),public.mme_warranty_api_finish_security_notification(uuid,boolean,text,text,text) to service_role;
commit;