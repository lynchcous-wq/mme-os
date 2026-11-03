-- Build 001: dedicated single-unit serialized checkout path.
-- Adds a separate RPC; aggregate checkout continues to reject serialized products.
-- Stripe signature verification must occur in the trusted server adapter before payment RPC.

alter table public.mme_order_lines
  add column serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
  add column serial_number_snapshot text,
  add column imei_snapshot text;

alter table public.mme_order_lines
  add constraint mme_order_lines_serialized_quantity_check
  check (serialized_unit_id is null or quantity=1);

create or replace function public.mme_create_serialized_order_and_reserve(
  p_idempotency_key text,
  p_customer_identity_id uuid,
  p_unit_id uuid,
  p_fulfillment_method text,
  p_fulfillment_snapshot jsonb,
  p_tax_cents bigint,
  p_fulfillment_cents bigint,
  p_discount_cents bigint,
  p_expires_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_fingerprint text; v_order_id uuid; v_existing_id uuid; v_existing_fp text;
  v_unit record; v_total bigint; v_reservation_id uuid;
begin
  if p_idempotency_key is null or length(btrim(p_idempotency_key))<8 or length(p_idempotency_key)>128
     or p_unit_id is null
     or p_fulfillment_method not in ('pickup','shipping')
     or p_fulfillment_snapshot is null or jsonb_typeof(p_fulfillment_snapshot)<>'object'
     or p_tax_cents is null or p_tax_cents<0
     or p_fulfillment_cents is null or p_fulfillment_cents<0
     or p_discount_cents is null or p_discount_cents<0
     or p_expires_at is null or p_expires_at<=now()
     or p_expires_at>now()+interval '30 minutes' then
    raise exception 'Invalid serialized order request' using errcode='22023';
  end if;

  v_fingerprint:=md5(jsonb_build_object(
    'customer_identity_id',p_customer_identity_id,'unit_id',p_unit_id,
    'fulfillment_method',p_fulfillment_method,'fulfillment_snapshot',p_fulfillment_snapshot,
    'tax_cents',p_tax_cents,'fulfillment_cents',p_fulfillment_cents,'discount_cents',p_discount_cents
  )::text);

  select id,request_fingerprint into v_existing_id,v_existing_fp
    from public.mme_orders where idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing_fp<>v_fingerprint then
      raise exception 'Idempotency key reused with different request' using errcode='23505';
    end if;
    return v_existing_id;
  end if;

  select u.id,u.product_id,u.location_id,u.serial_number,u.imei,u.condition_grade,u.unit_status,
         p.sku,p.title,p.unit_price_cents,p.active,p.serialized
    into v_unit
    from public.mme_serialized_units u
    join public.mme_products p on p.id=u.product_id
   where u.id=p_unit_id
   for update of u,p;

  if not found or v_unit.unit_status<>'in_stock' or not v_unit.active or not v_unit.serialized then
    raise exception 'Serialized unit unavailable' using errcode='P0002';
  end if;

  v_total:=v_unit.unit_price_cents+p_tax_cents+p_fulfillment_cents-p_discount_cents;
  if p_discount_cents>v_unit.unit_price_cents+p_tax_cents+p_fulfillment_cents
     or v_total<0 or v_total>9000000000000000 then
    raise exception 'Invalid serialized order total' using errcode='22003';
  end if;

  insert into public.mme_orders(
    idempotency_key,request_fingerprint,customer_identity_id,status,
    subtotal_cents,tax_cents,fulfillment_cents,discount_cents,total_cents,
    fulfillment_method,fulfillment_snapshot
  ) values(
    p_idempotency_key,v_fingerprint,p_customer_identity_id,'pending_payment',
    v_unit.unit_price_cents,p_tax_cents,p_fulfillment_cents,p_discount_cents,v_total,
    p_fulfillment_method,p_fulfillment_snapshot
  ) returning id into v_order_id;

  insert into public.mme_inventory_reservations(order_id,expires_at)
    values(v_order_id,p_expires_at) returning id into v_reservation_id;

  update public.mme_serialized_units
     set unit_status='reserved',updated_at=now()
   where id=p_unit_id and unit_status='in_stock';
  if not found then raise exception 'Serialized unit was reserved concurrently' using errcode='P0001'; end if;

  insert into public.mme_serialized_unit_reservations(
    reservation_id,order_id,unit_id,serial_snapshot,imei_snapshot,status
  ) values(v_reservation_id,v_order_id,p_unit_id,v_unit.serial_number,v_unit.imei,'active');

  insert into public.mme_order_lines(
    order_id,product_id,location_id,sku_snapshot,title_snapshot,condition_snapshot,
    quantity,unit_price_cents,line_total_cents,serialized_unit_id,serial_number_snapshot,imei_snapshot
  ) values(
    v_order_id,v_unit.product_id,v_unit.location_id,v_unit.sku,v_unit.title,v_unit.condition_grade,
    1,v_unit.unit_price_cents,v_unit.unit_price_cents,p_unit_id,v_unit.serial_number,v_unit.imei
  );

  return v_order_id;
end; $$;

create or replace function public.mme_release_serialized_order_reservation(
  p_order_id uuid,p_terminal_status text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_res record; v_unit_id uuid;
begin
  if p_order_id is null or p_terminal_status not in ('payment_failed','cancelled','expired') then
    raise exception 'Invalid serialized release request' using errcode='22023';
  end if;
  perform 1 from public.mme_orders where id=p_order_id and status='pending_payment' for update;
  if not found then return false; end if;
  select id,status into v_res from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_res.status<>'active' then return false; end if;

  for v_unit_id in
    select unit_id from public.mme_serialized_unit_reservations
     where reservation_id=v_res.id and status='active' order by unit_id for update
  loop
    update public.mme_serialized_units set unit_status='in_stock',updated_at=now()
     where id=v_unit_id and unit_status='reserved';
    if not found then raise exception 'Serialized unit state invariant violated' using errcode='23514'; end if;
  end loop;

  update public.mme_serialized_unit_reservations set status=case when p_terminal_status='expired' then 'expired' else 'released' end,updated_at=now()
   where reservation_id=v_res.id and status='active';
  update public.mme_inventory_reservations set status=case when p_terminal_status='expired' then 'expired' else 'released' end,updated_at=now()
   where id=v_res.id and status='active';
  update public.mme_orders set status=p_terminal_status,updated_at=now() where id=p_order_id and status='pending_payment';
  return true;
end; $$;

create or replace function public.mme_process_serialized_payment_event(
  p_provider_event_id text,p_event_type text,p_provider_object_id text,p_order_id uuid,
  p_amount_received_cents bigint,p_currency text,p_payload_sha256 text
) returns text language plpgsql security definer set search_path=''
as $$
declare v_event_id uuid; v_order record; v_res record; v_unit_id uuid;
begin
  if p_provider_event_id is null or length(btrim(p_provider_event_id))<5 or length(p_provider_event_id)>255
     or p_event_type is null or p_event_type not in ('payment_intent.succeeded','payment_intent.payment_failed')
     or p_provider_object_id is null or length(btrim(p_provider_object_id))=0 or p_order_id is null
     or p_amount_received_cents is null or p_amount_received_cents<0
     or lower(coalesce(p_currency,''))<>'usd'
     or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'Invalid verified payment event' using errcode='22023';
  end if;

  insert into public.mme_payment_events(provider,provider_event_id,event_type,provider_object_id,order_id,processing_status,payload_sha256)
  values('stripe',p_provider_event_id,p_event_type,p_provider_object_id,p_order_id,'received',lower(p_payload_sha256))
  on conflict(provider,provider_event_id) do nothing returning id into v_event_id;
  if v_event_id is null then return 'duplicate'; end if;

  select id,status,total_cents,currency into v_order from public.mme_orders where id=p_order_id for update;
  if not found then
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'order_not_found';
  end if;

  if p_event_type='payment_intent.payment_failed' then
    if v_order.status='pending_payment' then
      perform public.mme_release_serialized_order_reservation(p_order_id,'payment_failed');
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

  select id,status,expires_at into v_res from public.mme_inventory_reservations where order_id=p_order_id for update;
  if not found or v_res.status<>'active' or v_res.expires_at<=now() then
    if found and v_res.status='active' then
      perform public.mme_release_serialized_order_reservation(p_order_id,'expired');
    else
      update public.mme_orders set status='expired',updated_at=now() where id=p_order_id and status='pending_payment';
    end if;
    update public.mme_payment_events set processing_status='failed',processed_at=now() where id=v_event_id;
    return 'reservation_expired_refund_review';
  end if;

  for v_unit_id in
    select unit_id from public.mme_serialized_unit_reservations
     where reservation_id=v_res.id and status='active' order by unit_id for update
  loop
    update public.mme_serialized_units set unit_status='sold',sold_at=now(),updated_at=now()
     where id=v_unit_id and unit_status='reserved';
    if not found then raise exception 'Serialized unit consume invariant violated' using errcode='23514'; end if;
  end loop;

  update public.mme_serialized_unit_reservations set status='consumed',updated_at=now()
   where reservation_id=v_res.id and status='active';
  update public.mme_inventory_reservations set status='consumed',updated_at=now() where id=v_res.id and status='active';
  update public.mme_orders set status='paid',updated_at=now() where id=p_order_id and status='pending_payment';
  update public.mme_payment_events set processing_status='processed',processed_at=now() where id=v_event_id;
  return 'paid_and_serialized_unit_sold';
end; $$;

revoke all on function public.mme_create_serialized_order_and_reserve(text,uuid,uuid,text,jsonb,bigint,bigint,bigint,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_release_serialized_order_reservation(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_process_serialized_payment_event(text,text,text,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.mme_create_serialized_order_and_reserve(text,uuid,uuid,text,jsonb,bigint,bigint,bigint,timestamptz) to service_role;
grant execute on function public.mme_release_serialized_order_reservation(uuid,text) to service_role;
grant execute on function public.mme_process_serialized_payment_event(text,text,text,uuid,bigint,text,text) to service_role;
