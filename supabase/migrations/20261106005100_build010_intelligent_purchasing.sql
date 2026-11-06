begin;
create table if not exists public.mme_procurement_price_observations(
 observation_id uuid primary key default gen_random_uuid(),
 offer_id uuid not null references public.mme_vendor_catalog_offers(offer_id) on delete restrict,
 observed_unit_cost numeric(16,4) not null check(observed_unit_cost>=0),
 currency_code char(3) not null default 'USD',
 observed_at timestamptz not null default now(),
 source_reference text,
 recorded_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_procurement_price_observation_history_idx on public.mme_procurement_price_observations(offer_id,observed_at desc);
create table if not exists public.mme_procurement_landed_cost_scenarios(
 scenario_id uuid primary key default gen_random_uuid(),
 offer_id uuid not null references public.mme_vendor_catalog_offers(offer_id) on delete restrict,
 order_quantity numeric(14,3) not null check(order_quantity>0),
 currency_code char(3) not null default 'USD',
 unit_cost numeric(16,4) not null check(unit_cost>=0),
 shipping_total numeric(16,2) not null default 0 check(shipping_total>=0),
 duties_total numeric(16,2) not null default 0 check(duties_total>=0),
 tax_total numeric(16,2) not null default 0 check(tax_total>=0),
 fees_total numeric(16,2) not null default 0 check(fees_total>=0),
 discount_total numeric(16,2) not null default 0 check(discount_total>=0),
 notes text,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 check(discount_total<=order_quantity*unit_cost+shipping_total+duties_total+tax_total+fees_total)
);
create index if not exists mme_procurement_landed_cost_offer_idx on public.mme_procurement_landed_cost_scenarios(offer_id,created_at desc);
alter table public.mme_procurement_price_observations enable row level security;
alter table public.mme_procurement_landed_cost_scenarios enable row level security;
revoke all on public.mme_procurement_price_observations from public,anon,authenticated;
revoke all on public.mme_procurement_landed_cost_scenarios from public,anon,authenticated;
grant all on public.mme_procurement_price_observations to service_role;
grant all on public.mme_procurement_landed_cost_scenarios to service_role;
commit;