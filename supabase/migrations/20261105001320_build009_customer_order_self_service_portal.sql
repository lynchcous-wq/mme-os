-- Build 009.52 — authenticated customer order tracking and self-service read model.
-- Trusted commerce adapters maintain projections; customers can read only records bound to auth.uid().
begin;

create table public.mme_customer_account_links (
 auth_user_id uuid primary key,
 person_id uuid not null unique,
 link_status text not null default 'active' check(link_status in ('active','suspended','revoked')),
 linked_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_customer_account_links_person_idx on public.mme_customer_account_links(person_id);

create table public.mme_customer_order_portal (
 order_id uuid primary key,
 person_id uuid not null,
 order_reference text not null,
 order_status text not null check(order_status in ('pending','confirmed','processing','ready_for_pickup','partially_shipped','shipped','delivered','completed','cancelled','return_in_progress','refunded')),
 order_placed_at timestamptz not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 order_total numeric(14,2) not null check(order_total>=0),
 fulfillment_type text not null check(fulfillment_type in ('shipping','local_pickup','mixed')),
 location_id uuid,
 updated_at timestamptz not null default now(),
 unique(person_id,order_reference)
);
create index mme_customer_order_portal_history_idx on public.mme_customer_order_portal(person_id,order_placed_at desc);

create table public.mme_customer_order_fulfillment_portal (
 order_id uuid primary key references public.mme_customer_order_portal(order_id) on delete restrict,
 fulfillment_status text not null check(fulfillment_status in ('not_started','processing','label_created','in_transit','out_for_delivery','delivered','ready_for_pickup','picked_up','exception','cancelled')),
 carrier_name text,
 tracking_number text,
 tracking_url text,
 estimated_delivery_at timestamptz,
 pickup_location_id uuid,
 pickup_ready_at timestamptz,
 picked_up_at timestamptz,
 updated_at timestamptz not null default now(),
 check(tracking_url is null or tracking_url ~ '^https://'),
 check((tracking_number is null) or (carrier_name is not null))
);
create index mme_customer_order_fulfillment_status_idx on public.mme_customer_order_fulfillment_portal(fulfillment_status,updated_at desc);

create table public.mme_customer_order_refund_portal (
 refund_id uuid primary key,
 order_id uuid not null references public.mme_customer_order_portal(order_id) on delete restrict,
 refund_status text not null check(refund_status in ('requested','under_review','approved','processing','completed','failed','rejected')),
 refund_amount numeric(14,2) not null check(refund_amount>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 requested_at timestamptz not null,
 updated_at timestamptz not null default now()
);
create index mme_customer_order_refund_order_idx on public.mme_customer_order_refund_portal(order_id,requested_at desc);

create table public.mme_customer_order_warranty_portal (
 warranty_id uuid primary key,
 order_id uuid not null references public.mme_customer_order_portal(order_id) on delete restrict,
 item_reference text not null,
 warranty_name text not null,
 warranty_status text not null check(warranty_status in ('active','expiring','expired','claimed','voided')),
 starts_at timestamptz not null,
 expires_at timestamptz not null,
 updated_at timestamptz not null default now(),
 check(expires_at>=starts_at)
);
create index mme_customer_order_warranty_order_idx on public.mme_customer_order_warranty_portal(order_id,expires_at);

create table public.mme_customer_subscription_portal (
 subscription_id uuid primary key,
 person_id uuid not null,
 subscription_name text not null,
 subscription_status text not null check(subscription_status in ('trialing','active','past_due','paused','cancelled','expired')),
 current_period_ends_at timestamptz,
 cancel_at_period_end boolean not null default false,
 updated_at timestamptz not null default now()
);
create index mme_customer_subscription_person_idx on public.mme_customer_subscription_portal(person_id,updated_at desc);

create table public.mme_customer_order_service_requests (
 request_id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.mme_customer_order_portal(order_id) on delete restrict,
 person_id uuid not null,
 request_type text not null check(request_type in ('cancellation','return')),
 request_status text not null default 'submitted' check(request_status in ('submitted','under_review','approved','rejected','completed','withdrawn')),
 reason_code text not null check(reason_code in ('changed_mind','damaged','defective','wrong_item','not_as_described','late_delivery','duplicate_order','other')),
 customer_note text check(customer_note is null or length(customer_note)<=1000),
 requested_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_customer_order_service_requests_person_idx on public.mme_customer_order_service_requests(person_id,requested_at desc);
create unique index mme_customer_order_one_open_request_idx on public.mme_customer_order_service_requests(order_id,request_type)
 where request_status in ('submitted','under_review','approved');

alter table public.mme_customer_account_links enable row level security;
alter table public.mme_customer_order_portal enable row level security;
alter table public.mme_customer_order_fulfillment_portal enable row level security;
alter table public.mme_customer_order_refund_portal enable row level security;
alter table public.mme_customer_order_warranty_portal enable row level security;
alter table public.mme_customer_subscription_portal enable row level security;
alter table public.mme_customer_order_service_requests enable row level security;

revoke all on public.mme_customer_account_links,public.mme_customer_order_portal,
 public.mme_customer_order_fulfillment_portal,public.mme_customer_order_refund_portal,
 public.mme_customer_order_warranty_portal,public.mme_customer_subscription_portal,
 public.mme_customer_order_service_requests from public,anon,authenticated;
grant select on public.mme_customer_order_portal,public.mme_customer_order_fulfillment_portal,
 public.mme_customer_order_refund_portal,public.mme_customer_order_warranty_portal,
 public.mme_customer_subscription_portal,public.mme_customer_order_service_requests to authenticated;
grant select on public.mme_customer_account_links to authenticated;
grant select,insert,update on public.mme_customer_account_links,
 public.mme_customer_order_portal,public.mme_customer_order_fulfillment_portal,
 public.mme_customer_order_refund_portal,public.mme_customer_order_warranty_portal,
 public.mme_customer_subscription_portal,public.mme_customer_order_service_requests to service_role;
revoke update,delete,truncate on public.mme_customer_order_service_requests from public,anon,authenticated;

create policy mme_customer_account_link_self_read on public.mme_customer_account_links
 for select to authenticated using(auth_user_id=auth.uid() and link_status='active');
create policy mme_customer_order_self_read on public.mme_customer_order_portal
 for select to authenticated using(exists(select 1 from public.mme_customer_account_links l
  where l.auth_user_id=auth.uid() and l.person_id=mme_customer_order_portal.person_id and l.link_status='active'));
create policy mme_customer_fulfillment_self_read on public.mme_customer_order_fulfillment_portal
 for select to authenticated using(exists(select 1 from public.mme_customer_order_portal o
  join public.mme_customer_account_links l on l.person_id=o.person_id
  where o.order_id=mme_customer_order_fulfillment_portal.order_id and l.auth_user_id=auth.uid() and l.link_status='active'));
create policy mme_customer_refund_self_read on public.mme_customer_order_refund_portal
 for select to authenticated using(exists(select 1 from public.mme_customer_order_portal o
  join public.mme_customer_account_links l on l.person_id=o.person_id
  where o.order_id=mme_customer_order_refund_portal.order_id and l.auth_user_id=auth.uid() and l.link_status='active'));
create policy mme_customer_warranty_self_read on public.mme_customer_order_warranty_portal
 for select to authenticated using(exists(select 1 from public.mme_customer_order_portal o
  join public.mme_customer_account_links l on l.person_id=o.person_id
  where o.order_id=mme_customer_order_warranty_portal.order_id and l.auth_user_id=auth.uid() and l.link_status='active'));
create policy mme_customer_subscription_self_read on public.mme_customer_subscription_portal
 for select to authenticated using(exists(select 1 from public.mme_customer_account_links l
  where l.auth_user_id=auth.uid() and l.person_id=mme_customer_subscription_portal.person_id and l.link_status='active'));
create policy mme_customer_service_request_self_read on public.mme_customer_order_service_requests
 for select to authenticated using(exists(select 1 from public.mme_customer_account_links l
  where l.auth_user_id=auth.uid() and l.person_id=mme_customer_order_service_requests.person_id and l.link_status='active'));

create or replace function public.mme_customer_portal_submit_service_request(
 p_order_id uuid,p_request_type text,p_reason_code text,p_customer_note text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_person_id uuid; v_order public.mme_customer_order_portal%rowtype; v_id uuid;
begin
 if auth.uid() is null or p_order_id is null or p_request_type not in ('cancellation','return')
  or p_reason_code not in ('changed_mind','damaged','defective','wrong_item','not_as_described','late_delivery','duplicate_order','other')
  or (p_customer_note is not null and length(p_customer_note)>1000) then
  raise exception 'Invalid customer service request' using errcode='22023';
 end if;
 select l.person_id into v_person_id from public.mme_customer_account_links l
 where l.auth_user_id=auth.uid() and l.link_status='active';
 if v_person_id is null then raise exception 'Customer account link not found' using errcode='42501'; end if;
 select * into v_order from public.mme_customer_order_portal o
 where o.order_id=p_order_id and o.person_id=v_person_id for update;
 if not found then raise exception 'Order not found' using errcode='P0002'; end if;
 if p_request_type='cancellation' and v_order.order_status in ('shipped','delivered','completed','cancelled','refunded') then
  raise exception 'This order is no longer eligible for cancellation; submit a return request if applicable' using errcode='55000';
 end if;
 if p_request_type='return' and v_order.order_status not in ('delivered','completed','partially_shipped') then
  raise exception 'Return requests require an eligible fulfilled order' using errcode='55000';
 end if;
 insert into public.mme_customer_order_service_requests(order_id,person_id,request_type,reason_code,customer_note)
 values(p_order_id,v_person_id,p_request_type,p_reason_code,left(p_customer_note,1000))
 returning request_id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_customer_portal_provision_account_link(
 p_auth_user_id uuid,p_person_id uuid
) returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_auth_user_id is null or p_person_id is null or not exists(
  select 1 from public.mme_person_identities i where i.person_id=p_person_id and i.lifecycle_status='active'
 ) then raise exception 'Valid active identity and auth account required' using errcode='22023'; end if;
 insert into public.mme_customer_account_links(auth_user_id,person_id)
 values(p_auth_user_id,p_person_id)
 on conflict(auth_user_id) do update set person_id=excluded.person_id,link_status='active',updated_at=now();
end;
$$;

create or replace function public.mme_customer_portal_upsert_order_snapshot(
 p_order_id uuid,p_person_id uuid,p_order_reference text,p_order_status text,p_order_placed_at timestamptz,
 p_currency_code text,p_order_total numeric,p_fulfillment_type text,p_location_id uuid default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_order_id is null or p_person_id is null or p_order_reference is null or p_order_placed_at is null
  or p_currency_code is null or p_order_total is null or p_fulfillment_type is null
  or p_order_status not in ('pending','confirmed','processing','ready_for_pickup','partially_shipped','shipped','delivered','completed','cancelled','return_in_progress','refunded')
  or p_fulfillment_type not in ('shipping','local_pickup','mixed')
  or not exists(select 1 from public.mme_person_identities i where i.person_id=p_person_id and i.lifecycle_status='active') then
  raise exception 'Invalid order portal projection' using errcode='22023';
 end if;
 insert into public.mme_customer_order_portal(order_id,person_id,order_reference,order_status,order_placed_at,
  currency_code,order_total,fulfillment_type,location_id)
 values(p_order_id,p_person_id,p_order_reference,p_order_status,p_order_placed_at,p_currency_code,
  p_order_total,p_fulfillment_type,p_location_id)
 on conflict(order_id) do update set person_id=excluded.person_id,order_reference=excluded.order_reference,
  order_status=excluded.order_status,order_placed_at=excluded.order_placed_at,currency_code=excluded.currency_code,
  order_total=excluded.order_total,fulfillment_type=excluded.fulfillment_type,location_id=excluded.location_id,
  updated_at=now();
 return p_order_id;
end;
$$;

create or replace function public.mme_customer_portal_upsert_fulfillment_snapshot(
 p_order_id uuid,p_fulfillment_status text,p_carrier_name text default null,p_tracking_number text default null,
 p_tracking_url text default null,p_estimated_delivery_at timestamptz default null,
 p_pickup_location_id uuid default null,p_pickup_ready_at timestamptz default null,p_picked_up_at timestamptz default null
) returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_order_id is null or p_fulfillment_status not in ('not_started','processing','label_created','in_transit','out_for_delivery','delivered','ready_for_pickup','picked_up','exception','cancelled')
  or not exists(select 1 from public.mme_customer_order_portal o where o.order_id=p_order_id) then
  raise exception 'Invalid fulfillment portal projection' using errcode='22023';
 end if;
 insert into public.mme_customer_order_fulfillment_portal(order_id,fulfillment_status,carrier_name,
  tracking_number,tracking_url,estimated_delivery_at,pickup_location_id,pickup_ready_at,picked_up_at)
 values(p_order_id,p_fulfillment_status,p_carrier_name,p_tracking_number,p_tracking_url,
  p_estimated_delivery_at,p_pickup_location_id,p_pickup_ready_at,p_picked_up_at)
 on conflict(order_id) do update set fulfillment_status=excluded.fulfillment_status,
  carrier_name=excluded.carrier_name,tracking_number=excluded.tracking_number,tracking_url=excluded.tracking_url,
  estimated_delivery_at=excluded.estimated_delivery_at,pickup_location_id=excluded.pickup_location_id,
  pickup_ready_at=excluded.pickup_ready_at,picked_up_at=excluded.picked_up_at,updated_at=now();
end;
$$;

revoke all on function public.mme_customer_portal_submit_service_request(uuid,text,text,text) from public,anon;
revoke all on function public.mme_customer_portal_provision_account_link(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_customer_portal_upsert_order_snapshot(uuid,uuid,text,text,timestamptz,text,numeric,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_customer_portal_upsert_fulfillment_snapshot(uuid,text,text,text,text,timestamptz,uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.mme_customer_portal_submit_service_request(uuid,text,text,text) to authenticated;
grant execute on function public.mme_customer_portal_provision_account_link(uuid,uuid) to service_role;
grant execute on function public.mme_customer_portal_upsert_order_snapshot(uuid,uuid,text,text,timestamptz,text,numeric,text,uuid) to service_role;
grant execute on function public.mme_customer_portal_upsert_fulfillment_snapshot(uuid,text,text,text,text,timestamptz,uuid,timestamptz,timestamptz) to service_role;

comment on table public.mme_customer_order_portal is 'Customer-safe order history projection. Authoritative commerce records remain in the order domain.';
comment on table public.mme_customer_order_fulfillment_portal is 'Customer-safe carrier tracking, ETA and local pickup status projection.';
comment on table public.mme_customer_order_service_requests is 'Customer-originated cancellation and return requests awaiting policy and staff review.';

commit;
