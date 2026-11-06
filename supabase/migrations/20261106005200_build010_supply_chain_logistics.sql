begin;
create table if not exists public.mme_logistics_shipments(
 shipment_id uuid primary key default gen_random_uuid(),
 shipment_number text not null unique,
 shipment_direction text not null check(shipment_direction in('inbound','outbound','inter_store','return')),
 source_type text not null check(source_type in('purchase_order','inventory_transfer','customer_order','vendor_return','manual')),
 source_id uuid,
 vendor_id uuid references public.mme_financial_vendors(vendor_id) on delete restrict,
 carrier_name text not null,
 service_level text,
 tracking_number text,
 tracking_url text,
 origin_location_id uuid,
 destination_location_id uuid,
 origin_text text,
 destination_text text,
 shipment_status text not null default 'planned' check(shipment_status in('planned','label_created','picked_up','in_transit','out_for_delivery','delivered','delivery_exception','lost','damaged','returned','cancelled')),
 shipped_at timestamptz,
 estimated_delivery_at timestamptz,
 delivered_at timestamptz,
 declared_value numeric(16,2) check(declared_value is null or declared_value>=0),
 currency_code char(3) not null default 'USD',
 package_count integer not null default 1 check(package_count>0),
 weight_value numeric(12,3) check(weight_value is null or weight_value>0),
 weight_unit text check(weight_unit is null or weight_unit in('lb','kg','oz','g')),
 notes text,
 created_by_auth_user_id uuid not null,
 updated_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((shipment_direction='inbound' and source_type in('purchase_order','vendor_return','manual')) or (shipment_direction='outbound' and source_type in('customer_order','manual')) or (shipment_direction='inter_store' and source_type in('inventory_transfer','manual')) or (shipment_direction='return' and source_type in('vendor_return','customer_order','manual')))
);
create index if not exists mme_logistics_shipments_status_idx on public.mme_logistics_shipments(shipment_status,estimated_delivery_at);
create index if not exists mme_logistics_shipments_tracking_idx on public.mme_logistics_shipments(carrier_name,tracking_number) where tracking_number is not null;
create index if not exists mme_logistics_shipments_source_idx on public.mme_logistics_shipments(source_type,source_id) where source_id is not null;
create table if not exists public.mme_logistics_shipment_events(
 event_id uuid primary key default gen_random_uuid(),
 shipment_id uuid not null references public.mme_logistics_shipments(shipment_id) on delete restrict,
 event_type text not null check(event_type in('created','label_created','picked_up','in_transit','out_for_delivery','delivered','delivery_exception','lost','damaged','returned','cancelled','note','carrier_scan')),
 event_at timestamptz not null default now(),
 location_text text,
 description text not null,
 carrier_event_code text,
 source_reference text,
 recorded_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_logistics_shipment_events_history_idx on public.mme_logistics_shipment_events(shipment_id,event_at desc);
create table if not exists public.mme_logistics_delivery_claims(
 claim_id uuid primary key default gen_random_uuid(),
 shipment_id uuid not null references public.mme_logistics_shipments(shipment_id) on delete restrict,
 claim_type text not null check(claim_type in('lost','damaged','shortage','late','other')),
 claim_status text not null default 'open' check(claim_status in('open','investigating','submitted_to_carrier','approved','denied','resolved','closed')),
 claim_reference text,
 claimed_amount numeric(16,2) check(claimed_amount is null or claimed_amount>=0),
 currency_code char(3) not null default 'USD',
 description text not null,
 resolution_notes text,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists mme_logistics_claims_status_idx on public.mme_logistics_delivery_claims(claim_status,created_at desc);
do $$declare t text;begin foreach t in array array['mme_logistics_shipments','mme_logistics_shipment_events','mme_logistics_delivery_claims'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
commit;