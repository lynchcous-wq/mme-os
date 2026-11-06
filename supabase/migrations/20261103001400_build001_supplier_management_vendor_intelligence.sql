-- Build 001: supplier directory, vendor catalog, quote history and delivery scorecards.
-- Supplier records support purchasing intelligence; no supplier order is transmitted.

create table public.mme_suppliers (
  id uuid primary key default gen_random_uuid(),
  supplier_code text not null unique,
  legal_name text not null,
  display_name text not null,
  status text not null default 'active' check (status in ('active','on_hold','inactive')),
  website_url text,
  contact_name text,
  contact_email text,
  contact_phone text,
  payment_terms text,
  default_lead_time_days integer check (default_lead_time_days between 0 and 365),
  notes text,
  created_by_identity_id uuid not null,
  updated_by_identity_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(legal_name)) between 2 and 200),
  check (length(btrim(display_name)) between 2 and 120)
);

create table public.mme_supplier_products (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.mme_suppliers(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  supplier_sku text,
  last_quoted_unit_cost_cents bigint check (last_quoted_unit_cost_cents>=0),
  last_quoted_at timestamptz,
  currency text not null default 'USD' check (currency='USD'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(supplier_id,product_id)
);

create table public.mme_supplier_price_history (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.mme_suppliers(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  supplier_sku text,
  unit_cost_cents bigint not null check (unit_cost_cents>=0),
  currency text not null default 'USD' check (currency='USD'),
  minimum_order_quantity integer not null default 1 check (minimum_order_quantity>0),
  quoted_lead_time_days integer check (quoted_lead_time_days between 0 and 365),
  quote_reference text,
  valid_until timestamptz,
  recorded_by_identity_id uuid not null,
  recorded_at timestamptz not null default now(),
  source_type text not null default 'manual' check (source_type in ('manual','supplier_document','email','api','auction')),
  notes text
);

create table public.mme_supplier_deliveries (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.mme_suppliers(id) on delete restrict,
  proposal_id uuid references public.mme_purchase_proposals(id) on delete restrict,
  supplier_order_reference text,
  expected_at timestamptz,
  received_at timestamptz,
  units_expected integer not null default 0 check (units_expected>=0),
  units_received integer not null default 0 check (units_received>=0),
  units_damaged integer not null default 0 check (units_damaged>=0 and units_damaged<=units_received),
  delivery_status text not null default 'expected' check (delivery_status in ('expected','partial','received','delayed','cancelled','disputed')),
  quality_notes text,
  recorded_by_identity_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (units_received<=units_expected or units_expected=0),
  check (received_at is null or received_at>=created_at)
);

create index mme_supplier_products_product_idx on public.mme_supplier_products(product_id,active);
create index mme_supplier_price_history_lookup_idx on public.mme_supplier_price_history(supplier_id,product_id,recorded_at desc);
create index mme_supplier_deliveries_supplier_idx on public.mme_supplier_deliveries(supplier_id,created_at desc);
create index mme_supplier_deliveries_status_idx on public.mme_supplier_deliveries(delivery_status,expected_at);

alter table public.mme_suppliers enable row level security;
alter table public.mme_supplier_products enable row level security;
alter table public.mme_supplier_price_history enable row level security;
alter table public.mme_supplier_deliveries enable row level security;
revoke all on public.mme_suppliers from anon,authenticated;
revoke all on public.mme_supplier_products from anon,authenticated;
revoke all on public.mme_supplier_price_history from anon,authenticated;
revoke all on public.mme_supplier_deliveries from anon,authenticated;
grant all on public.mme_suppliers to service_role;
grant all on public.mme_supplier_products to service_role;
grant all on public.mme_supplier_price_history to service_role;
grant all on public.mme_supplier_deliveries to service_role;

create or replace function public.mme_upsert_supplier(
 p_supplier_code text,p_legal_name text,p_display_name text,p_website_url text,
 p_contact_name text,p_contact_email text,p_contact_phone text,p_payment_terms text,
 p_default_lead_time_days integer,p_notes text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if p_supplier_code is null or length(btrim(p_supplier_code)) not between 2 and 40
 or p_legal_name is null or length(btrim(p_legal_name)) not between 2 and 200
 or p_display_name is null or length(btrim(p_display_name)) not between 2 and 120
 or p_actor_identity_id is null
 or p_default_lead_time_days is not null and p_default_lead_time_days not between 0 and 365
 or p_website_url is not null and p_website_url !~ '^https://'
 or p_contact_email is not null and p_contact_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
  raise exception 'Invalid supplier profile' using errcode='22023';
 end if;
 insert into public.mme_suppliers(supplier_code,legal_name,display_name,website_url,contact_name,
  contact_email,contact_phone,payment_terms,default_lead_time_days,notes,created_by_identity_id,updated_by_identity_id)
 values(upper(btrim(p_supplier_code)),btrim(p_legal_name),btrim(p_display_name),p_website_url,
  p_contact_name,p_contact_email,p_contact_phone,p_payment_terms,p_default_lead_time_days,p_notes,p_actor_identity_id,p_actor_identity_id)
 on conflict(supplier_code) do update set legal_name=excluded.legal_name,display_name=excluded.display_name,
  website_url=excluded.website_url,contact_name=excluded.contact_name,contact_email=excluded.contact_email,
  contact_phone=excluded.contact_phone,payment_terms=excluded.payment_terms,
  default_lead_time_days=excluded.default_lead_time_days,notes=excluded.notes,
  updated_by_identity_id=excluded.updated_by_identity_id,updated_at=now()
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_record_supplier_quote(
 p_supplier_id uuid,p_product_id uuid,p_supplier_sku text,p_unit_cost_cents bigint,
 p_minimum_order_quantity integer,p_lead_time_days integer,p_quote_reference text,
 p_valid_until timestamptz,p_source_type text,p_notes text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if p_supplier_id is null or p_product_id is null or p_unit_cost_cents is null or p_unit_cost_cents<0
 or p_minimum_order_quantity is null or p_minimum_order_quantity<1
 or p_lead_time_days is not null and p_lead_time_days not between 0 and 365
 or p_source_type not in ('manual','supplier_document','email','api','auction')
 or p_actor_identity_id is null then
  raise exception 'Invalid supplier quote' using errcode='22023';
 end if;
 perform 1 from public.mme_suppliers where id=p_supplier_id and status='active' for update;
 if not found then raise exception 'Active supplier not found' using errcode='P0002'; end if;
 perform 1 from public.mme_products where id=p_product_id and active=true;
 if not found then raise exception 'Active product not found' using errcode='P0002'; end if;
 insert into public.mme_supplier_products(supplier_id,product_id,supplier_sku,last_quoted_unit_cost_cents,last_quoted_at)
 values(p_supplier_id,p_product_id,p_supplier_sku,p_unit_cost_cents,now())
 on conflict(supplier_id,product_id) do update set supplier_sku=excluded.supplier_sku,
  last_quoted_unit_cost_cents=excluded.last_quoted_unit_cost_cents,last_quoted_at=now(),active=true,updated_at=now();
 insert into public.mme_supplier_price_history(supplier_id,product_id,supplier_sku,unit_cost_cents,
  minimum_order_quantity,quoted_lead_time_days,quote_reference,valid_until,recorded_by_identity_id,source_type,notes)
 values(p_supplier_id,p_product_id,p_supplier_sku,p_unit_cost_cents,p_minimum_order_quantity,
  p_lead_time_days,p_quote_reference,p_valid_until,p_actor_identity_id,p_source_type,p_notes)
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_record_supplier_delivery(
 p_supplier_id uuid,p_proposal_id uuid,p_supplier_order_reference text,
 p_expected_at timestamptz,p_received_at timestamptz,p_units_expected integer,
 p_units_received integer,p_units_damaged integer,p_delivery_status text,
 p_quality_notes text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if p_supplier_id is null or p_actor_identity_id is null
 or p_units_expected is null or p_units_expected<0
 or p_units_received is null or p_units_received<0
 or p_units_damaged is null or p_units_damaged<0 or p_units_damaged>p_units_received
 or (p_units_expected>0 and p_units_received>p_units_expected)
 or p_delivery_status not in ('expected','partial','received','delayed','cancelled','disputed')
 or p_received_at is not null and p_received_at>now()+interval '1 day' then
  raise exception 'Invalid supplier delivery' using errcode='22023';
 end if;
 perform 1 from public.mme_suppliers where id=p_supplier_id for update;
 if not found then raise exception 'Supplier not found' using errcode='P0002'; end if;
 if p_proposal_id is not null and not exists(select 1 from public.mme_purchase_proposals where id=p_proposal_id) then
  raise exception 'Purchase proposal not found' using errcode='P0002';
 end if;
 insert into public.mme_supplier_deliveries(supplier_id,proposal_id,supplier_order_reference,
  expected_at,received_at,units_expected,units_received,units_damaged,delivery_status,quality_notes,recorded_by_identity_id)
 values(p_supplier_id,p_proposal_id,p_supplier_order_reference,p_expected_at,p_received_at,
  p_units_expected,p_units_received,p_units_damaged,p_delivery_status,p_quality_notes,p_actor_identity_id)
 returning id into v_id;
 return v_id;
end; $$;

create or replace view public.mme_supplier_scorecard_v
with (security_invoker=true) as
select s.id as supplier_id,s.supplier_code,s.display_name,s.status,
 count(d.id)::integer as delivery_count,
 count(d.id) filter(where d.delivery_status='received')::integer as completed_deliveries,
 coalesce(sum(d.units_expected),0)::bigint as units_expected,
 coalesce(sum(d.units_received),0)::bigint as units_received,
 coalesce(sum(d.units_damaged),0)::bigint as units_damaged,
 round(100.0*sum(d.units_received) filter(where d.delivery_status='received')
   /nullif(sum(d.units_expected) filter(where d.delivery_status='received'),0),2) as completion_rate_percent,
 round(100.0*(sum(d.units_received)-sum(d.units_damaged))
   /nullif(sum(d.units_received),0),2) as non_damaged_rate_percent,
 round(avg(extract(epoch from (d.received_at-d.expected_at))/86400.0)
   filter(where d.received_at is not null and d.expected_at is not null),2) as avg_days_vs_expected,
 count(d.id) filter(where d.delivery_status in ('delayed','disputed'))::integer as delayed_or_disputed_count
from public.mme_suppliers s left join public.mme_supplier_deliveries d on d.supplier_id=s.id
group by s.id,s.supplier_code,s.display_name,s.status;

revoke all on view public.mme_supplier_scorecard_v from public,anon,authenticated;
grant select on public.mme_supplier_scorecard_v to service_role;

revoke all on function public.mme_upsert_supplier(text,text,text,text,text,text,text,text,integer,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_record_supplier_quote(uuid,uuid,text,bigint,integer,integer,text,timestamptz,text,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_record_supplier_delivery(uuid,uuid,text,timestamptz,timestamptz,integer,integer,integer,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_upsert_supplier(text,text,text,text,text,text,text,text,integer,text,uuid) to service_role;
grant execute on function public.mme_record_supplier_quote(uuid,uuid,text,bigint,integer,integer,text,timestamptz,text,text,uuid) to service_role;
grant execute on function public.mme_record_supplier_delivery(uuid,uuid,text,timestamptz,timestamptz,integer,integer,integer,text,text,uuid) to service_role;

comment on table public.mme_suppliers is 'Supplier directory and commercial terms; private to trusted MME services.';
comment on table public.mme_supplier_price_history is 'Append-only supplier quote history for product cost comparisons.';
comment on view public.mme_supplier_scorecard_v is 'Delivery completion, non-damaged rate, and schedule variance metrics; not a credit rating.';
