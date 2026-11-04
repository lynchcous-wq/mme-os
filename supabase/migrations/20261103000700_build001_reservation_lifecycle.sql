-- Build 001 additive reservation lifecycle and verified-payment reconciliation.
-- Trusted server only. Stripe signature verification must occur before this RPC is called.

create or replace function public.mme_release_order_reservation(
  p_order_id uuid, p_terminal_status text
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_reservation_id uuid;
  v_status text;
  v_line record;
begin
  if p_order_id is null or p_terminal_status not in ('payment_failed','cancelled','expired') then
    raise exception 'Invalid reservation release request' using errcode='22023';
  end if;
  perform 1 from public.mme_orders
   where id=p_order_id and status='pending_payment' for update;
  if not found then return false; end if;

  select id,status into v_reservation_id,v_status
    from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_status <> 'active' then return false; end if;

  for v_line in
    select inventory_balance_id,quantity
      from public.mme_inventory_reservation_lines
     where reservation_id=v_reservation_id order by inventory_balance_id
  loop
    update public.mme_inventory_balances
       set reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
     where id=v_line.inventory_balance_id and reserved_quantity>=v_line.quantity;
    if not found then raise exception 'Reservation balance invariant violated' using errcode='23514'; end if;
  end loop;

  update public.mme_inventory_reservations
     set status=case when p_terminal_status='expired' then 'expired' else 'released' end,updated_at=now()
   where id=v_reservation_id and status='active';
  update public.mme_orders set status=p_terminal_status,updated_at=now()
   where id=p_order_id and status='pending_payment';
  return true;
end; $$;

create or replace function public.mme_expire_inventory_reservations(p_limit integer default 100)
returns integer language plpgsql security definer set search_path=''
as $$
declare v_order_id uuid; v_count integer:=0;
begin
  if p_limit is null or p_limit<1 or p_limit>1000 then
    raise exception 'Expiry batch limit must be between 1 and 1000' using errcode='22023';
  end if;
  for v_order_id in
    select o.id from public.mme_orders o
    join public.mme_inventory_reservations r on r.order_id=o.id
    where o.status='pending_payment' and r.status='active' and r.expires_at<=now()
    order by r.expires_at,o.id
    for update of o skip locked limit p_limit
  loop
    if public.mme_release_order_reservation(v_order_id,'expired') then v_count:=v_count+1; end if;
  end loop;
  return v_count;
end; $$;

create or replace function public.mme_process_verified_payment_event(
  p_provider_event_id text,p_event_type text,p_provider_object_id text,p_order_id uuid,
  p_amount_received_cents bigint,p_currency text,p_payload_sha256 text
) returns text language plpgsql security definer set search_path=''
as $$
declare
  v_event_id uuid; v_order record; v_res record; v_line record;
begin
  if p_provider_event_id is null or length(btrim(p_provider_event_id))<5
     or length(p_provider_event_id)>255
     or p_event_type is null or p_event_type not in ('payment_intent.succeeded','payment_intent.payment_failed')
     or p_provider_object_id is null or length(btrim(p_provider_object_id))=0 or p_order_id is null
     or p_amount_received_cents is null or p_amount_received_cents<0
     or lower(coalesce(p_currency,''))<>'usd'
     or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-fA-F]{64}
  if exists (
    select 1 from public.mme_order_lines
    where order_id=p_order_id and serialized_unit_id is not null
  ) then
    return 'use_serialized_payment_processor';
  end if;

  insert into public.mme_payment_events(provider,provider_event_id,event_type,provider_object_id,order_id,processing_status,payload_sha256)
  values('stripe',p_provider_event_id,p_event_type,p_provider_object_id,p_order_id,'received',lower(p_payload_sha256))
  on conflict(provider,provider_event_id) do nothing returning id into v_event_id;
  if v_event_id is null then return 'duplicate'; end if;

  select id,status,total_cents,currency into v_order
    from public.mme_orders where id=p_order_id for update;
  if not found then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_found';
  end if;

  if p_event_type='payment_intent.payment_failed' then
    if v_order.status='pending_payment' then
      perform public.mme_release_order_reservation(p_order_id,'payment_failed');
      update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
      return 'payment_failed_released';
    end if;
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'order_not_pending';
  end if;

  if v_order.currency<>'USD' or v_order.total_cents<>p_amount_received_cents then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'amount_or_currency_mismatch';
  end if;
  if v_order.status='paid' then
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'already_paid';
  end if;
  if v_order.status<>'pending_payment' then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_payable_refund_review';
  end if;

  select id,status,expires_at into v_res
    from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_res.status<>'active' or v_res.expires_at<=now() then
    if found and v_res.status='active' then
      perform public.mme_release_order_reservation(p_order_id,'expired');
    else
      update public.mme_orders set status='expired',updated_at=now() where id=p_order_id and status='pending_payment';
    end if;
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'reservation_expired_refund_review';
  end if;

  for v_line in
    select inventory_balance_id,quantity from public.mme_inventory_reservation_lines
     where reservation_id=v_res.id order by inventory_balance_id
  loop
    update public.mme_inventory_balances
       set on_hand_quantity=on_hand_quantity-v_line.quantity,
           reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
     where id=v_line.inventory_balance_id
       and on_hand_quantity>=v_line.quantity and reserved_quantity>=v_line.quantity;
    if not found then raise exception 'Inventory consume invariant violated' using errcode='23514'; end if;
  end loop;

  update public.mme_inventory_reservations set status='consumed',updated_at=now()
   where id=v_res.id and status='active';
  update public.mme_orders set status='paid',updated_at=now()
   where id=p_order_id and status='pending_payment';
  update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return 'paid_and_inventory_consumed';
