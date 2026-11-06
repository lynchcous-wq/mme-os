begin;
alter table public.mme_warranty_api_security_delivery_attempts drop constraint if exists mme_warranty_api_security_delivery_attempts_provider_check;
alter table public.mme_warranty_api_security_delivery_attempts add constraint mme_warranty_api_security_delivery_attempts_provider_check check(provider in ('resend','sendgrid','twilio','telnyx','in_app'));
create table public.mme_warranty_api_security_provider_receipts(receipt_id bigint generated always as identity primary key,provider text not null check(provider in ('resend','twilio')),provider_event_id text not null,event_type text not null,provider_reference text,delivery_id uuid references public.mme_warranty_api_security_alert_deliveries(delivery_id) on delete restrict,payload_digest text not null,received_at timestamptz not null default now(),unique(provider,provider_event_id));
alter table public.mme_warranty_api_security_provider_receipts enable row level security;
revoke all on public.mme_warranty_api_security_provider_receipts from public,anon,authenticated;
grant select,insert on public.mme_warranty_api_security_provider_receipts to service_role;
create or replace function public.mme_warranty_api_security_apply_provider_receipt(p_provider text,p_event_id text,p_event_type text,p_provider_reference text,p_payload_digest text)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_delivery uuid; v_status text; v_alert uuid; v_count integer;
begin
 if p_provider not in ('resend','twilio') or length(coalesce(p_event_id,''))<1 then raise exception 'invalid_provider_receipt'; end if;
 select delivery_id into v_delivery from public.mme_warranty_api_security_alert_deliveries where provider_reference=p_provider_reference for update;
 insert into public.mme_warranty_api_security_provider_receipts(provider,provider_event_id,event_type,provider_reference,delivery_id,payload_digest)
 values(p_provider,p_event_id,p_event_type,p_provider_reference,v_delivery,p_payload_digest) on conflict(provider,provider_event_id) do nothing;
 get diagnostics v_count=row_count;
 if v_count=0 then return 'duplicate'; end if;
 if v_delivery is null then return 'unmatched'; end if;
 v_status:=case when p_event_type in ('email.delivered','delivered','message.delivered') then 'delivered' when p_event_type in ('email.bounced','email.failed','failed','undelivered','message.failed') then 'failed' else null end;
 if v_status is not null then
  update public.mme_warranty_api_security_alert_deliveries set delivery_status=v_status,delivered_at=case when v_status='delivered' then now() else delivered_at end,last_error_code=case when v_status='failed' then p_event_type else last_error_code end where delivery_id=v_delivery;
  select alert_id into v_alert from public.mme_warranty_api_security_alert_deliveries where delivery_id=v_delivery;
  insert into public.mme_warranty_api_security_alert_events(alert_id,event_type,details) values(v_alert,'delivery_attempted',jsonb_build_object('provider',p_provider,'eventType',p_event_type,'providerReference',p_provider_reference,'status',v_status));
 end if;
 return coalesce(v_status,'recorded');
end $$;
revoke all on function public.mme_warranty_api_security_apply_provider_receipt(text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_security_apply_provider_receipt(text,text,text,text,text) to service_role;
commit;
