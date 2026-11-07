-- Build 010.90: idempotent aggregate order payment finalization.
-- Called only by a trusted server after Stripe webhook signature verification.
-- Additive migration; does not configure Stripe or enable live checkout.

create or replace function public.mme_process_order_payment_event(
  p_provider_event_id text,
  p_event_type text,
  p_provider_object_id text,
  p_order_id uuid,
  p_amount_received_cents bigint,
  p_currency text,
  p_payload_sha256 text
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_order record;
  v_reservation record;
  v_line record;
begin
  if p_provider_event_id is null or length(btrim(p_provider_event_id)) < 5
     or length(p_provider_event_id) > 255
     or p_event_type is null or p_event_type not in (
       'checkout.session.completed',
       'checkout.session.async_payment_succeeded',
       'checkout.session.async_payment_failed',
       'checkout.session.expired'
     )
     or p_provider_object_id is null or length(btrim(p_provider_object_id)) = 0
     or p_order_id is null
     or p_amount_received_cents is null or p_amount_received_cents < 0
     or lower(coalesce(p_currency, '')) <> 'usd'
     or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'Invalid verified order payment event' using errcode = '22023';
  end if;

  insert into public.mme_payment_events(
    provider, provider_event_id, event_type, provider_object_id,
    order_id, processing_status, payload_sha256
  ) values (
    'stripe', p_provider_event_id, p_event_type, p_provider_object_id,
    p_order_id, 'received', lower(p_payload_sha256)
  )
  on conflict (provider, provider_event_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    return 'duplicate';
  end if;

  select id, status, total_cents, currency
    into v_order
  from public.mme_orders
  where id = p_order_id
  for update;

  if not found then
    update public.mme_payment_events
       set processing_status = 'failed', processed_at = now()
     where id = v_event_id;
    return 'order_not_found';
  end if;

  if v_order.currency <> 'USD' or v_order.total_cents <> p_amount_received_cents then
    update public.mme_payment_events
       set processing_status = 'failed', processed_at = now()
     where id = v_event_id;
    return 'amount_or_currency_mismatch';
  end if;

  if v_order.status = 'paid' then
    update public.mme_payment_events
       set processing_status = 'ignored', processed_at = now()
     where id = v_event_id;
    return 'already_paid';
  end if;

  if v_order.status <> 'pending_payment' then
    update public.mme_payment_events
       set processing_status = 'failed', processed_at = now()
     where id = v_event_id;
    return 'order_not_payable_manual_review';
  end if;

  select id, status, expires_at
    into v_reservation
  from public.mme_inventory_reservations
  where order_id = p_order_id
  for update;

  if not found or v_reservation.status <> 'active'
     or v_reservation.expires_at <= now() then
    update public.mme_payment_events
       set processing_status = 'failed', processed_at = now()
     where id = v_event_id;
    return 'reservation_missing_or_expired_manual_refund_review';
  end if;

  if p_event_type in ('checkout.session.async_payment_failed', 'checkout.session.expired')
     or (p_event_type = 'checkout.session.completed' and p_amount_received_cents = 0) then
    for v_line in
      select inventory_balance_id, quantity
      from public.mme_inventory_reservation_lines
      where reservation_id = v_reservation.id
      order by inventory_balance_id
      for update
    loop
      update public.mme_inventory_balances
         set reserved_quantity = reserved_quantity - v_line.quantity,
             updated_at = now()
       where id = v_line.inventory_balance_id
         and reserved_quantity >= v_line.quantity;
      if not found then
        raise exception 'Inventory reservation release invariant violated' using errcode = '23514';
      end if;
    end loop;

    update public.mme_inventory_reservations
       set status = case when p_event_type = 'checkout.session.expired' then 'expired' else 'released' end,
           updated_at = now()
     where id = v_reservation.id and status = 'active';

    update public.mme_orders
       set status = case when p_event_type = 'checkout.session.expired' then 'expired' else 'payment_failed' end,
           updated_at = now()
     where id = p_order_id and status = 'pending_payment';

    update public.mme_payment_events
       set processing_status = 'processed', processed_at = now()
     where id = v_event_id;
    return 'payment_not_completed_reservation_released';
  end if;

  if p_event_type not in ('checkout.session.completed', 'checkout.session.async_payment_succeeded') then
    update public.mme_payment_events
       set processing_status = 'ignored', processed_at = now()
     where id = v_event_id;
    return 'event_ignored';
  end if;

  for v_line in
    select inventory_balance_id, quantity
    from public.mme_inventory_reservation_lines
    where reservation_id = v_reservation.id
    order by inventory_balance_id
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
      raise exception 'Inventory consumption invariant violated' using errcode = '23514';
    end if;
  end loop;

  update public.mme_inventory_reservations
     set status = 'consumed', updated_at = now()
   where id = v_reservation.id and status = 'active';

  update public.mme_orders
     set status = 'paid', updated_at = now()
   where id = p_order_id and status = 'pending_payment';

  update public.mme_payment_events
     set processing_status = 'processed', processed_at = now()
   where id = v_event_id;

  return 'paid_and_inventory_consumed';
end;
$$;

revoke all on function public.mme_process_order_payment_event(text,text,text,uuid,bigint,text,text) from public, anon, authenticated;
grant execute on function public.mme_process_order_payment_event(text,text,text,uuid,bigint,text,text) to service_role;
