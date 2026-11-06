-- Build 001: idempotent paid-order fulfillment initialization and customer order history.
create or replace function public.mme_finalize_paid_order_fulfillment(
 p_order_id uuid,p_system_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_order public.mme_orders%rowtype;
 v_snapshot jsonb;
 v_fulfillment_id uuid;
 v_email text;
 v_name text;
 v_phone text;
 v_pickup_location_id uuid;
 v_address jsonb;
begin
 if p_order_id is null or p_system_actor_identity_id is null then
  raise exception 'Order and system actor are required' using errcode='22023';
 end if;
 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found or v_order.status not in ('paid','partially_refunded') then
  raise exception 'Only verified paid orders can be finalized' using errcode='23514';
 end if;
 v_snapshot:=v_order.fulfillment_snapshot;
 v_email:=nullif(btrim(v_snapshot->>'customer_email'),'');
 v_name:=nullif(btrim(v_snapshot->>'customer_name'),'');
 v_phone:=nullif(btrim(v_snapshot->>'customer_phone'),'');
 if v_email is null or length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
  raise exception 'Paid order has no valid customer email snapshot' using errcode='23514';
 end if;
 if v_order.fulfillment_method='pickup' then
  begin v_pickup_location_id:=(v_snapshot->>'pickup_location_id')::uuid;
  exception when others then raise exception 'Pickup location snapshot is invalid' using errcode='23514'; end;
  v_fulfillment_id:=public.mme_create_order_fulfillment(
   p_order_id,p_system_actor_identity_id,v_pickup_location_id,v_name,v_email,null);
 else
  v_address:=v_snapshot->'shipping_address';
  if v_address is null or jsonb_typeof(v_address)<>'object' then
   raise exception 'Shipping address snapshot is missing' using errcode='23514';
  end if;
  v_fulfillment_id:=public.mme_create_order_fulfillment(
   p_order_id,p_system_actor_identity_id,null,v_name,v_email,v_address);
 end if;

 perform public.mme_queue_fulfillment_notification(
  p_order_id,v_fulfillment_id,'email',v_email,'order_paid',
  'order-paid:'||p_order_id::text,
  jsonb_build_object(
   'order_id',p_order_id,'fulfillment_id',v_fulfillment_id,
   'customer_name',v_name,'fulfillment_method',v_order.fulfillment_method,
   'total_cents',v_order.total_cents,'currency',v_order.currency,
   'pickup_location_name',v_snapshot->>'pickup_location_name',
   'shipping_address',case when v_order.fulfillment_method='shipping'
     then jsonb_build_object('city',v_address->>'city','state',v_address->>'state','postal_code',v_address->>'postal_code')
     else null end
  )
 );
 return v_fulfillment_id;
end; $$;
revoke all on function public.mme_finalize_paid_order_fulfillment(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_finalize_paid_order_fulfillment(uuid,uuid) to service_role;
comment on function public.mme_finalize_paid_order_fulfillment(uuid,uuid) is
 'Idempotently creates the fulfillment record and queues one transactional email after a signature-verified Stripe payment event marks the order paid.';

-- Customer history is scoped to the authenticated MME person identity; no arbitrary identity argument.
create or replace function public.mme_get_my_order_history()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_identity_id uuid; v_result jsonb;
begin
 select id into v_identity_id from public.mme_person_identities
 where auth_user_id=auth.uid() and security_status='active';
 if v_identity_id is null then return '[]'::jsonb; end if;
 if not exists(select 1 from public.mme_customer_relationships
  where person_identity_id=v_identity_id and status='active') then return '[]'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',o.id,'status',o.status,'currency',o.currency,
  'subtotal_cents',o.subtotal_cents,'tax_cents',o.tax_cents,
  'fulfillment_cents',o.fulfillment_cents,'discount_cents',o.discount_cents,
  'total_cents',o.total_cents,'fulfillment_method',o.fulfillment_method,
  'created_at',o.created_at,'updated_at',o.updated_at,
  'fulfillment',case when f.id is null then null else jsonb_build_object(
    'status',f.fulfillment_status,'carrier',f.carrier_name,
    'tracking_number',f.tracking_number,'tracking_url',f.tracking_url,
    'pickup_ready_at',f.pickup_ready_at,'pickup_completed_at',f.pickup_completed_at,
    'pickup_location_id',f.pickup_location_id
  ) end,
  'items',coalesce((select jsonb_agg(jsonb_build_object(
    'title',l.title_snapshot,'sku',l.sku_snapshot,'condition',l.condition_snapshot,
    'quantity',l.quantity,'unit_price_cents',l.unit_price_cents,
    'line_total_cents',l.line_total_cents
  ) order by l.created_at) from public.mme_order_lines l where l.order_id=o.id),'[]'::jsonb)
 ) order by o.created_at desc),'[]'::jsonb) into v_result
 from public.mme_orders o left join public.mme_order_fulfillments f on f.order_id=o.id
 where o.customer_identity_id=v_identity_id;
 return v_result;
end; $$;
revoke all on function public.mme_get_my_order_history() from public,anon;
grant execute on function public.mme_get_my_order_history() to authenticated;
comment on function public.mme_get_my_order_history() is
 'Returns only the calling authenticated active customer identity own orders, line snapshots, and non-sensitive fulfillment status.';
