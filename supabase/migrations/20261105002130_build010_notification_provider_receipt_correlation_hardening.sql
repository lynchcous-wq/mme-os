begin;
create or replace function public.mme_security_notification_ingest_provider_receipt(p_provider text,p_event_id text,p_reference text,p_channel text,p_status text,p_event jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare ev public.mme_security_notification_provider_receipt_events%rowtype; d public.mme_security_notification_escalation_channel_deliveries%rowtype; mapped text; terminal boolean; has_failure boolean;
begin
 if p_provider not in ('resend','twilio','pagerduty','telnyx','push') or p_channel not in ('email','sms','pager','push') or p_status not in ('accepted','delivered','failed','undelivered','read','acknowledged','unknown') or coalesce(p_event_id,'')='' then raise exception 'invalid_provider_receipt'; end if;
 insert into public.mme_security_notification_provider_receipt_events(provider,provider_event_id,provider_reference,channel,normalized_status,raw_event)
 values(p_provider,left(p_event_id,250),left(p_reference,500),p_channel,p_status,coalesce(p_event,'{}'::jsonb))
 on conflict(provider,provider_event_id) do nothing returning * into ev;
 if not found then return jsonb_build_object('result','duplicate'); end if;
 if p_reference is null then
  update public.mme_security_notification_provider_receipt_events set processing_status='unmatched',processed_at=now(),processing_error='provider_reference_missing' where receipt_event_id=ev.receipt_event_id;
  return jsonb_build_object('result','unmatched');
 end if;
 select * into d from public.mme_security_notification_escalation_channel_deliveries
 where channel=p_channel and provider=p_provider and provider_reference=p_reference
 order by updated_at desc limit 1 for update;
 if not found then update public.mme_security_notification_provider_receipt_events set processing_status='unmatched',processed_at=now() where receipt_event_id=ev.receipt_event_id;return jsonb_build_object('result','unmatched'); end if;
 mapped:=case when p_status in ('delivered','read','acknowledged') then 'delivered' when p_status in ('failed','undelivered') then 'failed' else d.status end;
 if mapped='delivered' then
  update public.mme_security_notification_escalation_channel_deliveries set status='delivered',last_error=null,locked_at=null,locked_by=null,updated_at=now() where channel_delivery_id=d.channel_delivery_id;
 elsif mapped='failed' then
  update public.mme_security_notification_escalation_channel_deliveries set status=case when attempt_count>=5 then 'dead_letter' else 'retry' end,next_attempt_at=now()+interval '1 minute',last_error='provider_receipt:'||p_status,locked_at=null,locked_by=null,updated_at=now() where channel_delivery_id=d.channel_delivery_id;
 end if;
 update public.mme_security_notification_provider_receipt_events set channel_delivery_id=d.channel_delivery_id,processing_status='processed',processed_at=now() where receipt_event_id=ev.receipt_event_id;
 select bool_and(status in ('delivered','accepted','dead_letter','skipped')),(bool_or(status in ('dead_letter','skipped'))) into terminal,has_failure from public.mme_security_notification_escalation_channel_deliveries where dispatch_id=d.dispatch_id;
 if terminal then
  update public.mme_security_notification_escalation_dispatch_events set dispatch_status=case when has_failure then 'dead_letter' else 'dispatched' end,updated_at=now(),last_error=case when has_failure then 'one_or_more_required_channels_failed_or_skipped' else null end where dispatch_id=d.dispatch_id;
  if not has_failure then update public.mme_security_notification_acknowledgement_escalations e set escalation_status='issued',issued_at=coalesce(issued_at,now()) from public.mme_security_notification_escalation_dispatch_events q where q.dispatch_id=d.dispatch_id and e.escalation_id=q.escalation_id; end if;
 end if;
 return jsonb_build_object('result','processed','channelDeliveryId',d.channel_delivery_id,'status',mapped);
end $$;
revoke all on function public.mme_security_notification_ingest_provider_receipt(text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mme_security_notification_ingest_provider_receipt(text,text,text,text,text,jsonb) to service_role;
commit;