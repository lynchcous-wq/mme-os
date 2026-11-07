-- Build 010.96: Stripe checkout payment confirmation and atomic inventory consumption.
-- Additive schema extension; production activation requires reviewed migration and Stripe test-mode validation.

alter table public.mme_orders
  add column if not exists stripe_checkout_session_id text,
  add column if not exists stripe_payment_intent_id text;

create unique index if not exists mme_orders_stripe_checkout_session_uidx
  on public.mme_orders(stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

create unique index if not exists mme_orders_stripe_payment_intent_uidx
  on public.mme_orders(stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

alter table public.mme_orders drop constraint if exists mme_orders_status_check;
alter table public.mme_orders add constraint mme_orders_status_check
  check (status in ('pending_payment','paid','payment_failed','payment_review','cancelled','expired','partially_refunded','refunded','disputed'));

create or replace function public.mme_confirm_stripe_order_payment(
  p_provider_event_id text,
  p_event_type text,
  p_payload_sha256 text,
  p_order_id uuid,
  p_customer_identity_id uuid,
  p_checkout_session_id text,
  p_payment_intent_id text,
  p_amount_cents bigint,
  p_currency text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_existing_hash text;
  v_order public.mme_orders%rowtype;
  v_reservation public.mme_inventory_reservations%rowtype;
  v_line record;
begin
  if p_provider_event_id is null or length(p_provider_event_id) not between 8 and 255
     or p_event_type not in ('checkout.session.completed','checkout.session.async_payment_succeeded')
     or p_payload_sha256 !~ '^[0-9a-f]{64}$'
     or p_order_id is null or p_customer_identity_id is null or p_checkout_session_id is null or p_checkout_session_id not like 'cs\_%'
     or p_payment_intent_id is null or p_payment_intent_id not like 'pi\_%'
     or p_amount_cents is null or p_amount_cents <= 0 or p_currency <> 'usd' then
    raise exception 'Invalid Stripe payment confirmation' using errcode = '22023';
  end if;

  insert into public.mme_payment_events(
    provider, provider_event_id, event_type, provider_object_id, order_id, processing_status, payload_sha256
  ) values (
    'stripe', p_provider_event_id, p_event_type, p_checkout_session_id, p_order_id, 'received', p_payload_sha256
  ) on conflict (provider, provider_event_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select id, payload_sha256 into v_event_id, v_existing_hash
    from public.mme_payment_events
    where provider = 'stripe' and provider_event_id = p_provider_event_id
    for update;
    if v_existing_hash is distinct from p_payload_sha256 then
      raise exception 'Stripe event ID replayed with a different payload' using errcode = '23505';
    end if;
    return jsonb_build_object('result','duplicate');
  end if;

  select * into v_order
  from public.mme_orders
  where id = p_order_id
  for update;

  if not found then
    update public.mme_payment_events set processing_status = 'failed', processed_at = now() where id = v_event_id;
    raise exception 'Order not found for Stripe payment' using errcode = 'P0002';
  end if;

  if v_order.customer_identity_id is distinct from p_customer_identity_id then
    update public.mme_payment_events set processing_status = 'failed', processed_at = now() where id = v_event_id;
    raise exception 'Stripe customer identity does not match order' using errcode = '23514';
  end if;

  if v_order.stripe_checkout_session_id is distinct from p_checkout_session_id then
    update public.mme_payment_events set processing_status = 'failed', processed_at = now() where id = v_event_id;
    raise exception 'Stripe Checkout Session does not match order' using errcode = '23514';
  end if;

  if v_order.total_cents <> p_amount_cents or lower(v_order.currency) <> p_currency then
    update public.mme_payment_events set processing_status = 'failed', processed_at = now() where id = v_event_id;
    raise exception 'Stripe amount or currency does not match order' using errcode = '23514';
  end if;

  if v_order.status = 'paid' then
    if v_order.stripe_checkout_session_id is distinct from p_checkout_session_id
       or v_order.stripe_payment_intent_id is distinct from p_payment_intent_id then
      update public.mme_payment_events set processing_status = 'failed', processed_at = now() where id = v_event_id;
      raise exception 'Paid order is bound to a different Stripe payment' using errcode = '23505';
    end if;
    update public.mme_payment_events set processing_status = 'processed', processed_at = now() where id = v_event_id;
    return jsonb_build_object('result','already_paid','order_id',p_order_id);
  end if;

  if v_order.status <> 'pending_payment' then
    update public.mme_payment_events set processing_status = 'failed', processed_at = now() where id = v_event_id;
    raise exception 'Order is not awaiting payment' using errcode = '23514';
  end if;

  select * into v_reservation
  from public.mme_inventory_reservations
  where order_id = p_order_id
  for update;

  if not found or v_reservation.status <> 'active' or v_reservation.expires_at <= now() then
    update public.mme_orders set status = 'payment_review', updated_at = now() where id = p_order_id;
    update public.mme_payment_events set processing_status = 'processed', processed_at = now() where id = v_event_id;
    return jsonb_build_object('result','payment_review','order_id',p_order_id,'reason','reservation_missing_or_expired');
  end if;

  for v_line in
    select rl.inventory_balance_id, rl.quantity
    from public.mme_inventory_reservation_lines rl
    where rl.reservation_id = v_reservation.id
    order by rl.inventory_balance_id
    for update
  loop
    update public.mme_inventory_balances
    set on_hand_quantity = on_hand_quantity - v_line.quantity,
        reserved_quantity = reserved_quantity - v_line.quantity,
        updated_at = now()
    where id = v_line.inventory_balance_id
      and on_hand_quantity >= v_line.quantity
      and reserved_quantity >= v_line.quantity;
    if not found then
      update public.mme_orders set status = 'payment_review', updated_at = now() where id = p_order_id;
      update public.mme_payment_events set processing_status = 'processed', processed_at = now() where id = v_event_id;
      return jsonb_build_object('result','payment_review','order_id',p_order_id,'reason','inventory_balance_mismatch');
    end if;
  end loop;

  update public.mme_inventory_reservations
  set status = 'consumed', updated_at = now()
  where id = v_reservation.id;

  update public.mme_orders
  set status = 'paid',
      stripe_checkout_session_id = p_checkout_session_id,
      stripe_payment_intent_id = p_payment_intent_id,
      updated_at = now()
  where id = p_order_id;

  update public.mme_payment_events
  set processing_status = 'processed', processed_at = now()
  where id = v_event_id;

  return jsonb_build_object('result','paid','order_id',p_order_id);
end;
$$;

revoke all on function public.mme_confirm_stripe_order_payment(text,text,text,uuid,uuid,text,text,bigint,text) from public;
revoke all on function public.mme_confirm_stripe_order_payment(text,text,text,uuid,uuid,text,text,bigint,text) from anon;
revoke all on function public.mme_confirm_stripe_order_payment(text,text,text,uuid,uuid,text,text,bigint,text) from authenticated;
grant execute on function public.mme_confirm_stripe_order_payment(text,text,text,uuid,uuid,text,text,bigint,text) to service_role;


create or replace function public.mme_bind_stripe_checkout_session(
  p_order_id uuid,
  p_checkout_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.mme_orders%rowtype;
begin
  if p_order_id is null or p_checkout_session_id is null or p_checkout_session_id not like 'cs\_%' then
    raise exception 'Invalid Stripe Checkout session binding' using errcode = '22023';
  end if;
  select * into v_order from public.mme_orders where id = p_order_id for update;
  if not found or v_order.status <> 'pending_payment' then return false; end if;
  if not exists (
    select 1 from public.mme_inventory_reservations r
    where r.order_id = p_order_id and r.status = 'active' and r.expires_at > now()
  ) then return false; end if;
  if v_order.stripe_checkout_session_id is not null
     and v_order.stripe_checkout_session_id <> p_checkout_session_id then
    raise exception 'Order already bound to another Stripe session' using errcode = '23505';
  end if;
  update public.mme_orders set stripe_checkout_session_id = p_checkout_session_id, updated_at = now()
  where id = p_order_id;
  return true;
end;
$$;

revoke all on function public.mme_bind_stripe_checkout_session(uuid,text) from public;
revoke all on function public.mme_bind_stripe_checkout_session(uuid,text) from anon;
revoke all on function public.mme_bind_stripe_checkout_session(uuid,text) from authenticated;
grant execute on function public.mme_bind_stripe_checkout_session(uuid,text) to service_role;
