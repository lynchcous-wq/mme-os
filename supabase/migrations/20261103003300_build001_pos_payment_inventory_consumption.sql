-- Build 001: bind Stripe PaymentIntents to orders and atomically consume/release aggregate stock.
-- The trusted webhook adapter MUST verify Stripe signature, live/test mode, account and event payload
-- before calling these service-role-only functions. No browser or client may call these RPCs.

create table public.mme_order_payment_intents (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null unique references public.mme_orders(id) on delete restrict,
 provider text not null default 'stripe' check(provider='stripe'),
 provider_object_id text not null unique check(length(btrim(provider_object_id)) between 5 and 255),
 expected_amount_cents bigint not null check(expected_amount_cents>=0),
 currency text not null default 'USD' check(currency='USD'),
 created_at timestamptz not null default now(),
 created_by_identity_id uuid not null
);
alter table public.mme_order_payment_intents enable row level security;
revoke all on public.mme_order_payment_intents from public,anon,authenticated;
grant all on public.mme_order_payment_intents to service_role;

create or replace function public.mme_bind_order_payment_intent(
 p_order_id uuid,p_payment_intent_id text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_order public.mme_orders%rowtype; v_id uuid;
begin
 if p_order_id is null or p_payment_intent_id is null
  or length(btrim(p_payment_intent_id)) not between 5 and 255 or p_actor_identity_id is null then
  raise exception 'Invalid payment intent binding' using errcode='22023';
 end if;
 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found or v_order.status<>'pending_payment' then
  raise exception 'Pending order not found' using errcode='P0002';
 end if;
 insert into public.mme_order_payment_intents(order_id,provider_object_id,expected_amount_cents,currency,created_by_identity_id)
 values(p_order_id,btrim(p_payment_intent_id),v_order.total_cents,v_order.currency,p_actor_identity_id)
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_process_aggregate_order_payment_event(
 p_provider_event_id text,p_event_type text,p_payment_intent_id text,p_order_id uuid,
 p_amount_received_cents bigint,p_currency text,p_payload_sha256 text
) returns text language plpgsql security definer set search_path=''
as $$
declare v_event_id uuid; v_order public.mme_orders%rowtype;
 v_res public.mme_inventory_reservations%rowtype; v_intent public.mme_order_payment_intents%rowtype;
 v_line record;
begin
 if p_provider_event_id is null or length(btrim(p_provider_event_id)) not between 5 and 255
  or p_event_type not in ('payment_intent.succeeded','payment_intent.payment_failed')
  or p_payment_intent_id is null or length(btrim(p_payment_intent_id)) not between 5 and 255
  or p_order_id is null or p_amount_received_cents is null or p_amount_received_cents<0
  or lower(coalesce(p_currency,''))<>'usd'
  or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-fA-F]{64}$' then
  raise exception 'Invalid verified aggregate payment event' using errcode='22023';
 end if;

 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found then return 'order_not_found'; end if;
 select * into v_intent from public.mme_order_payment_intents
  where order_id=p_order_id and provider_object_id=btrim(p_payment_intent_id);
 if not found or v_intent.expected_amount_cents<>v_order.total_cents then
  raise exception 'PaymentIntent is not bound to this order' using errcode='23514';
 end if;
 if exists(select 1 from public.mme_order_lines where order_id=p_order_id and serialized_unit_id is not null) then
  raise exception 'Serialized order must use serialized payment processor' using errcode='23514';
 end if;

 insert into public.mme_payment_events(provider,provider_event_id,event_type,provider_object_id,order_id,processing_status,payload_sha256)
 values('stripe',btrim(p_provider_event_id),p_event_type,btrim(p_payment_intent_id),p_order_id,'received',lower(p_payload_sha256))
 on conflict(provider,provider_event_id) do nothing returning id into v_event_id;
 if v_event_id is null then return 'duplicate'; end if;

 if p_event_type='payment_intent.payment_failed' then
  if v_order.status<>'pending_payment' then
   update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
   return 'order_not_pending';
  end if;
  select * into v_res from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_res.status<>'active' then
   update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
   return 'reservation_not_active';
  end if;
  for v_line in select * from public.mme_inventory_reservation_lines
   where reservation_id=v_res.id order by inventory_balance_id for update
  loop
   update public.mme_inventory_balances set reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
    where id=v_line.inventory_balance_id and reserved_quantity>=v_line.quantity;
   if not found then raise exception 'Aggregate reservation release invariant violated' using errcode='23514'; end if;
  end loop;
  update public.mme_inventory_reservations set status='released',updated_at=now() where id=v_res.id;
  update public.mme_orders set status='payment_failed',updated_at=now() where id=p_order_id;
  update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return 'payment_failed_stock_released';
 end if;

 if v_order.status='paid' then
  update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
  return 'already_paid';
 end if;
 if v_order.status<>'pending_payment' then
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  return 'order_not_payable_refund_review';
 end if;
 if v_order.currency<>'USD' or v_order.total_cents<>p_amount_received_cents
  or v_intent.expected_amount_cents<>p_amount_received_cents then
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  return 'amount_or_currency_mismatch';
 end if;

 select * into v_res from public.mme_inventory_reservations where order_id=p_order_id for update;
 if not found or v_res.status<>'active' or v_res.expires_at<=now() then
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  update public.mme_orders set status='expired',updated_at=now() where id=p_order_id;
  return 'reservation_expired_refund_review';
 end if;

 for v_line in select * from public.mme_inventory_reservation_lines
  where reservation_id=v_res.id order by inventory_balance_id for update
 loop
  update public.mme_inventory_balances set
   on_hand_quantity=on_hand_quantity-v_line.quantity,
   reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
  where id=v_line.inventory_balance_id
   and on_hand_quantity>=v_line.quantity and reserved_quantity>=v_line.quantity;
  if not found then raise exception 'Aggregate stock consumption invariant violated' using errcode='23514'; end if;
 end loop;
 update public.mme_inventory_reservations set status='consumed',updated_at=now() where id=v_res.id;
 update public.mme_orders set status='paid',updated_at=now() where id=p_order_id;
 update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
 return 'paid_and_aggregate_stock_consumed';
end; $$;

revoke all on function public.mme_bind_order_payment_intent(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_process_aggregate_order_payment_event(text,text,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_bind_order_payment_intent(uuid,text,uuid) to service_role;
grant execute on function public.mme_process_aggregate_order_payment_event(text,text,text,uuid,bigint,text,text) to service_role;

comment on table public.mme_order_payment_intents is
 'Server-created Stripe PaymentIntent binding; expected amount and currency are snapshotted per order.';
comment on function public.mme_process_aggregate_order_payment_event(text,text,text,uuid,bigint,text,text) is
 'Processes signature-verified Stripe event idempotently and atomically consumes or releases aggregate stock reservations.';
