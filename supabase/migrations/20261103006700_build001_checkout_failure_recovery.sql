-- Build 001: safe reservation expiration after provider-side payment-intent reconciliation.
create table if not exists public.mme_checkout_recovery_cases (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 provider text not null default 'stripe' check (provider='stripe'),
 provider_object_id text,
 case_type text not null check (case_type in (
  'payment_succeeded_after_reservation_expiry',
  'payment_intent_binding_missing',
  'payment_intent_status_unresolved',
  'payment_intent_cancel_failed'
 )),
 provider_status text,
 details jsonb not null default '{}'::jsonb check (jsonb_typeof(details)='object'),
 status text not null default 'open' check (status in ('open','resolved')),
 attempts integer not null default 1 check (attempts>=1),
 last_error text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 resolved_at timestamptz,
 unique(order_id,case_type)
);
create index if not exists mme_checkout_recovery_cases_open_idx
 on public.mme_checkout_recovery_cases(created_at) where status='open';
alter table public.mme_checkout_recovery_cases enable row level security;
revoke all on public.mme_checkout_recovery_cases from public,anon,authenticated;
grant all on public.mme_checkout_recovery_cases to service_role;

create or replace function public.mme_expire_single_inventory_reservation(p_order_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare
 v_order public.mme_orders%rowtype;
 v_res public.mme_inventory_reservations%rowtype;
 v_line record;
 v_unit_id uuid;
begin
 if p_order_id is null then raise exception 'Order ID required' using errcode='22023'; end if;
 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found or v_order.status<>'pending_payment' then return false; end if;
 select * into v_res from public.mme_inventory_reservations where order_id=p_order_id for update;
 if not found or v_res.status<>'active' or v_res.expires_at>now() then return false; end if;

 -- Release aggregate and serialized lines in one transaction, including mixed carts.
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
 update public.mme_serialized_unit_reservations set status='expired',updated_at=now()
  where reservation_id=v_res.id and status='active';
 update public.mme_inventory_reservations set status='expired',updated_at=now() where id=v_res.id;
 update public.mme_orders set status='expired',updated_at=now()
  where id=p_order_id and status='pending_payment';
 return true;
end; $$;
revoke all on function public.mme_expire_single_inventory_reservation(uuid) from public,anon,authenticated;
grant execute on function public.mme_expire_single_inventory_reservation(uuid) to service_role;
comment on function public.mme_expire_single_inventory_reservation(uuid) is
 'Expires exactly one due pending-payment reservation after the caller has reconciled/canceled its Stripe PaymentIntent; preserves payment-success exceptions for manual refund handling.';
