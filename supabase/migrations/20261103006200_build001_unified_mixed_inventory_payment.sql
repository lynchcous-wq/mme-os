-- Build 001: one verified Stripe event consumes/releases aggregate and serialized reservations atomically.
create or replace function public.mme_process_unified_order_payment_event(
 p_provider_event_id text,p_event_type text,p_payment_intent_id text,p_order_id uuid,
 p_amount_received_cents bigint,p_currency text,p_payload_sha256 text
) returns text language plpgsql security definer set search_path=''
as $$
declare
 v_event_id uuid;
 v_order public.mme_orders%rowtype;
 v_res public.mme_inventory_reservations%rowtype;
 v_intent public.mme_order_payment_intents%rowtype;
 v_line record;
 v_unit_id uuid;
 v_has_aggregate boolean;
 v_has_serialized boolean;
begin
 if p_provider_event_id is null or length(btrim(p_provider_event_id)) not between 5 and 255
  or p_event_type not in ('payment_intent.succeeded','payment_intent.payment_failed')
  or p_payment_intent_id is null or length(btrim(p_payment_intent_id)) not between 5 and 255
  or p_order_id is null or p_amount_received_cents is null or p_amount_received_cents<0
  or lower(coalesce(p_currency,''))<>'usd'
  or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-fA-F]{64}$' then
  raise exception 'Invalid verified unified payment event' using errcode='22023';
 end if;

 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found then return 'order_not_found'; end if;
 select * into v_intent from public.mme_order_payment_intents
  where order_id=p_order_id and provider_object_id=btrim(p_payment_intent_id);
 if not found or v_intent.expected_amount_cents<>v_order.total_cents
   or v_intent.currency<>v_order.currency then
  raise exception 'PaymentIntent is not bound to this order and amount' using errcode='23514';
 end if;

 insert into public.mme_payment_events(provider,provider_event_id,event_type,provider_object_id,order_id,processing_status,payload_sha256)
 values('stripe',btrim(p_provider_event_id),p_event_type,btrim(p_payment_intent_id),p_order_id,'received',lower(p_payload_sha256))
 on conflict(provider,provider_event_id) do nothing returning id into v_event_id;
 if v_event_id is null then return 'duplicate'; end if;

 if v_order.status='paid' then
  update public.mme_payment_events set processing_status='ignored',processed_at=now() where id=v_event_id;
  return 'already_paid';
 end if;
 if v_order.status<>'pending_payment' then
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  return 'order_not_payable_refund_review';
 end if;

 select * into v_res from public.mme_inventory_reservations where order_id=p_order_id for update;
 if not found or v_res.status<>'active' then
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  return 'reservation_not_active_refund_review';
 end if;

 select exists(select 1 from public.mme_inventory_reservation_lines where reservation_id=v_res.id),
        exists(select 1 from public.mme_serialized_unit_reservations where reservation_id=v_res.id and status='active')
 into v_has_aggregate,v_has_serialized;
 if not v_has_aggregate and not v_has_serialized then
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  return 'reservation_has_no_active_stock_refund_review';
 end if;

 if p_event_type='payment_intent.payment_failed' then
  for v_line in select * from public.mme_inventory_reservation_lines
   where reservation_id=v_res.id order by inventory_balance_id for update
  loop
   update public.mme_inventory_balances set reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
    where id=v_line.inventory_balance_id and reserved_quantity>=v_line.quantity;
   if not found then raise exception 'Aggregate reservation release invariant violated' using errcode='23514'; end if;
  end loop;
  for v_unit_id in
   select unit_id from public.mme_serialized_unit_reservations
   where reservation_id=v_res.id and status='active' order by unit_id for update
  loop
   update public.mme_serialized_units set unit_status='in_stock',updated_at=now()
    where id=v_unit_id and unit_status='reserved';
   if not found then raise exception 'Serialized reservation release invariant violated' using errcode='23514'; end if;
  end loop;
  update public.mme_serialized_unit_reservations set status='released',updated_at=now()
   where reservation_id=v_res.id and status='active';
  update public.mme_inventory_reservations set status='released',updated_at=now() where id=v_res.id;
  update public.mme_orders set status='payment_failed',updated_at=now() where id=p_order_id;
  update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return 'payment_failed_all_stock_released';
 end if;

 if v_order.currency<>'USD' or v_order.total_cents<>p_amount_received_cents
  or v_intent.expected_amount_cents<>p_amount_received_cents then
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  return 'amount_or_currency_mismatch_refund_review';
 end if;

 if v_res.expires_at<=now() then
  for v_line in select * from public.mme_inventory_reservation_lines
   where reservation_id=v_res.id order by inventory_balance_id for update
  loop
   update public.mme_inventory_balances set reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
    where id=v_line.inventory_balance_id and reserved_quantity>=v_line.quantity;
   if not found then raise exception 'Expired aggregate release invariant violated' using errcode='23514'; end if;
  end loop;
  for v_unit_id in
   select unit_id from public.mme_serialized_unit_reservations
   where reservation_id=v_res.id and status='active' order by unit_id for update
  loop
   update public.mme_serialized_units set unit_status='in_stock',updated_at=now()
    where id=v_unit_id and unit_status='reserved';
   if not found then raise exception 'Expired serialized release invariant violated' using errcode='23514'; end if;
  end loop;
  update public.mme_serialized_unit_reservations set status='expired',updated_at=now()
   where reservation_id=v_res.id and status='active';
  update public.mme_inventory_reservations set status='expired',updated_at=now() where id=v_res.id;
  update public.mme_orders set status='expired',updated_at=now() where id=p_order_id;
  update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
  return 'reservation_expired_refund_review_stock_released';
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

 for v_unit_id in
  select unit_id from public.mme_serialized_unit_reservations
  where reservation_id=v_res.id and status='active' order by unit_id for update
 loop
  update public.mme_serialized_units set unit_status='sold',sold_at=now(),updated_at=now()
   where id=v_unit_id and unit_status='reserved';
  if not found then raise exception 'Serialized unit consumption invariant violated' using errcode='23514'; end if;
 end loop;

 update public.mme_serialized_unit_reservations set status='consumed',updated_at=now()
  where reservation_id=v_res.id and status='active';
 update public.mme_inventory_reservations set status='consumed',updated_at=now() where id=v_res.id;
 update public.mme_orders set status='paid',updated_at=now() where id=p_order_id and status='pending_payment';
 update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
 return case when v_has_aggregate and v_has_serialized
  then 'paid_and_mixed_stock_consumed'
  when v_has_serialized then 'paid_and_serialized_stock_consumed'
  else 'paid_and_aggregate_stock_consumed' end;
end; $$;

revoke all on function public.mme_process_unified_order_payment_event(text,text,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_process_unified_order_payment_event(text,text,text,uuid,bigint,text,text) to service_role;
comment on function public.mme_process_unified_order_payment_event(text,text,text,uuid,bigint,text,text) is
 'Single transaction processor for signature-verified Stripe PaymentIntent events across aggregate, serialized and mixed reservations. Adapter must verify Stripe signature, account, mode and event payload before invocation.';
