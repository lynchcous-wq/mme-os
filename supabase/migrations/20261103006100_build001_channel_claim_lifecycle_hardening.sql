-- Build 001 hardening: allow released serialized units to be claimed again and verify conversion retries.
alter table public.mme_channel_stock_claim_lines
  add column is_active boolean not null default true;

update public.mme_channel_stock_claim_lines l
set is_active=false
from public.mme_channel_stock_claims c
where c.id=l.claim_id and c.status<>'active';

drop index if exists public.mme_channel_claim_serialized_unit_unique;
create unique index mme_channel_claim_serialized_unit_active_unique
  on public.mme_channel_stock_claim_lines(serialized_unit_id)
  where serialized_unit_id is not null and is_active=true;

create or replace function public.mme_release_channel_stock_claim(p_claim_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_claim public.mme_channel_stock_claims%rowtype; v_line record;
begin
  if p_claim_id is null then raise exception 'Claim id required' using errcode='22023'; end if;
  select * into v_claim from public.mme_channel_stock_claims where id=p_claim_id for update;
  if not found or v_claim.status<>'active' then return false; end if;
  for v_line in
    select * from public.mme_channel_stock_claim_lines
    where claim_id=p_claim_id and is_active=true
    order by inventory_balance_id nulls last,serialized_unit_id nulls last
    for update
  loop
    if v_line.inventory_balance_id is not null then
      update public.mme_inventory_balances
      set reserved_quantity=reserved_quantity-v_line.quantity,updated_at=now()
      where id=v_line.inventory_balance_id and reserved_quantity>=v_line.quantity;
      if not found then raise exception 'Aggregate claim release invariant violated' using errcode='23514'; end if;
    else
      update public.mme_serialized_units set unit_status='in_stock',updated_at=now()
      where id=v_line.serialized_unit_id and unit_status='reserved'
        and not exists (
          select 1 from public.mme_serialized_unit_reservations r
          where r.unit_id=v_line.serialized_unit_id and r.status='active'
        );
      if not found then raise exception 'Serialized claim release invariant violated' using errcode='23514'; end if;
    end if;
  end loop;
  update public.mme_channel_stock_claim_lines set is_active=false
    where claim_id=p_claim_id and is_active=true;
  update public.mme_channel_stock_claims
  set status=case when expires_at<=now() then 'expired' else 'released' end,updated_at=now()
  where id=p_claim_id and status='active';
  return true;
end; $$;

create or replace function public.mme_convert_channel_claim_to_order(
  p_claim_id uuid,p_idempotency_key text,p_customer_identity_id uuid,
  p_fulfillment_method text,p_fulfillment_snapshot jsonb,
  p_tax_cents bigint,p_fulfillment_cents bigint,p_discount_cents bigint,
  p_expires_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_claim public.mme_channel_stock_claims%rowtype;
  v_order_id uuid;
  v_reservation_id uuid;
  v_item record;
  v_product public.mme_products%rowtype;
  v_subtotal bigint:=0;
  v_total bigint;
  v_fingerprint text;
  v_existing_fingerprint text;
  v_has_serialized boolean;
  v_has_aggregate boolean;
begin
  if p_claim_id is null or p_idempotency_key is null
    or length(btrim(p_idempotency_key))<8 or length(p_idempotency_key)>128
    or p_fulfillment_method not in ('pickup','shipping')
    or p_fulfillment_snapshot is null or jsonb_typeof(p_fulfillment_snapshot)<>'object'
    or p_tax_cents is null or p_tax_cents<0 or p_fulfillment_cents is null or p_fulfillment_cents<0
    or p_discount_cents is null or p_discount_cents<0
    or p_expires_at is null or p_expires_at<=now()
    or p_expires_at>now()+interval '30 minutes' then
    raise exception 'Invalid channel claim conversion request' using errcode='22023';
  end if;

  v_fingerprint:=md5(jsonb_build_object(
    'claim_id',p_claim_id,'customer_identity_id',p_customer_identity_id,
    'fulfillment_method',p_fulfillment_method,'fulfillment_snapshot',p_fulfillment_snapshot,
    'tax_cents',p_tax_cents,'fulfillment_cents',p_fulfillment_cents,'discount_cents',p_discount_cents
  )::text);

  select * into v_claim from public.mme_channel_stock_claims where id=p_claim_id for update;
  if not found then raise exception 'Stock claim not found' using errcode='P0002'; end if;

  if v_claim.status='converted' and v_claim.converted_order_id is not null then
    select request_fingerprint into v_existing_fingerprint from public.mme_orders
      where id=v_claim.converted_order_id and idempotency_key=p_idempotency_key;
    if not found then raise exception 'Stock claim has already been converted with another request key' using errcode='23505'; end if;
    if v_existing_fingerprint is distinct from v_fingerprint then
      raise exception 'Idempotency key reused with different conversion request' using errcode='23505';
    end if;
    return v_claim.converted_order_id;
  end if;
  if v_claim.status<>'active' or v_claim.expires_at<=now() then
    raise exception 'Only active, unexpired stock claims can convert' using errcode='23514';
  end if;

  select coalesce(bool_or(serialized_unit_id is not null),false),
         coalesce(bool_or(inventory_balance_id is not null),false)
    into v_has_serialized,v_has_aggregate
    from public.mme_channel_stock_claim_lines where claim_id=p_claim_id and is_active=true;
  if v_has_serialized and v_has_aggregate then
    raise exception 'Mixed serialized and aggregate claims require unified payment processing' using errcode='0A000';
  end if;
  if not v_has_serialized and not v_has_aggregate then
    raise exception 'Empty stock claim cannot convert' using errcode='23514';
  end if;

  select id,request_fingerprint into v_order_id,v_existing_fingerprint
    from public.mme_orders where idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing_fingerprint is distinct from v_fingerprint then
      raise exception 'Idempotency key reused with different conversion request' using errcode='23505';
    end if;
    raise exception 'Idempotency key already belongs to another order workflow' using errcode='23505';
  end if;

  for v_item in
    select l.product_id,l.location_id,l.quantity,l.inventory_balance_id,l.serialized_unit_id
    from public.mme_channel_stock_claim_lines l where l.claim_id=p_claim_id and l.is_active=true
    order by l.product_id,l.location_id,l.serialized_unit_id
  loop
    select * into v_product from public.mme_products where id=v_item.product_id for update;
    if not found or not v_product.active or v_product.serialized is distinct from (v_item.serialized_unit_id is not null) then
      raise exception 'Claim product is unavailable or serialization does not match' using errcode='23514';
    end if;
    if v_item.inventory_balance_id is not null then
      perform 1 from public.mme_inventory_balances
       where id=v_item.inventory_balance_id and product_id=v_item.product_id
         and location_id=v_item.location_id and reserved_quantity>=v_item.quantity
         and on_hand_quantity>=v_item.quantity for update;
      if not found then raise exception 'Aggregate claim reservation is no longer valid' using errcode='23514'; end if;
    else
      perform 1 from public.mme_serialized_units
       where id=v_item.serialized_unit_id and product_id=v_item.product_id
         and location_id=v_item.location_id and unit_status='reserved' for update;
      if not found then raise exception 'Serialized claim reservation is no longer valid' using errcode='23514'; end if;
    end if;
    v_subtotal:=v_subtotal+(v_product.unit_price_cents*v_item.quantity);
    if v_subtotal>9000000000000000 then raise exception 'Order subtotal exceeds supported amount' using errcode='22003'; end if;
  end loop;

  v_total:=v_subtotal+p_tax_cents+p_fulfillment_cents-p_discount_cents;
  if p_discount_cents>v_subtotal+p_tax_cents+p_fulfillment_cents
    or v_total<0 or v_total>9000000000000000 then
    raise exception 'Invalid converted order total' using errcode='22003';
  end if;

  insert into public.mme_orders(
    idempotency_key,request_fingerprint,customer_identity_id,status,
    subtotal_cents,tax_cents,fulfillment_cents,discount_cents,total_cents,
    fulfillment_method,fulfillment_snapshot
  ) values (
    p_idempotency_key,v_fingerprint,p_customer_identity_id,'pending_payment',
    v_subtotal,p_tax_cents,p_fulfillment_cents,p_discount_cents,v_total,
    p_fulfillment_method,p_fulfillment_snapshot
  ) returning id into v_order_id;

  insert into public.mme_inventory_reservations(order_id,expires_at)
  values(v_order_id,p_expires_at) returning id into v_reservation_id;

  for v_item in
    select l.product_id,l.location_id,l.quantity,l.inventory_balance_id,l.serialized_unit_id
    from public.mme_channel_stock_claim_lines l where l.claim_id=p_claim_id and l.is_active=true
    order by l.product_id,l.location_id,l.serialized_unit_id
  loop
    select * into v_product from public.mme_products where id=v_item.product_id;
    if v_item.inventory_balance_id is not null then
      insert into public.mme_inventory_reservation_lines(
        reservation_id,inventory_balance_id,product_id,location_id,quantity
      ) values(v_reservation_id,v_item.inventory_balance_id,v_item.product_id,v_item.location_id,v_item.quantity);
      insert into public.mme_order_lines(
        order_id,product_id,location_id,sku_snapshot,title_snapshot,condition_snapshot,
        quantity,unit_price_cents,line_total_cents
      ) values(v_order_id,v_product.id,v_item.location_id,v_product.sku,v_product.title,
        v_product.condition_grade,v_item.quantity,v_product.unit_price_cents,v_product.unit_price_cents*v_item.quantity);
    else
      insert into public.mme_serialized_unit_reservations(
        reservation_id,order_id,unit_id,serial_snapshot,imei_snapshot,status
      ) select v_reservation_id,v_order_id,u.id,u.serial_number,u.imei,'active'
        from public.mme_serialized_units u where u.id=v_item.serialized_unit_id;
      insert into public.mme_order_lines(
        order_id,product_id,location_id,sku_snapshot,title_snapshot,condition_snapshot,
        quantity,unit_price_cents,line_total_cents,serialized_unit_id,serial_number_snapshot,imei_snapshot
      ) select v_order_id,p.id,u.location_id,p.sku,p.title,u.condition_grade,1,p.unit_price_cents,
        p.unit_price_cents,u.id,u.serial_number,u.imei
        from public.mme_serialized_units u join public.mme_products p on p.id=u.product_id
        where u.id=v_item.serialized_unit_id;
    end if;
  end loop;

  update public.mme_channel_stock_claim_lines set is_active=false
    where claim_id=p_claim_id and is_active=true;
  update public.mme_channel_stock_claims set status='converted',converted_order_id=v_order_id,updated_at=now()
   where id=p_claim_id and status='active';
  if not found then raise exception 'Stock claim conversion race detected' using errcode='23514'; end if;
  return v_order_id;
end; $$;

revoke all on function public.mme_release_channel_stock_claim(uuid) from public,anon,authenticated;
revoke all on function public.mme_convert_channel_claim_to_order(uuid,text,uuid,text,jsonb,bigint,bigint,bigint,timestamptz) from public,anon,authenticated;
grant execute on function public.mme_release_channel_stock_claim(uuid) to service_role;
grant execute on function public.mme_convert_channel_claim_to_order(uuid,text,uuid,text,jsonb,bigint,bigint,bigint,timestamptz) to service_role;

comment on column public.mme_channel_stock_claim_lines.is_active is
 'True while the claim owns its stock lock; false after release, expiry or conversion. Preserves historical claim lines without blocking future holds.';
