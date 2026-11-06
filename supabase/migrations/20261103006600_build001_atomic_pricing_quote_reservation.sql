-- Build 001: bind trusted pricing quote to order creation and inventory reservation atomically.
-- The expected subtotal is checked after current product rows are locked and re-read,
-- but before order/reservation inserts. A stale quote raises and rolls back the transaction.
-- Build 001: one order/reservation transaction for aggregate and serialized cart lines.
create or replace function public.mme_create_mixed_order_and_reserve(
 p_idempotency_key text,p_customer_identity_id uuid,p_fulfillment_method text,
 p_fulfillment_snapshot jsonb,p_tax_cents bigint,p_fulfillment_cents bigint,
 p_discount_cents bigint,p_items jsonb,p_expected_subtotal_cents bigint,p_expires_at timestamptz
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_fingerprint text; v_existing_id uuid; v_existing_fp text; v_order_id uuid;
 v_reservation_id uuid; v_item record; v_product record; v_unit record;
 v_balance record; v_subtotal bigint:=0; v_line_total bigint; v_total bigint;
begin
 if p_idempotency_key is null or length(btrim(p_idempotency_key))<8 or length(p_idempotency_key)>128
  or p_customer_identity_id is null or p_fulfillment_method not in ('pickup','shipping')
  or p_fulfillment_snapshot is null or jsonb_typeof(p_fulfillment_snapshot)<>'object'
  or p_tax_cents is null or p_tax_cents<0 or p_fulfillment_cents is null or p_fulfillment_cents<0
  or p_discount_cents is null or p_discount_cents<0 or p_expected_subtotal_cents is null or p_expected_subtotal_cents<0 or p_items is null
  or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0
  or jsonb_array_length(p_items)>50 or p_expires_at is null or p_expires_at<=now()
  or p_expires_at>now()+interval '30 minutes' then
  raise exception 'Invalid mixed order request' using errcode='22023';
 end if;
 if exists(
  select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
  where x.product_id is null or x.location_id is null or x.quantity is null or x.quantity<1 or x.quantity>20
     or (x.serialized_unit_id is not null and x.quantity<>1)
 ) or exists(
  select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
  where x.serialized_unit_id is null group by x.product_id,x.location_id having count(*)>1
 ) or exists(
  select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
  where x.serialized_unit_id is not null group by x.serialized_unit_id having count(*)>1
 ) then raise exception 'Invalid or duplicate mixed order lines' using errcode='22023'; end if;

 v_fingerprint:=md5(jsonb_build_object('expected_subtotal_cents',p_expected_subtotal_cents,'customer_identity_id',p_customer_identity_id,
  'fulfillment_method',p_fulfillment_method,'fulfillment_snapshot',p_fulfillment_snapshot,
  'tax_cents',p_tax_cents,'fulfillment_cents',p_fulfillment_cents,'discount_cents',p_discount_cents,'items',p_items)::text);
 select id,request_fingerprint into v_existing_id,v_existing_fp from public.mme_orders
  where idempotency_key=p_idempotency_key for update;
 if found then
  if v_existing_fp<>v_fingerprint then raise exception 'Idempotency key reused with different request' using errcode='23505'; end if;
  return v_existing_id;
 end if;

 -- Deterministic lock order avoids deadlocks across carts.
 for v_item in select x.* from jsonb_to_recordset(p_items)
  as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
  order by x.product_id,x.location_id,coalesce(x.serialized_unit_id,'00000000-0000-0000-0000-000000000000'::uuid)
 loop
  if v_item.serialized_unit_id is not null then
   select u.id,u.product_id,u.location_id,u.serial_number,u.imei,u.condition_grade,u.unit_status,
    p.sku,p.title,p.unit_price_cents,p.active,p.serialized
   into v_unit from public.mme_serialized_units u join public.mme_products p on p.id=u.product_id
   where u.id=v_item.serialized_unit_id for update of u,p;
   if not found or v_unit.product_id<>v_item.product_id or v_unit.location_id<>v_item.location_id
    or v_unit.unit_status<>'in_stock' or not v_unit.active or not v_unit.serialized then
    raise exception 'Serialized unit unavailable or does not match cart line' using errcode='P0002';
   end if;
   v_line_total:=v_unit.unit_price_cents;
   v_subtotal:=v_subtotal+v_line_total;
  else
   select p.id,p.sku,p.title,p.condition_grade,p.unit_price_cents,p.active,p.serialized
   into v_product from public.mme_products p where p.id=v_item.product_id for update;
   if not found or not v_product.active or v_product.serialized then
    raise exception 'Aggregate product unavailable' using errcode='P0002';
   end if;
   v_line_total:=v_product.unit_price_cents*v_item.quantity;
   v_subtotal:=v_subtotal+v_line_total;
  end if;
  if v_line_total>9000000000000000 or v_subtotal>9000000000000000 then
   raise exception 'Order amount exceeds supported range' using errcode='22003';
  end if;
 end loop;

 if v_subtotal<>p_expected_subtotal_cents then
  raise exception 'Quoted subtotal changed; refresh cart before checkout' using errcode='40001';
 end if;

 v_total:=v_subtotal+p_tax_cents+p_fulfillment_cents-p_discount_cents;
 if p_discount_cents>v_subtotal+p_tax_cents+p_fulfillment_cents or v_total<0 or v_total>9000000000000000 then
  raise exception 'Invalid mixed order total' using errcode='22003';
 end if;
 insert into public.mme_orders(idempotency_key,request_fingerprint,customer_identity_id,status,
  subtotal_cents,tax_cents,fulfillment_cents,discount_cents,total_cents,fulfillment_method,fulfillment_snapshot)
 values(p_idempotency_key,v_fingerprint,p_customer_identity_id,'pending_payment',
  v_subtotal,p_tax_cents,p_fulfillment_cents,p_discount_cents,v_total,p_fulfillment_method,p_fulfillment_snapshot)
 returning id into v_order_id;

 insert into public.mme_inventory_reservations(order_id,expires_at)
 values(v_order_id,p_expires_at) returning id into v_reservation_id;

 for v_item in select x.* from jsonb_to_recordset(p_items)
  as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
  order by x.product_id,x.location_id,coalesce(x.serialized_unit_id,'00000000-0000-0000-0000-000000000000'::uuid)
 loop
  if v_item.serialized_unit_id is not null then
   select u.id,u.product_id,u.location_id,u.serial_number,u.imei,u.condition_grade,u.unit_status,
    p.sku,p.title,p.unit_price_cents,p.active,p.serialized
   into v_unit from public.mme_serialized_units u join public.mme_products p on p.id=u.product_id
   where u.id=v_item.serialized_unit_id;
   update public.mme_serialized_units set unit_status='reserved',updated_at=now()
    where id=v_item.serialized_unit_id and unit_status='in_stock';
   if not found then raise exception 'Serialized unit was reserved concurrently' using errcode='P0001'; end if;
   insert into public.mme_serialized_unit_reservations(reservation_id,order_id,unit_id,serial_snapshot,imei_snapshot,status)
   values(v_reservation_id,v_order_id,v_unit.id,v_unit.serial_number,v_unit.imei,'active');
   insert into public.mme_order_lines(order_id,product_id,location_id,sku_snapshot,title_snapshot,condition_snapshot,
    quantity,unit_price_cents,line_total_cents,serialized_unit_id,serial_number_snapshot,imei_snapshot)
   values(v_order_id,v_unit.product_id,v_unit.location_id,v_unit.sku,v_unit.title,v_unit.condition_grade,
    1,v_unit.unit_price_cents,v_unit.unit_price_cents,v_unit.id,v_unit.serial_number,v_unit.imei);
  else
   select b.id,b.on_hand_quantity,b.reserved_quantity into v_balance
   from public.mme_inventory_balances b join public.mme_store_locations l on l.id=b.location_id
   where b.product_id=v_item.product_id and b.location_id=v_item.location_id and l.active=true
   for update of b;
   if not found or v_balance.on_hand_quantity-v_balance.reserved_quantity<v_item.quantity then
    raise exception 'Insufficient aggregate inventory' using errcode='P0001';
   end if;
   update public.mme_inventory_balances set reserved_quantity=reserved_quantity+v_item.quantity,updated_at=now()
    where id=v_balance.id;
   insert into public.mme_inventory_reservation_lines(reservation_id,inventory_balance_id,product_id,location_id,quantity)
   values(v_reservation_id,v_balance.id,v_item.product_id,v_item.location_id,v_item.quantity);
   select id,sku,title,condition_grade,unit_price_cents into v_product from public.mme_products where id=v_item.product_id;
   v_line_total:=v_product.unit_price_cents*v_item.quantity;
   insert into public.mme_order_lines(order_id,product_id,location_id,sku_snapshot,title_snapshot,condition_snapshot,
    quantity,unit_price_cents,line_total_cents)
   values(v_order_id,v_item.product_id,v_item.location_id,v_product.sku,v_product.title,v_product.condition_grade,
    v_item.quantity,v_product.unit_price_cents,v_line_total);
  end if;
 end loop;
 return v_order_id;
end; $$;

revoke all on function public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz) from public,anon,authenticated;
grant execute on function public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamptz) to service_role;
comment on function public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamptz) is
 'Atomic mixed cart order creation. Validates the externally quoted subtotal under the same product and inventory locks used to create the order and reserve stock. Stale quotes roll back before any reservation commits.';