end; $$;

revoke all on function public.mme_release_order_reservation(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_expire_inventory_reservations(integer) from public,anon,authenticated;
revoke all on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_release_order_reservation(uuid,text) to service_role;
grant execute on function public.mme_expire_inventory_reservations(integer) to service_role;
grant execute on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) to service_role;
 then
    raise exception 'Invalid verified payment event' using errcode='22023';
  end if;

  -- Keep aggregate and serialized payment handlers disjoint. Return before
  -- inserting the event so the correct serialized handler can process it.
  if exists (
    select 1 from public.mme_order_lines
    where order_id=p_order_id and serialized_unit_id is not null
  ) then
    return 'use_serialized_payment_processor';
  end if;

  insert into public.mme_payment_events(provider,provider_event_id,event_type,provider_object_id,order_id,processing_status,payload_sha256)
  values('stripe',p_provider_event_id,p_event_type,p_provider_object_id,p_order_id,'received',lower(p_payload_sha256))
  on conflict(provider,provider_event_id) do nothing returning id into v_event_id;
  if v_event_id is null then return 'duplicate'; end if;

  select id,status,total_cents,currency into v_order
    from public.mme_orders where id=p_order_id for update;
  if not found then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_found';
  end if;

  if p_event_type='payment_intent.payment_failed' then
    if v_order.status='pending_payment' then
      perform public.mme_release_order_reservation(p_order_id,'payment_failed');
      update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
      return 'payment_failed_released';
    end if;
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'order_not_pending';
  end if;

  if v_order.currency<>'USD' or v_order.total_cents<>p_amount_received_cents then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'amount_or_currency_mismatch';
  end if;
  if v_order.status='paid' then
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'already_paid';
  end if;
  if v_order.status<>'pending_payment' then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_payable_refund_review';
  end if;

  select id,status,expires_at into v_res
    from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_res.status<>'active' or v_res.expires_at<=now() then
    if found and v_res.status='active' then
      perform public.mme_release_order_reservation(p_order_id,'expired');
    else
      update public.mme_orders set status='expired',updated_at=now() where id=p_order_id and status='pending_payment';
    end if;
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'reservation_expired_refund_review';
  end if;

  for v_line in
    select inventory_balance_id,quantity from public.mme_inventory_reservation_lines
     where reservation_id=v_res.id order by inventory_balance_id
  loop
    update public.mme_inventory_balances
       set on_hand_quantity=on_hand_quantity-v_line.quantity,
           reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
     where id=v_line.inventory_balance_id
       and on_hand_quantity>=v_line.quantity and reserved_quantity>=v_line.quantity;
    if not found then raise exception 'Inventory consume invariant violated' using errcode='23514'; end if;
  end loop;

  update public.mme_inventory_reservations set status='consumed',updated_at=now()
   where id=v_res.id and status='active';
  update public.mme_orders set status='paid',updated_at=now()
   where id=p_order_id and status='pending_payment';
  update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return 'paid_and_inventory_consumed';
end; $$;

