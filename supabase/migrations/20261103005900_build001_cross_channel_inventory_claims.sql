-- Build 001: shared temporary inventory claims for non-checkout channels.
-- Existing order reservations remain authoritative for website checkout/payment.
create table public.mme_channel_stock_claims (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('customer_hold','pos_quote','subscription','auction','manual_allocation')),
  source_reference text not null check (length(btrim(source_reference)) between 1 and 160),
  status text not null default 'active' check (status in ('active','released','expired')),
  expires_at timestamptz not null,
  created_by_identity_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_type,source_reference),
  check (expires_at > created_at)
);

create table public.mme_channel_stock_claim_lines (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.mme_channel_stock_claims(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  inventory_balance_id uuid references public.mme_inventory_balances(id) on delete restrict,
  serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),
  check (
    (inventory_balance_id is not null and serialized_unit_id is null)
    or (inventory_balance_id is null and serialized_unit_id is not null and quantity = 1)
  )
);

create unique index mme_channel_claim_aggregate_line_unique
  on public.mme_channel_stock_claim_lines(claim_id,inventory_balance_id)
  where inventory_balance_id is not null;
create unique index mme_channel_claim_serialized_unit_unique
  on public.mme_channel_stock_claim_lines(serialized_unit_id)
  where serialized_unit_id is not null;
create index mme_channel_stock_claim_expiry_idx
  on public.mme_channel_stock_claims(status,expires_at);

alter table public.mme_channel_stock_claims enable row level security;
alter table public.mme_channel_stock_claim_lines enable row level security;
revoke all on public.mme_channel_stock_claims,public.mme_channel_stock_claim_lines from public,anon,authenticated;
grant all on public.mme_channel_stock_claims,public.mme_channel_stock_claim_lines to service_role;

