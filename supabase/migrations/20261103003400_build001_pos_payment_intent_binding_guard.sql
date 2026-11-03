-- Build 001: enforce PaymentIntent-to-order binding for every Stripe payment event,
-- including serialized checkout. This closes the serialized processor's missing intent-binding check.

create or replace function public.mme_guard_order_payment_event_binding()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_intent public.mme_order_payment_intents%rowtype;
begin
 if new.event_type in ('payment_intent.succeeded','payment_intent.payment_failed') then
  if new.order_id is null or new.provider_object_id is null then
   raise exception 'Stripe PaymentIntent event requires an order and PaymentIntent ID' using errcode='23514';
  end if;
  select * into v_intent from public.mme_order_payment_intents
   where order_id=new.order_id and provider_object_id=new.provider_object_id;
  if not found then
   raise exception 'Stripe PaymentIntent is not bound to the supplied order' using errcode='23514';
  end if;
 end if;
 return new;
end; $$;

drop trigger if exists mme_payment_event_intent_binding_guard on public.mme_payment_events;
create trigger mme_payment_event_intent_binding_guard
 before insert on public.mme_payment_events
 for each row execute function public.mme_guard_order_payment_event_binding();

revoke all on function public.mme_guard_order_payment_event_binding() from public,anon,authenticated;
comment on function public.mme_guard_order_payment_event_binding() is
 'Requires every Stripe PaymentIntent event to reference the exact server-bound PaymentIntent for its order; protects aggregate and serialized checkout paths.';
