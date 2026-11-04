-- Build 001: warehouse bin locations, bin-level stock balances and auditable putaway/pick/move operations.
-- Aggregate on-hand remains authoritative in mme_inventory_balances; bin totals may never exceed it.
create table public.mme_warehouse_bins (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 bin_code text not null, zone_code text, aisle_code text, rack_code text, shelf_code text,
 bin_type text not null default 'storage' check(bin_type in ('storage','receiving','inspection','quarantine','packing','staging','returns')),
 active boolean not null default true, capacity_units integer check(capacity_units is null or capacity_units>0),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(location_id,bin_code), unique(id,location_id)
);
create table public.mme_warehouse_bin_balances (
 id uuid primary key default gen_random_uuid(),
 bin_id uuid not null references public.mme_warehouse_bins(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 quantity integer not null default 0 check(quantity>=0),
 updated_at timestamptz not null default now(), unique(bin_id,product_id)
);
create index mme_warehouse_bin_balances_product_idx on public.mme_warehouse_bin_balances(product_id,bin_id);
create table public.mme_warehouse_bin_movements (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.mme_products(id) on delete restrict,
 from_bin_id uuid references public.mme_warehouse_bins(id) on delete restrict,
 to_bin_id uuid references public.mme_warehouse_bins(id) on delete restrict,
 quantity integer not null check(quantity>0),
 movement_type text not null check(movement_type in ('putaway','pick','bin_transfer','cycle_count_increase','cycle_count_decrease','quarantine_move','inspection_move')),
 reference_text text, reason text not null check(length(btrim(reason)) between 3 and 500),
 actor_identity_id uuid not null, approved_by_identity_id uuid,
 created_at timestamptz not null default now(),
 check(from_bin_id is distinct from to_bin_id)
);
create index mme_warehouse_bin_movements_product_idx on public.mme_warehouse_bin_movements(product_id,created_at desc);
create index mme_warehouse_bin_movements_bins_idx on public.mme_warehouse_bin_movements(from_bin_id,to_bin_id,created_at desc);
alter table public.mme_warehouse_bins enable row level security;
alter table public.mme_warehouse_bin_balances enable row level security;
alter table public.mme_warehouse_bin_movements enable row level security;
revoke all on public.mme_warehouse_bins,public.mme_warehouse_bin_balances,public.mme_warehouse_bin_movements from public,anon,authenticated;
grant all on public.mme_warehouse_bins,public.mme_warehouse_bin_balances,public.mme_warehouse_bin_movements to service_role;

create or replace function public.mme_putaway_inventory(p_product_id uuid,p_bin_id uuid,p_quantity integer,p_reason text,p_actor_identity_id uuid,p_reference_text text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_bin public.mme_warehouse_bins%rowtype; v_product public.mme_products%rowtype; v_balance public.mme_inventory_balances%rowtype; v_bin_qty integer; v_id uuid;
begin
 if p_product_id is null or p_bin_id is null or p_quantity is null or p_quantity<1 or p_reason is null or length(btrim(p_reason))<3 or p_actor_identity_id is null then raise exception 'Invalid putaway request' using errcode='22023'; end if;
 select * into v_bin from public.mme_warehouse_bins where id=p_bin_id and active=true for update;
 if not found then raise exception 'Active warehouse bin not found' using errcode='P0002'; end if;
 select * into v_product from public.mme_products where id=p_product_id and active=true and serialized=false for update;
 if not found then raise exception 'Active aggregate product not found' using errcode='P0002'; end if;
 select * into v_balance from public.mme_inventory_balances where product_id=p_product_id and location_id=v_bin.location_id for update;
 if not found then raise exception 'No location inventory balance exists for putaway' using errcode='23514'; end if;
 insert into public.mme_warehouse_bin_balances(bin_id,product_id,quantity) values(p_bin_id,p_product_id,0) on conflict(bin_id,product_id) do nothing;
 select quantity into v_bin_qty from public.mme_warehouse_bin_balances where bin_id=p_bin_id and product_id=p_product_id for update;
 if coalesce((select sum(quantity) from public.mme_warehouse_bin_balances bb join public.mme_warehouse_bins b on b.id=bb.bin_id where b.location_id=v_bin.location_id and bb.product_id=p_product_id),0)+p_quantity>v_balance.on_hand_quantity then raise exception 'Putaway exceeds unallocated location stock' using errcode='23514'; end if;
 if v_bin.capacity_units is not null and coalesce((select sum(quantity) from public.mme_warehouse_bin_balances where bin_id=p_bin_id),0)+p_quantity>v_bin.capacity_units then raise exception 'Warehouse bin capacity exceeded' using errcode='23514'; end if;
 update public.mme_warehouse_bin_balances set quantity=quantity+p_quantity,updated_at=now() where bin_id=p_bin_id and product_id=p_product_id;
 insert into public.mme_warehouse_bin_movements(product_id,to_bin_id,quantity,movement_type,reference_text,reason,actor_identity_id) values(p_product_id,p_bin_id,p_quantity,'putaway',left(p_reference_text,180),btrim(p_reason),p_actor_identity_id) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_move_warehouse_bin_stock(p_product_id uuid,p_from_bin_id uuid,p_to_bin_id uuid,p_quantity integer,p_reason text,p_actor_identity_id uuid,p_reference_text text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_from public.mme_warehouse_bins%rowtype; v_to public.mme_warehouse_bins%rowtype; v_from_qty integer; v_to_qty integer; v_id uuid;
begin
 if p_product_id is null or p_from_bin_id is null or p_to_bin_id is null or p_from_bin_id=p_to_bin_id or p_quantity is null or p_quantity<1 or p_reason is null or length(btrim(p_reason))<3 or p_actor_identity_id is null then raise exception 'Invalid bin transfer' using errcode='22023'; end if;
 perform 1 from public.mme_products where id=p_product_id and active=true and serialized=false for update;
 if not found then raise exception 'Active aggregate product not found' using errcode='P0002'; end if;
 perform 1 from public.mme_warehouse_bins where id in (p_from_bin_id,p_to_bin_id) and active=true order by id for update;
 select * into v_from from public.mme_warehouse_bins where id=p_from_bin_id and active=true;
 select * into v_to from public.mme_warehouse_bins where id=p_to_bin_id and active=true;
 if v_from.id is null or v_to.id is null or v_from.location_id<>v_to.location_id then raise exception 'Both active bins must belong to the same store location' using errcode='23514'; end if;
 insert into public.mme_warehouse_bin_balances(bin_id,product_id,quantity) values(p_from_bin_id,p_product_id,0),(p_to_bin_id,p_product_id,0) on conflict(bin_id,product_id) do nothing;
 perform 1 from public.mme_warehouse_bin_balances where product_id=p_product_id and bin_id in (p_from_bin_id,p_to_bin_id) order by bin_id for update;
 select quantity into v_from_qty from public.mme_warehouse_bin_balances where bin_id=p_from_bin_id and product_id=p_product_id;
 select quantity into v_to_qty from public.mme_warehouse_bin_balances where bin_id=p_to_bin_id and product_id=p_product_id;
 if v_from_qty<p_quantity then raise exception 'Insufficient quantity in source bin' using errcode='P0001'; end if;
 if v_to.capacity_units is not null and (select coalesce(sum(quantity),0) from public.mme_warehouse_bin_balances where bin_id=p_to_bin_id)+p_quantity>v_to.capacity_units then raise exception 'Destination bin capacity exceeded' using errcode='23514'; end if;
 update public.mme_warehouse_bin_balances set quantity=quantity-p_quantity,updated_at=now() where bin_id=p_from_bin_id and product_id=p_product_id;
 update public.mme_warehouse_bin_balances set quantity=quantity+p_quantity,updated_at=now() where bin_id=p_to_bin_id and product_id=p_product_id;
 insert into public.mme_warehouse_bin_movements(product_id,from_bin_id,to_bin_id,quantity,movement_type,reference_text,reason,actor_identity_id) values(p_product_id,p_from_bin_id,p_to_bin_id,p_quantity,'bin_transfer',left(p_reference_text,180),btrim(p_reason),p_actor_identity_id) returning id into v_id;
 return v_id;
end; $$;

revoke all on function public.mme_putaway_inventory(uuid,uuid,integer,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_move_warehouse_bin_stock(uuid,uuid,uuid,integer,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_putaway_inventory(uuid,uuid,integer,text,uuid,text) to service_role;
grant execute on function public.mme_move_warehouse_bin_stock(uuid,uuid,uuid,integer,text,uuid,text) to service_role;
comment on table public.mme_warehouse_bins is 'Location-scoped aisle/rack/shelf/bin directory with operational zones and capacity.';
comment on table public.mme_warehouse_bin_balances is 'Bin-level aggregate stock allocation; location on-hand ledger remains authoritative.';
comment on table public.mme_warehouse_bin_movements is 'Auditable putaway, pick and within-location bin movement ledger.';