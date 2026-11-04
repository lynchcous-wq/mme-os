-- Build 001: explicit binding between an approved MME refund and the Stripe refund created by the trusted server adapter.
-- This registry does not initiate refunds and does not infer approval from a PaymentIntent alone.

create table public.mme_return_refund_provider_bindings (
 id uuid primary key default gen_random_uuid(),
 approval_id uuid not null unique references public.mme_return_refund_approvals(id) on delete restrict,
 provider text not null check(provider='stripe'),
 provider_payment_intent_id text not null check(length(btrim(provider_payment_intent_id)) between 5 and 255),
 provider_refund_id text not null unique check(length(btrim(provider_refund_id)) between 5 and 255),
 amount_cents bigint not null check(amount_cents>0),
 currency text not null default 'USD' check(currency='USD'),
 bound_by_identity_id uuid not null,
 bound_at timestamptz not null default now()
);

alter table public.mme_return_refund_provider_bindings enable row level security;
revoke all on public.mme_return_refund_provider_bindings from public,anon,authenticated;
grant all on public.mme_return_refund_provider_bindings to service_role;

create or replace function public.mme_bind_approved_stripe_refund(
 p_approval_id uuid,
 p_payment_intent_id text,
 p_refund_id text,
 p_amount_cents bigint,
 p_currency text,
 p_actor_identity_id uuid
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
 v_approval public.mme_return_refund_approvals%rowtype;
 v_case public.mme_return_cases%rowtype;
 v_binding public.mme_order_payment_intents%rowtype;
 v_id uuid;
begin
 if p_approval_id is null or p_payment_intent_id is null
  or length(btrim(p_payment_intent_id)) not between 5 and 255
  or p_refund_id is null or length(btrim(p_refund_id)) not between 5 and 255
  or p_amount_cents is null or p_amount_cents<=0
  or upper(coalesce(p_currency,''))<>'USD' or p_actor_identity_id is null then
  raise exception 'Invalid Stripe refund binding' using errcode='22023';
 end if;

 select * into v_approval from public.mme_return_refund_approvals
  where id=p_approval_id for update;
 if not found or v_approval.decision<>'approved'
  or v_approval.approved_amount_cents<>p_amount_cents
  or v_approval.currency<>'USD' then
  raise exception 'Refund does not match an approved MME refund' using errcode='23514';
 end if;

 select * into v_case from public.mme_return_cases
  where id=v_approval.return_case_id;
 if not found then raise exception 'Return case not found' using errcode='23503'; end if;

 select * into v_binding from public.mme_order_payment_intents
  where order_id=v_case.order_id and provider='stripe'
   and provider_object_id=btrim(p_payment_intent_id);
 if not found then
  raise exception 'Stripe PaymentIntent is not bound to the return order' using errcode='23514';
 end if;

 insert into public.mme_return_refund_provider_bindings(
  approval_id,provider,provider_payment_intent_id,provider_refund_id,
  amount_cents,currency,bound_by_identity_id
 ) values (
  p_approval_id,'stripe',btrim(p_payment_intent_id),btrim(p_refund_id),
  p_amount_cents,'USD',p_actor_identity_id
 ) returning id into v_id;
 return v_id;
end;
$$;

revoke all on function public.mme_bind_approved_stripe_refund(uuid,text,text,bigint,text,uuid)
 from public,anon,authenticated;
grant execute on function public.mme_bind_approved_stripe_refund(uuid,text,text,bigint,text,uuid)
 to service_role;

comment on table public.mme_return_refund_provider_bindings is
 'Explicit server-created Stripe refund to MME approved return refund mapping; webhook handlers must match both PaymentIntent and Refund IDs. This table does not initiate refunds.';
