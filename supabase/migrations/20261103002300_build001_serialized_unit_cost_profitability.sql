-- Build 001: per-device landed cost and realized sale profitability ledger.
-- The trusted order/payment service calls sale recording only after confirmed settlement.

create table public.mme_serialized_unit_costs (
 id uuid primary key default gen_random_uuid(),
 unit_id uuid not null unique references public.mme_serialized_units(id) on delete restrict,
 acquisition_cost_cents bigint not null check(acquisition_cost_cents>=0),
 freight_cost_cents bigint not null default 0 check(freight_cost_cents>=0),
 auction_fee_cents bigint not null default 0 check(auction_fee_cents>=0),
 handling_cost_cents bigint not null default 0 check(handling_cost_cents>=0),
 other_cost_cents bigint not null default 0 check(other_cost_cents>=0),
 landed_cost_cents bigint generated always as
  (acquisition_cost_cents+freight_cost_cents+auction_fee_cents+handling_cost_cents+other_cost_cents) stored,
 currency_code text not null default 'USD' check(currency_code='USD'),
 source_reference text,
 approved_by_identity_id uuid,
 created_by_identity_id uuid not null,
 created_at timestamptz not null default now()
);

create table public.mme_serialized_unit_sale_outcomes (
 id uuid primary key default gen_random_uuid(),
 unit_id uuid not null unique references public.mme_serialized_units(id) on delete restrict,
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 sale_price_cents bigint not null check(sale_price_cents>=0),
 discount_cents bigint not null default 0 check(discount_cents>=0),
 refund_cents bigint not null default 0 check(refund_cents>=0),
 payment_fee_cents bigint not null default 0 check(payment_fee_cents>=0),
 other_direct_cost_cents bigint not null default 0 check(other_direct_cost_cents>=0),
 net_revenue_cents bigint generated always as (sale_price_cents-discount_cents-refund_cents) stored,
 realized_gross_profit_cents bigint,
 sold_at timestamptz not null,
 recorded_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 check(discount_cents+refund_cents<=sale_price_cents)
);

create index mme_serialized_unit_costs_created_idx on public.mme_serialized_unit_costs(created_at desc);
create index mme_serialized_unit_sales_sold_idx on public.mme_serialized_unit_sale_outcomes(sold_at desc);

alter table public.mme_serialized_unit_costs enable row level security;
alter table public.mme_serialized_unit_sale_outcomes enable row level security;
revoke all on public.mme_serialized_unit_costs,public.mme_serialized_unit_sale_outcomes from public,anon,authenticated;
grant all on public.mme_serialized_unit_costs,public.mme_serialized_unit_sale_outcomes to service_role;

