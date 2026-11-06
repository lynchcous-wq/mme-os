begin;

-- Durable provider receipt ledger for the escalation-channel delivery pipeline.
create table if not exists public.mme_security_notification_provider_receipt_events (
  receipt_event_id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  provider_reference text,
  channel text not null,
  normalized_status text not null default 'unknown',
  raw_event jsonb not null default '{}'::jsonb,
  channel_delivery_id uuid references public.mme_security_notification_escalation_channel_deliveries(channel_delivery_id) on delete restrict,
  processing_status text not null default 'received',
  processed_at timestamptz,
  processing_error text,
  received_at timestamptz not null default now(),
  constraint mme_security_notification_provider_receipt_provider_check
    check (provider in ('resend','twilio','pagerduty','telnyx','push')),
  constraint mme_security_notification_provider_receipt_channel_check
    check (channel in ('email','sms','pager','push')),
  constraint mme_security_notification_provider_receipt_status_check
    check (normalized_status in ('accepted','delivered','failed','undelivered','read','acknowledged','unknown')),
  constraint mme_security_notification_provider_receipt_processing_check
    check (processing_status in ('received','processed','unmatched','ambiguous'))
);

create unique index if not exists mme_security_notification_provider_receipt_event_uq
  on public.mme_security_notification_provider_receipt_events(provider, provider_event_id);
create index if not exists mme_security_notification_provider_receipt_reference_idx
  on public.mme_security_notification_provider_receipt_events(provider, channel, provider_reference, received_at desc);
create index if not exists mme_security_notification_provider_receipt_unprocessed_idx
  on public.mme_security_notification_provider_receipt_events(processing_status, received_at)
  where processing_status in ('received','unmatched','ambiguous');

alter table public.mme_security_notification_provider_receipt_events enable row level security;
revoke all on public.mme_security_notification_provider_receipt_events from public, anon, authenticated;
grant select, insert, update on public.mme_security_notification_provider_receipt_events to service_role;

create or replace function public.mme_security_notification_ingest_provider_receipt(
  p_provider text,
  p_event_id text,
  p_reference text,
  p_channel text,
  p_status text,
  p_event jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  ev public.mme_security_notification_provider_receipt_events%rowtype;
  d public.mme_security_notification_escalation_channel_deliveries%rowtype;
  match_count integer;
  mapped text;
  all_terminal boolean;
  has_failure boolean;
  result_code text := 'unmatched';
begin
  if p_provider not in ('resend','twilio','pagerduty','telnyx','push')
     or p_channel not in ('email','sms','pager','push')
     or p_status not in ('accepted','delivered','failed','undelivered','read','acknowledged','unknown')
     or coalesce(length(trim(p_event_id)),0)=0
     or length(p_event_id)>250
     or coalesce(length(trim(p_reference)),0)=0
     or length(p_reference)>500 then
    raise exception 'invalid_provider_receipt';
  end if;

  insert into public.mme_security_notification_provider_receipt_events(
    provider,provider_event_id,provider_reference,channel,normalized_status,raw_event
  ) values (
    p_provider,p_event_id,p_reference,p_channel,p_status,coalesce(p_event,'{}'::jsonb)
  )
  on conflict(provider,provider_event_id) do nothing
  returning * into ev;

  if not found then
    return jsonb_build_object('result','duplicate');
  end if;

  select count(*) into match_count
  from public.mme_security_notification_escalation_channel_deliveries
  where channel=p_channel and provider=p_provider and provider_reference=p_reference;

  if match_count=0 then
    update public.mme_security_notification_provider_receipt_events
      set processing_status='unmatched',processed_at=now(),processing_error='provider_reference_not_found'
      where receipt_event_id=ev.receipt_event_id;
    return jsonb_build_object('result','unmatched');
  elsif match_count>1 then
    update public.mme_security_notification_provider_receipt_events
      set processing_status='ambiguous',processed_at=now(),processing_error='provider_reference_not_unique'
      where receipt_event_id=ev.receipt_event_id;
    return jsonb_build_object('result','ambiguous');
  end if;

  select * into d
  from public.mme_security_notification_escalation_channel_deliveries
  where channel=p_channel and provider=p_provider and provider_reference=p_reference
  for update;

  mapped := case
    when p_status in ('delivered','read','acknowledged') then 'delivered'
    when p_status in ('failed','undelivered') then 'failed'
    else d.status
  end;

  -- Provider callbacks can arrive out of order. A delivered channel is terminal:
  -- late failure/queued/sent callbacks are recorded but cannot regress it.
  if d.status='delivered' then
    mapped := 'delivered';
  elsif mapped='delivered' then
    update public.mme_security_notification_escalation_channel_deliveries
      set status='delivered',last_error=null,locked_at=null,locked_by=null,updated_at=now()
      where channel_delivery_id=d.channel_delivery_id;
  elsif mapped='failed' then
    update public.mme_security_notification_escalation_channel_deliveries
      set status=case when attempt_count>=5 then 'dead_letter' else 'retry' end,
          next_attempt_at=now()+interval '1 minute',
          last_error='provider_receipt:'||p_status,
          locked_at=null,locked_by=null,updated_at=now()
      where channel_delivery_id=d.channel_delivery_id;
  end if;

  update public.mme_security_notification_provider_receipt_events
    set channel_delivery_id=d.channel_delivery_id,processing_status='processed',processed_at=now()
    where receipt_event_id=ev.receipt_event_id;

  select bool_and(status in ('delivered','accepted','dead_letter','skipped')),
         coalesce(bool_or(status in ('dead_letter','skipped')),false)
    into all_terminal,has_failure
    from public.mme_security_notification_escalation_channel_deliveries
    where dispatch_id=d.dispatch_id;

  if all_terminal then
    update public.mme_security_notification_escalation_dispatch_events
      set dispatch_status=case when has_failure then 'dead_letter' else 'dispatched' end,
          updated_at=now(),
          last_error=case when has_failure then 'one_or_more_required_channels_failed_or_skipped' else null end
      where dispatch_id=d.dispatch_id;
    if not has_failure then
      update public.mme_security_notification_acknowledgement_escalations e
        set escalation_status='issued',issued_at=coalesce(e.issued_at,now())
        from public.mme_security_notification_escalation_dispatch_events q
        where q.dispatch_id=d.dispatch_id and e.escalation_id=q.escalation_id;
    end if;
  end if;

  result_code := case when d.status='delivered' and mapped='delivered' then 'processed_terminal_preserved' else 'processed' end;
  return jsonb_build_object('result',result_code,'channelDeliveryId',d.channel_delivery_id,'status',mapped);
end
$$;

revoke all on function public.mme_security_notification_ingest_provider_receipt(text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mme_security_notification_ingest_provider_receipt(text,text,text,text,text,jsonb) to service_role;

commit;
