-- Build 001: verified Stripe dispute event ledger and order-review flag.
-- Disputes never automatically refund, restock, or release inventory.
create table public.mme_payment_disputes (
 id uuid primary key default gen_random_uuid(),
 provider text not null check(provider='stripe'),
 provider_dispute_id text not null check(length(btrim(provider_dispute_id)) between 5 and 255),
 provider_event_id text not null check(length(btrim(provider_event_id)) between 5 and 255),
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 payment_intent_id text not null,
 dispute_status text not null check(dispute_status in ('warning_needs_response','needs_response','under_review','won','lost','unknown')),
 reason text,
 amount_cents bigint not null check(amount_cents>0),
 currency text not null default 'USD' check(currency='USD'),
 payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
 actor_identity_id uuid not null,
 received_at timestamptz not null default now(),
 unique(provider,provider_event_id)
);
create or replace function public.mme_prevent_payment_dispute_mutation()
returns trigger language plpgsql security definer set search_path=''
as $
begin
 raise exception 'Stripe dispute events are immutable; record a new provider event instead'
  using errcode='55000';
end;
$;
revoke all on function public.mme_prevent_payment_dispute_mutation() from public,anon,authenticated;
create trigger mme_payment_disputes_immutable
before update or delete on public.mme_payment_disputes
for each row execute function public.mme_prevent_payment_dispute_mutation();

create index mme_payment_disputes_order_idx on public.mme_payment_disputes(order_id,received_at desc);
alter table public.mme_payment_disputes enable row level security;
revoke all on public.mme_payment_disputes from public,anon,authenticated;
grant all on public.mme_payment_disputes to service_role;

create or replace function public.mme_record_stripe_dispute_event(
 p_event_id text,p_dispute_id text,p_payment_intent_id text,p_status text,
 p_reason text,p_amount_cents bigint,p_currency text,p_payload_sha256 text,p_actor_identity_id uuid
) returns text language plpgsql security definer set search_path=''
as $$
declare
 v_binding public.mme_order_payment_intents%rowtype;
 v_order public.mme_orders%rowtype;
 v_id uuid;
begin
 if p_event_id is null or length(btrim(p_event_id)) not between 5 and 255
  or p_dispute_id is null or length(btrim(p_dispute_id)) not between 5 and 255
  or p_payment_intent_id is null or length(btrim(p_payment_intent_id)) not between 5 and 255
  or p_status not in ('warning_needs_response','needs_response','under_review','won','lost','unknown')
  or p_amount_cents is null or p_amount_cents<=0
  or upper(coalesce(p_currency,''))<>'USD'
  or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-fA-F]{64}$'
  or p_actor_identity_id is null then
  raise exception 'Invalid verified Stripe dispute event' using errcode='22023';
 end if;
 select * into v_binding from public.mme_order_payment_intents
  where provider='stripe' and provider_object_id=btrim(p_payment_intent_id);
 if not found then raise exception 'Dispute PaymentIntent is not bound to an MME order' using errcode='23514'; end if;
 select * into v_order from public.mme_orders where id=v_binding.order_id for update;
 if not found then raise exception 'Dispute order not found' using errcode='23503'; end if;
 insert into public.mme_payment_disputes(provider,provider_dispute_id,provider_event_id,
  order_id,payment_intent_id,dispute_status,reason,amount_cents,currency,payload_sha256,actor_identity_id)
 values('stripe',btrim(p_dispute_id),btrim(p_event_id),v_order.id,btrim(p_payment_intent_id),
  p_status,left(coalesce(p_reason,''),500),p_amount_cents,'USD',lower(p_payload_sha256),p_actor_identity_id)
 on conflict(provider,provider_event_id) do nothing returning id into v_id;
 if v_id is null then return 'duplicate'; end if;
 update public.mme_orders set status='disputed',updated_at=now()
  where id=v_order.id and status in ('paid','partially_refunded','disputed');
 return 'dispute_recorded_order_flagged_for_review';
end;
$$;
revoke all on function public.mme_record_stripe_dispute_event(text,text,text,text,text,bigint,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_record_stripe_dispute_event(text,text,text,text,text,bigint,text,text,uuid) to service_role;
comment on table public.mme_payment_disputes is 'Append-only Stripe dispute event ledger. Flags orders for review; never automatically refunds or restocks inventory.';
