create table if not exists public.mme_order_payment_intents (
 id uuid primary key default gen_random_uuid(),
 provider text not null check (provider='stripe'),
 provider_object_id text not null,
 order_id uuid not null unique references public.mme_orders(id) on delete restrict,
 expected_amount_cents bigint not null check (expected_amount_cents>=0),
 currency text not null default 'USD' check (currency='USD'),
 bound_customer_identity_id uuid not null,
 created_at timestamptz not null default now(),
 unique(provider,provider_object_id)
);

-- Add the customer binding to the pre-existing ledger without discarding rows.
alter table public.mme_order_payment_intents add column if not exists bound_customer_identity_id uuid;
update public.mme_order_payment_intents i set bound_customer_identity_id=o.customer_identity_id from public.mme_orders o where o.id=i.order_id and i.bound_customer_identity_id is null and o.customer_identity_id is not null;

alter table public.mme_order_payment_intents enable row level security;
revoke all on public.mme_order_payment_intents from public,anon,authenticated;
grant all on public.mme_order_payment_intents to service_role;

create or replace function public.mme_bind_order_payment_intent(
 p_order_id uuid,p_provider_object_id text,p_expected_amount_cents bigint,
 p_currency text,p_customer_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_order public.mme_orders%rowtype; v_binding_id uuid; v_existing public.mme_order_payment_intents%rowtype;
begin
 if p_order_id is null or p_provider_object_id is null or length(btrim(p_provider_object_id)) not between 5 and 255
  or p_expected_amount_cents is null or p_expected_amount_cents<0
  or upper(coalesce(p_currency,''))<>'USD' or p_customer_identity_id is null then
  raise exception 'Invalid PaymentIntent binding request' using errcode='22023';
 end if;
 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found or v_order.status<>'pending_payment' then
  raise exception 'Only pending orders can bind a PaymentIntent' using errcode='23514';
 end if;
 if v_order.customer_identity_id is distinct from p_customer_identity_id then
  raise exception 'Customer does not own this order' using errcode='42501';
 end if;
 if v_order.total_cents<>p_expected_amount_cents or v_order.currency<>'USD' then
  raise exception 'PaymentIntent amount does not match authoritative order total' using errcode='23514';
 end if;
 select * into v_existing from public.mme_order_payment_intents
  where order_id=p_order_id or (provider='stripe' and provider_object_id=btrim(p_provider_object_id))
  for update;
 if found then
  if v_existing.order_id=p_order_id and v_existing.provider_object_id=btrim(p_provider_object_id)
   and v_existing.expected_amount_cents=p_expected_amount_cents
   and v_existing.bound_customer_identity_id=p_customer_identity_id then return v_existing.id; end if;
  raise exception 'Order or PaymentIntent already bound' using errcode='23505';
 end if;
 insert into public.mme_order_payment_intents(provider,provider_object_id,order_id,expected_amount_cents,currency,bound_customer_identity_id,created_by_identity_id)
 values('stripe',btrim(p_provider_object_id),p_order_id,p_expected_amount_cents,'USD',p_customer_identity_id,p_customer_identity_id)
 returning id into v_binding_id;
 return v_binding_id;
end; $$;
revoke all on function public.mme_bind_order_payment_intent(uuid,text,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_bind_order_payment_intent(uuid,text,bigint,text,uuid) to service_role;
