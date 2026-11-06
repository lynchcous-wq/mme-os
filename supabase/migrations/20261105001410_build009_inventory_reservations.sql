-- Build 009.61 — atomic multi-channel stock reservations and allocation.
begin;
create table public.mme_inventory_reservations (
 reservation_id uuid primary key default gen_random_uuid(),
 idempotency_key text not null unique,
 sku_reference text not null, location_code text not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 quantity bigint not null check(quantity>0),
 channel text not null check(channel in ('pos','website','local_pickup','shipping','subscription','staff','auction')),
 customer_reference text, order_reference text,
 priority_class text not null default 'standard' check(priority_class in ('standard','member','priority','staff')),
 status text not null default 'active' check(status in ('active','consumed','released','expired','cancelled')),
 reserved_by uuid not null, reserved_at timestamptz not null default now(),
 expires_at timestamptz not null,
 consumed_at timestamptz, released_at timestamptz,
 release_reason text, metadata jsonb not null default '{}'::jsonb,
 check(expires_at>reserved_at),
 check((status='consumed' and consumed_at is not null) or status<>'consumed')
);
create index mme_inventory_reservations_active_idx on public.mme_inventory_reservations(location_code,sku_reference,expires_at) where status='active';
create index mme_inventory_reservations_order_idx on public.mme_inventory_reservations(order_reference,channel);
create table public.mme_inventory_reservation_events (
 event_id bigint generated always as identity primary key,
 reservation_id uuid not null references public.mme_inventory_reservations(reservation_id) on delete restrict,
 event_type text not null check(event_type in ('reserved','consumed','released','expired','cancelled')),
 actor_user_id uuid not null, event_data jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
alter table public.mme_inventory_reservations enable row level security;
alter table public.mme_inventory_reservation_events enable row level security;
revoke all on public.mme_inventory_reservations,public.mme_inventory_reservation_events from public,anon,authenticated;
grant select on public.mme_inventory_reservations to service_role;
grant select,insert on public.mme_inventory_reservation_events to service_role;
revoke update,delete,truncate on public.mme_inventory_reservation_events from public,anon,authenticated,service_role;

create or replace function public.mme_inventory_reserve_stock(
 p_sku text,p_location text,p_currency text,p_quantity bigint,p_channel text,
 p_customer_ref text,p_order_ref text,p_priority text,p_actor uuid,
 p_expires_at timestamptz,p_idempotency_key text,p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare b public.mme_inventory_balances%rowtype; r public.mme_inventory_reservations%rowtype; v_id uuid;
begin
 if p_quantity<1 or p_actor is null or p_expires_at<=now() or p_expires_at>now()+interval '7 days'
  or length(trim(coalesce(p_idempotency_key,'')))<12 then
  raise exception 'Invalid reservation quantity, actor, expiry or idempotency key' using errcode='22023';
 end if;
 if p_channel not in ('pos','website','local_pickup','shipping','subscription','staff','auction')
  or p_priority not in ('standard','member','priority','staff') then raise exception 'Unsupported channel or priority' using errcode='22023'; end if;
 select * into r from public.mme_inventory_reservations where idempotency_key=p_idempotency_key;
 if found then
  if r.sku_reference<>p_sku or r.location_code<>p_location or r.quantity<>p_quantity or r.order_reference is distinct from p_order_ref then
   raise exception 'Idempotency key reused with different reservation payload' using errcode='23505';
  end if;
  return r.reservation_id;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_sku||'|'||p_location||'|'||p_currency,0));
 select * into b from public.mme_inventory_balances where sku_reference=p_sku and location_code=p_location and currency_code=p_currency for update;
 if not found or b.on_hand_quantity-b.reserved_quantity<p_quantity then
  raise exception 'Insufficient available inventory' using errcode='23514';
 end if;
 insert into public.mme_inventory_reservations(idempotency_key,sku_reference,location_code,currency_code,quantity,channel,customer_reference,order_reference,priority_class,reserved_by,expires_at,metadata)
 values(p_idempotency_key,p_sku,p_location,p_currency,p_quantity,p_channel,p_customer_ref,p_order_ref,p_priority,p_actor,p_expires_at,coalesce(p_metadata,'{}'::jsonb))
 returning reservation_id into v_id;
 update public.mme_inventory_balances set reserved_quantity=reserved_quantity+p_quantity,version=version+1,updated_at=now() where balance_id=b.balance_id;
 insert into public.mme_inventory_reservation_events(reservation_id,event_type,actor_user_id,event_data)
 values(v_id,'reserved',p_actor,jsonb_build_object('quantity',p_quantity,'channel',p_channel,'expires_at',p_expires_at));
 return v_id;
end; $$;

