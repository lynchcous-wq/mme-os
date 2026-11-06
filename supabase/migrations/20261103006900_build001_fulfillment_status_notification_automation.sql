-- Build 001: automatically queue customer email after fulfillment state transitions.
create or replace function public.mme_queue_fulfillment_status_email()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_order public.mme_orders%rowtype;
 v_template text;
 v_idempotency text;
 v_data jsonb;
begin
 if new.fulfillment_status is not distinct from old.fulfillment_status then return new; end if;
 v_template:=case new.fulfillment_status
  when 'picking' then 'order_picking'
  when 'shipped' then 'order_shipped'
  when 'ready_for_pickup' then 'pickup_ready'
  when 'delivered' then 'order_delivered'
  when 'picked_up' then 'order_picked_up'
  when 'exception' then 'fulfillment_exception'
  else null end;
 if v_template is null then return new; end if;
 select * into v_order from public.mme_orders where id=new.order_id;
 if not found or v_order.status not in ('paid','partially_refunded') then return new; end if;
 if new.recipient_contact_snapshot is null or position('@' in new.recipient_contact_snapshot)=0 then return new; end if;
 v_idempotency:='fulfillment:'||new.id::text||':'||new.fulfillment_status||':'||to_char(new.updated_at at time zone 'UTC','YYYYMMDDHH24MISSMS');
 v_data:=jsonb_build_object(
  'order_id',new.order_id,'fulfillment_id',new.id,
  'fulfillment_method',new.fulfillment_method,'fulfillment_status',new.fulfillment_status,
  'customer_name',new.recipient_name_snapshot,'carrier',new.carrier_name,
  'service_level',new.service_level,'tracking_number',new.tracking_number,
  'tracking_url',case when new.tracking_url like 'https://%' then new.tracking_url else null end,
  'pickup_ready_at',new.pickup_ready_at,'pickup_location_id',new.pickup_location_id,
  'package_count',new.package_count
 );
 perform public.mme_queue_fulfillment_notification(
  new.order_id,new.id,'email',new.recipient_contact_snapshot,v_template,v_idempotency,v_data
 );
 return new;
end; $$;
drop trigger if exists mme_fulfillment_status_customer_email on public.mme_order_fulfillments;
create trigger mme_fulfillment_status_customer_email
 after update of fulfillment_status on public.mme_order_fulfillments
 for each row execute function public.mme_queue_fulfillment_status_email();
revoke all on function public.mme_queue_fulfillment_status_email() from public,anon,authenticated;
comment on function public.mme_queue_fulfillment_status_email() is
 'Queues one idempotent customer email for eligible fulfillment status transitions; delivery is handled asynchronously by the trusted notification worker.';