create or replace function public.mme_record_serialized_unit_landed_cost(
 p_unit_id uuid,p_acquisition_cost_cents bigint,p_freight_cost_cents bigint,
 p_auction_fee_cents bigint,p_handling_cost_cents bigint,p_other_cost_cents bigint,
 p_source_reference text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if p_unit_id is null or p_acquisition_cost_cents is null or p_acquisition_cost_cents<0
  or p_freight_cost_cents is null or p_freight_cost_cents<0
  or p_auction_fee_cents is null or p_auction_fee_cents<0
  or p_handling_cost_cents is null or p_handling_cost_cents<0
  or p_other_cost_cents is null or p_other_cost_cents<0
  or p_actor_identity_id is null or p_source_reference is not null and length(p_source_reference)>160 then
  raise exception 'Invalid serialized unit cost' using errcode='22023';
 end if;
 perform 1 from public.mme_serialized_units where id=p_unit_id for update;
 if not found then raise exception 'Serialized unit not found' using errcode='P0002'; end if;
 insert into public.mme_serialized_unit_costs(unit_id,acquisition_cost_cents,freight_cost_cents,
  auction_fee_cents,handling_cost_cents,other_cost_cents,source_reference,created_by_identity_id,approved_by_identity_id)
 values(p_unit_id,p_acquisition_cost_cents,p_freight_cost_cents,p_auction_fee_cents,
  p_handling_cost_cents,p_other_cost_cents,p_source_reference,p_actor_identity_id,p_approved_by_identity_id)
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_record_serialized_unit_sale_outcome(
 p_unit_id uuid,p_order_id uuid,p_sale_price_cents bigint,p_discount_cents bigint,
 p_refund_cents bigint,p_payment_fee_cents bigint,p_other_direct_cost_cents bigint,
 p_sold_at timestamptz,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_cost bigint; v_id uuid;
begin
 if p_unit_id is null or p_order_id is null or p_sale_price_cents is null or p_sale_price_cents<0
  or p_discount_cents is null or p_discount_cents<0 or p_refund_cents is null or p_refund_cents<0
  or p_payment_fee_cents is null or p_payment_fee_cents<0
  or p_other_direct_cost_cents is null or p_other_direct_cost_cents<0
  or p_discount_cents+p_refund_cents>p_sale_price_cents
  or p_sold_at is null or p_actor_identity_id is null then
  raise exception 'Invalid serialized sale outcome' using errcode='22023';
 end if;
 select c.landed_cost_cents into v_cost
 from public.mme_serialized_units u
 join public.mme_serialized_unit_costs c on c.unit_id=u.id
 where u.id=p_unit_id and u.unit_status='sold' and u.sold_at is not null
 for update of u;
 if not found then raise exception 'Sold unit with landed cost required' using errcode='P0002'; end if;
 if not exists(select 1 from public.mme_orders where id=p_order_id) then
  raise exception 'Order not found' using errcode='P0002'; end if;
 insert into public.mme_serialized_unit_sale_outcomes(
  unit_id,order_id,sale_price_cents,discount_cents,refund_cents,payment_fee_cents,
  other_direct_cost_cents,realized_gross_profit_cents,sold_at,recorded_by_identity_id
 ) values(p_unit_id,p_order_id,p_sale_price_cents,p_discount_cents,p_refund_cents,
  p_payment_fee_cents,p_other_direct_cost_cents,
  p_sale_price_cents-p_discount_cents-p_refund_cents-v_cost,
  p_sold_at,p_actor_identity_id) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_get_serialized_unit_profitability(
 p_location_id uuid default null,p_limit integer default 100,p_offset integer default 0
) returns table(
 unit_id uuid,product_id uuid,sku text,product_title text,serial_number text,
 imei_last_four text,condition_grade text,unit_status text,landed_cost_cents bigint,
 sale_price_cents bigint,discount_cents bigint,refund_cents bigint,net_revenue_cents bigint,
 realized_gross_profit_cents bigint,margin_percent numeric,sold_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_limit is null or p_limit<1 or p_limit>500 or p_offset is null or p_offset<0 then
  raise exception 'Invalid serialized profitability query' using errcode='22023'; end if;
 return query
 select u.id,p.id,p.sku,p.title,u.serial_number,
  case when u.imei is null then null else right(u.imei,4) end,
  u.condition_grade,u.unit_status,c.landed_cost_cents,
  s.sale_price_cents,s.discount_cents,s.refund_cents,s.net_revenue_cents,
  s.realized_gross_profit_cents,
  case when s.net_revenue_cents=0 then null else round(100.0*s.realized_gross_profit_cents/s.net_revenue_cents,2) end,
  s.sold_at
 from public.mme_serialized_units u
 join public.mme_products p on p.id=u.product_id
 join public.mme_serialized_unit_costs c on c.unit_id=u.id
 left join public.mme_serialized_unit_sale_outcomes s on s.unit_id=u.id
 where p_location_id is null or u.location_id=p_location_id
 order by s.sold_at desc nulls last,u.received_at desc
 limit p_limit offset p_offset;
end; $$;

revoke all on function public.mme_record_serialized_unit_landed_cost(uuid,bigint,bigint,bigint,bigint,bigint,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_record_serialized_unit_sale_outcome(uuid,uuid,bigint,bigint,bigint,bigint,bigint,timestamptz,uuid) from public,anon,authenticated;
revoke all on function public.mme_get_serialized_unit_profitability(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.mme_record_serialized_unit_landed_cost(uuid,bigint,bigint,bigint,bigint,bigint,text,uuid,uuid) to service_role;
grant execute on function public.mme_record_serialized_unit_sale_outcome(uuid,uuid,bigint,bigint,bigint,bigint,bigint,timestamptz,uuid) to service_role;
grant execute on function public.mme_get_serialized_unit_profitability(uuid,integer,integer) to service_role;

comment on table public.mme_serialized_unit_costs is
 'One-time per-device landed-cost basis, including allocated freight, auction and handling components.';
comment on table public.mme_serialized_unit_sale_outcomes is
 'One sale outcome per serialized device; realized gross profit subtracts landed cost, discounts and refunds, before payment fees and other direct costs.';
