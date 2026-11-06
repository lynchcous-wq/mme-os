begin;
alter table public.mme_security_notification_delivery_jobs drop constraint if exists mme_security_notification_delivery_jobs_delivery_status_check;
alter table public.mme_security_notification_delivery_jobs add constraint mme_security_notification_delivery_jobs_delivery_status_check check(delivery_status in ('queued','processing','accepted','sent','delivered','bounced','undelivered','retry','failed','skipped','dead_letter'));
alter table public.mme_security_notification_delivery_jobs add column if not exists provider_status text,add column if not exists provider_status_at timestamptz,add column if not exists last_receipt_at timestamptz;
create table public.mme_security_notification_provider_receipts(
 receipt_id uuid primary key default gen_random_uuid(),
 provider text not null,
 provider_event_id text not null,
 delivery_id uuid references public.mme_security_notification_delivery_jobs(delivery_id) on delete restrict,
 provider_reference text,
 event_type text not null,
 normalized_status text not null check(normalized_status in ('accepted','sent','delivered','bounced','undelivered','failed','complained','unknown')),
 payload_digest text not null,
 received_at timestamptz not null default now(),
 processed_at timestamptz,
 processing_result text,
 unique(provider,provider_event_id)
);
create index mme_security_notification_receipts_delivery_idx on public.mme_security_notification_provider_receipts(delivery_id,received_at desc);
alter table public.mme_security_notification_provider_receipts enable row level security;
revoke all on public.mme_security_notification_provider_receipts from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_provider_receipts to service_role;
create or replace function public.mme_security_notification_apply_provider_receipt(
 p_provider text,p_event_id text,p_provider_reference text,p_event_type text,p_status text,p_digest text
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare rid uuid; did uuid; current_status text; result text:='unmatched';
begin
 if coalesce(length(p_event_id),0)=0 or coalesce(length(p_digest),0)<>64 then raise exception 'invalid_provider_receipt'; end if;
 insert into public.mme_security_notification_provider_receipts(provider,provider_event_id,provider_reference,event_type,normalized_status,payload_digest)
 values(left(p_provider,40),left(p_event_id,250),left(p_provider_reference,250),left(p_event_type,150),p_status,p_digest)
 on conflict(provider,provider_event_id) do nothing returning receipt_id into rid;
 if rid is null then return jsonb_build_object('result','duplicate'); end if;
 select delivery_id into did from public.mme_security_notification_delivery_jobs where provider_reference=p_provider_reference and provider= p_provider order by created_at desc limit 1 for update;
 if did is not null then
  select delivery_status into current_status from public.mme_security_notification_delivery_jobs where delivery_id=did;
  if p_status='delivered' then
   update public.mme_security_notification_delivery_jobs set delivery_status='delivered',delivered_at=coalesce(delivered_at,now()),provider_status=p_event_type,provider_status_at=now(),last_receipt_at=now(),updated_at=now(),last_error_code=null where delivery_id=did;
  elsif p_status in ('bounced','undelivered','failed','complained') then
   update public.mme_security_notification_delivery_jobs set delivery_status=case when delivery_status='delivered' then 'delivered' else p_status end,provider_status=p_event_type,provider_status_at=now(),last_receipt_at=now(),last_error_code=left(p_event_type,100),updated_at=now() where delivery_id=did;
  elsif p_status in ('sent','accepted') and current_status not in ('delivered','bounced','undelivered','failed','complained') then
   update public.mme_security_notification_delivery_jobs set delivery_status=p_status,provider_status=p_event_type,provider_status_at=now(),last_receipt_at=now(),updated_at=now() where delivery_id=did;
  else
   update public.mme_security_notification_delivery_jobs set last_receipt_at=now(),provider_status=p_event_type,provider_status_at=now(),updated_at=now() where delivery_id=did;
  end if;
  result:='matched';
 end if;
 update public.mme_security_notification_provider_receipts set delivery_id=did,processed_at=now(),processing_result=result where receipt_id=rid;
 return jsonb_build_object('result',result,'deliveryId',did);
end $$;
revoke all on function public.mme_security_notification_apply_provider_receipt(text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_security_notification_apply_provider_receipt(text,text,text,text,text,text) to service_role;
commit;