revoke all on function public.mme_release_order_reservation(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_expire_inventory_reservations(integer) from public,anon,authenticated;
revoke all on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_release_order_reservation(uuid,text) to service_role;
grant execute on function public.mme_expire_inventory_reservations(integer) to service_role;
grant execute on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) to service_role;
 then
    raise exception 'Invalid verified payment event' using errcode='22023';
  end if;

  -- Keep aggregate and serialized payment handlers disjoint. Return before inserting the event so the correct serialized handler can process it.
  if exists (
    select 1 from public.mme_order_lines
    where order_id=p_order_id and serialized_unit_id is not null
  ) then
    return 'use_serialized_payment_processor';
  end if;

  insert into public.mme_payment_events(provider,provider_event_id,event_type,provider_object_id,order_id,processing_status,payload_sha256)
  values('stripe',p_provider_event_id,p_event_type,p_provider_object_id,p_order_id,'received',lower(p_payload_sha256))
  on conflict(provider,provider_event_id) do nothing returning id into v_event_id;
  if v_event_id is null then return 'duplicate'; end if;

  select id,status,total_cents,currency into v_order
    from public.mme_orders where id=p_order_id for update;
  if not found then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_found';
  end if;

  if p_event_type='payment_intent.payment_failed' then
    if v_order.status='pending_payment' then
      perform public.mme_release_order_reservation(p_order_id,'payment_failed');
      update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
      return 'payment_failed_released';
    end if;
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'order_not_pending';
  end if;

  if v_order.currency<>'USD' or v_order.total_cents<>p_amount_received_cents then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'amount_or_currency_mismatch';
  end if;
  if v_order.status='paid' then
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'already_paid';
  end if;
  if v_order.status<>'pending_payment' then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_payable_refund_review';
  end if;

  select id,status,expires_at into v_res
    from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_res.status<>'active' or v_res.expires_at<=now() then
    if found and v_res.status='active' then
      perform public.mme_release_order_reservation(p_order_id,'expired');
    else
      update public.mme_orders set status='expired',updated_at=now() where id=p_order_id and status='pending_payment';
    end if;
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'reservation_expired_refund_review';
  end if;

  for v_line in
    select inventory_balance_id,quantity from public.mme_inventory_reservation_lines
     where reservation_id=v_res.id order by inventory_balance_id
  loop
    update public.mme_inventory_balances
       set on_hand_quantity=on_hand_quantity-v_line.quantity,
           reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
     where id=v_line.inventory_balance_id
       and on_hand_quantity>=v_line.quantity and reserved_quantity>=v_line.quantity;
    if not found then raise exception 'Inventory consume invariant violated' using errcode='23514'; end if;
  end loop;

  update public.mme_inventory_reservations set status='consumed',updated_at=now()
   where id=v_res.id and status='active';
  update public.mme_orders set status='paid',updated_at=now()
   where id=p_order_id and status='pending_payment';
  update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return 'paid_and_inventory_consumed';
end; $$;

revoke all on function public.mme_release_order_reservation(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_expire_inventory_reservations(integer) from public,anon,authenticated;
revoke all on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_release_order_reservation(uuid,text) to service_role;
grant execute on function public.mme_expire_inventory_reservations(integer) to service_role;
grant execute on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) to service_role;
 then
    raise exception 'Invalid verified payment event' using errcode='22023';
  end if;

  -- Keep aggregate and serialized payment handlers disjoint. Return before
  -- inserting the event so the correct serialized handler can process it.
  if exists (
    select 1 from public.mme_order_lines
    where order_id=p_order_id and serialized_unit_id is not null
  ) then
    return 'use_serialized_payment_processor';
  end if;

  insert into public.mme_payment_events(provider,provider_event_id,event_type,provider_object_id,order_id,processing_status,payload_sha256)
  values('stripe',p_provider_event_id,p_event_type,p_provider_object_id,p_order_id,'received',lower(p_payload_sha256))
  on conflict(provider,provider_event_id) do nothing returning id into v_event_id;
  if v_event_id is null then return 'duplicate'; end if;

  select id,status,total_cents,currency into v_order
    from public.mme_orders where id=p_order_id for update;
  if not found then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_found';
  end if;

  if p_event_type='payment_intent.payment_failed' then
    if v_order.status='pending_payment' then
      perform public.mme_release_order_reservation(p_order_id,'payment_failed');
      update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
      return 'payment_failed_released';
    end if;
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'order_not_pending';
  end if;

  if v_order.currency<>'USD' or v_order.total_cents<>p_amount_received_cents then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'amount_or_currency_mismatch';
  end if;
  if v_order.status='paid' then
    update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
    return 'already_paid';
  end if;
  if v_order.status<>'pending_payment' then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_payable_refund_review';
  end if;

  select id,status,expires_at into v_res
    from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_res.status<>'active' or v_res.expires_at<=now() then
    if found and v_res.status='active' then
      perform public.mme_release_order_reservation(p_order_id,'expired');
    else
      update public.mme_orders set status='expired',updated_at=now() where id=p_order_id and status='pending_payment';
    end if;
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'reservation_expired_refund_review';
  end if;

  for v_line in
    select inventory_balance_id,quantity from public.mme_inventory_reservation_lines
     where reservation_id=v_res.id order by inventory_balance_id
  loop
    update public.mme_inventory_balances
       set on_hand_quantity=on_hand_quantity-v_line.quantity,
           reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
     where id=v_line.inventory_balance_id
       and on_hand_quantity>=v_line.quantity and reserved_quantity>=v_line.quantity;
    if not found then raise exception 'Inventory consume invariant violated' using errcode='23514'; end if;
  end loop;

  update public.mme_inventory_reservations set status='consumed',updated_at=now()
   where id=v_res.id and status='active';
  update public.mme_orders set status='paid',updated_at=now()
   where id=p_order_id and status='pending_payment';
  update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return 'paid_and_inventory_consumed';
end; $$;

revoke all on function public.mme_release_order_reservation(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_expire_inventory_reservations(integer) from public,anon,authenticated;
revoke all on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_release_order_reservation(uuid,text) to service_role;
grant execute on function public.mme_expire_inventory_reservations(integer) to service_role;
grant execute on function public.mme_process_verified_payment_event(text,text,text,uuid,bigint,text,text) to service_role;