create or replace function public.mme_create_channel_stock_claim(
  p_source_type text,p_source_reference text,p_actor_identity_id uuid,
  p_expires_at timestamptz,p_items jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_claim_id uuid;
  v_item record;
  v_balance public.mme_inventory_balances%rowtype;
  v_unit public.mme_serialized_units%rowtype;
begin
  if p_source_type not in ('customer_hold','pos_quote','subscription','auction','manual_allocation')
     or p_source_reference is null or length(btrim(p_source_reference)) not between 1 and 160
     or p_actor_identity_id is null or p_expires_at is null
     or p_expires_at <= now() or p_expires_at > now()+interval '30 days'
     or p_items is null or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>50 then
    raise exception 'Invalid channel stock claim' using errcode='22023';
  end if;

  if exists (
    select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
    where x.product_id is null or x.location_id is null or x.quantity is null
       or x.quantity<1 or x.quantity>20
  ) then raise exception 'Invalid channel claim line' using errcode='22023'; end if;

  if exists (
    select 1 from jsonb_to_recordset(p_items) as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
    group by x.product_id,x.location_id having count(*)>1
  ) then raise exception 'Duplicate product/location claim lines are not allowed' using errcode='22023'; end if;

  insert into public.mme_channel_stock_claims(source_type,source_reference,created_by_identity_id,expires_at)
  values(p_source_type,btrim(p_source_reference),p_actor_identity_id,p_expires_at)
  returning id into v_claim_id;

  for v_item in
    select * from jsonb_to_recordset(p_items)
      as x(product_id uuid,location_id uuid,quantity integer,serialized_unit_id uuid)
    order by x.product_id,x.location_id
  loop
    if v_item.serialized_unit_id is not null then
      if v_item.quantity<>1 then raise exception 'Serialized claim quantity must equal one' using errcode='22023'; end if;
      select u.* into v_unit
      from public.mme_serialized_units u
      join public.mme_products p on p.id=u.product_id and p.active=true and p.serialized=true
      join public.mme_store_locations l on l.id=u.location_id and l.active=true
      where u.id=v_item.serialized_unit_id and u.product_id=v_item.product_id
        and u.location_id=v_item.location_id and u.unit_status='in_stock'
      for update of u,p;
      if not found then raise exception 'Serialized unit unavailable at requested location' using errcode='P0001'; end if;
      update public.mme_serialized_units set unit_status='reserved',updated_at=now()
      where id=v_unit.id and unit_status='in_stock';
      if not found then raise exception 'Serialized unit was claimed concurrently' using errcode='P0001'; end if;
      insert into public.mme_channel_stock_claim_lines(claim_id,product_id,location_id,serialized_unit_id,quantity)
      values(v_claim_id,v_item.product_id,v_item.location_id,v_unit.id,1);
    else
      select b.* into v_balance
      from public.mme_inventory_balances b
      join public.mme_products p on p.id=b.product_id and p.active=true and p.serialized=false
      join public.mme_store_locations l on l.id=b.location_id and l.active=true
      where b.product_id=v_item.product_id and b.location_id=v_item.location_id
      for update of b,p;
      if not found or v_balance.on_hand_quantity-v_balance.reserved_quantity<v_item.quantity then
        raise exception 'Insufficient available stock for channel claim' using errcode='P0001';
      end if;
      update public.mme_inventory_balances
      set reserved_quantity=reserved_quantity+v_item.quantity,updated_at=now()
      where id=v_balance.id;
      insert into public.mme_channel_stock_claim_lines(claim_id,product_id,location_id,inventory_balance_id,quantity)
      values(v_claim_id,v_item.product_id,v_item.location_id,v_balance.id,v_item.quantity);
    end if;
  end loop;
  return v_claim_id;
end; $$;

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
    where claim_id=p_claim_id order by inventory_balance_id nulls last,serialized_unit_id nulls last
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
  update public.mme_channel_stock_claims
  set status=case when expires_at<=now() then 'expired' else 'released' end,updated_at=now()
  where id=p_claim_id and status='active';
  return true;
end; $$;

create or replace function public.mme_expire_channel_stock_claims(p_limit integer default 100)
returns integer language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_count integer:=0;
begin
  if p_limit is null or p_limit not between 1 and 1000 then
    raise exception 'Expiry batch limit must be between 1 and 1000' using errcode='22023';
  end if;
  for v_id in
    select id from public.mme_channel_stock_claims
    where status='active' and expires_at<=now()
    order by expires_at,id for update skip locked limit p_limit
  loop
    if public.mme_release_channel_stock_claim(v_id) then v_count:=v_count+1; end if;
  end loop;
  return v_count;
end; $$;

create or replace view public.mme_inventory_available_to_sell_v
with (security_invoker=true) as
select p.id as product_id,p.sku,p.title,p.condition_grade,p.serialized,b.location_id,
  b.on_hand_quantity,b.reserved_quantity,
  (b.on_hand_quantity-b.reserved_quantity)::integer as available_to_sell_quantity,
  now() as calculated_at
from public.mme_products p
join public.mme_inventory_balances b on b.product_id=p.id
where p.active=true and p.serialized=false
union all
select p.id,p.sku,p.title,p.condition_grade,p.serialized,u.location_id,
  1::integer,case when u.unit_status='reserved' then 1 else 0 end,
  case when u.unit_status='in_stock' then 1 else 0 end,now()
from public.mme_serialized_units u
join public.mme_products p on p.id=u.product_id
where p.active=true and p.serialized=true and u.unit_status in ('in_stock','reserved');

revoke all on public.mme_inventory_available_to_sell_v from public,anon,authenticated;
grant select on public.mme_inventory_available_to_sell_v to service_role;
revoke all on function public.mme_create_channel_stock_claim(text,text,uuid,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function public.mme_release_channel_stock_claim(uuid) from public,anon,authenticated;
revoke all on function public.mme_expire_channel_stock_claims(integer) from public,anon,authenticated;
grant execute on function public.mme_create_channel_stock_claim(text,text,uuid,timestamptz,jsonb) to service_role;
grant execute on function public.mme_release_channel_stock_claim(uuid) to service_role;
grant execute on function public.mme_expire_channel_stock_claims(integer) to service_role;

comment on view public.mme_inventory_available_to_sell_v is
  'Current available-to-sell quantity across aggregate balances and serialized units. Website order reservations and active channel claims reduce availability.';
comment on table public.mme_channel_stock_claims is
  'Temporary inventory holds for POS quotes, customer holds, subscriptions, auctions and authorized manual allocations. No payment or sale is implied.';