create or replace function public.mme_inventory_release_reservation(p_reservation uuid,p_actor uuid,p_reason text,p_terminal_status text default 'released')
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_inventory_reservations%rowtype; b public.mme_inventory_balances%rowtype; ev text;
begin
 select * into r from public.mme_inventory_reservations where reservation_id=p_reservation for update;
 if not found then raise exception 'Reservation not found' using errcode='22023'; end if;
 if r.status<>'active' then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(r.sku_reference||'|'||r.location_code||'|'||r.currency_code,0));
 select * into b from public.mme_inventory_balances where sku_reference=r.sku_reference and location_code=r.location_code and currency_code=r.currency_code for update;
 if not found or b.reserved_quantity<r.quantity then raise exception 'Reservation balance invariant failed' using errcode='23514'; end if;
 update public.mme_inventory_balances set reserved_quantity=reserved_quantity-r.quantity,version=version+1,updated_at=now() where balance_id=b.balance_id;
 ev:=case when p_terminal_status='expired' then 'expired' when p_terminal_status='cancelled' then 'cancelled' else 'released' end;
 if p_terminal_status not in ('released','expired','cancelled') then raise exception 'Invalid terminal reservation status' using errcode='22023'; end if;
 update public.mme_inventory_reservations set status=p_terminal_status,released_at=now(),release_reason=left(coalesce(p_reason,''),500) where reservation_id=p_reservation;
 insert into public.mme_inventory_reservation_events(reservation_id,event_type,actor_user_id,event_data)
 values(p_reservation,ev,p_actor,jsonb_build_object('reason',p_reason));
end; $$;

create or replace function public.mme_inventory_expire_reservations(p_actor uuid,p_limit integer default 100)
returns integer language plpgsql security definer set search_path=pg_catalog,public as $$
declare r record; n integer:=0;
begin
 if p_limit<1 or p_limit>1000 then raise exception 'Batch limit must be 1..1000' using errcode='22023'; end if;
 for r in select reservation_id from public.mme_inventory_reservations
  where status='active' and expires_at<=now() order by expires_at
  for update skip locked limit p_limit
 loop
  perform public.mme_inventory_release_reservation(r.reservation_id,p_actor,'Reservation TTL elapsed','expired');
  n:=n+1;
 end loop;
 return n;
end; $$;

create or replace function public.mme_inventory_consume_reservation(p_reservation uuid,p_actor uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_inventory_reservations%rowtype; b public.mme_inventory_balances%rowtype; e uuid; v numeric(18,2);
begin
 if length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Idempotency key required' using errcode='22023'; end if;
 select * into r from public.mme_inventory_reservations where reservation_id=p_reservation for update;
 if not found then raise exception 'Reservation not found' using errcode='22023'; end if;
 if r.status='consumed' then
  select ledger_entry_id into e from public.mme_inventory_ledger where idempotency_key=p_idempotency_key;
  if e is not null then return e; end if;
  raise exception 'Reservation already consumed with another posting key' using errcode='55000';
 end if;
 if r.status<>'active' or r.expires_at<=now() then raise exception 'Reservation is inactive or expired' using errcode='55000'; end if;
 perform pg_advisory_xact_lock(hashtextextended(r.sku_reference||'|'||r.location_code||'|'||r.currency_code,0));
 select * into b from public.mme_inventory_balances where sku_reference=r.sku_reference and location_code=r.location_code and currency_code=r.currency_code for update;
 if not found or b.on_hand_quantity<r.quantity or b.reserved_quantity<r.quantity then raise exception 'Inventory balance invariant failed' using errcode='23514'; end if;
 v:=round(r.quantity*b.average_unit_cost,2);
 insert into public.mme_inventory_ledger(idempotency_key,sku_reference,location_code,movement_type,quantity_delta,unit_cost,value_delta,currency_code,source_type,source_id,actor_user_id,reason)
 values(p_idempotency_key,r.sku_reference,r.location_code,'sale',-r.quantity,b.average_unit_cost,-v,r.currency_code,'inventory_reservation',r.reservation_id,p_actor,'Consumed reservation for completed sale')
 returning ledger_entry_id into e;
 update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity-r.quantity,reserved_quantity=reserved_quantity-r.quantity,
 inventory_value=greatest(0,inventory_value-v),average_unit_cost=case when on_hand_quantity-r.quantity=0 then 0 else round(greatest(0,inventory_value-v)/(on_hand_quantity-r.quantity),6) end,
 version=version+1,updated_at=now() where balance_id=b.balance_id;
 update public.mme_inventory_reservations set status='consumed',consumed_at=now() where reservation_id=p_reservation;
 insert into public.mme_inventory_reservation_events(reservation_id,event_type,actor_user_id,event_data)
 values(p_reservation,'consumed',p_actor,jsonb_build_object('ledger_entry_id',e,'quantity',r.quantity));
 return e;
end; $$;

create or replace view public.mme_inventory_channel_availability as
select sku_reference,location_code,currency_code,on_hand_quantity,reserved_quantity,
 on_hand_quantity-reserved_quantity as available_quantity,average_unit_cost,version,updated_at
from public.mme_inventory_balances;
revoke all on public.mme_inventory_channel_availability from public,anon,authenticated;
grant select on public.mme_inventory_channel_availability to service_role;

revoke all on function public.mme_inventory_reserve_stock(text,text,text,bigint,text,text,text,text,uuid,timestamptz,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_inventory_release_reservation(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_inventory_expire_reservations(uuid,integer) from public,anon,authenticated;
revoke all on function public.mme_inventory_consume_reservation(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_inventory_reserve_stock(text,text,text,bigint,text,text,text,text,uuid,timestamptz,text,jsonb) to service_role;
grant execute on function public.mme_inventory_release_reservation(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_inventory_expire_reservations(uuid,integer) to service_role;
grant execute on function public.mme_inventory_consume_reservation(uuid,uuid,text) to service_role;
commit;
