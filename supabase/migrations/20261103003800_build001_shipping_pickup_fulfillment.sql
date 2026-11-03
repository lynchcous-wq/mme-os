-- Build 001: fulfillment lifecycle for paid shipping and customer pickup orders.
create table public.mme_order_fulfillments (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null unique references public.mme_orders(id) on delete restrict,
 fulfillment_method text not null check(fulfillment_method in ('shipping','pickup')),
 fulfillment_status text not null default 'queued' check(fulfillment_status in ('queued','picking','packed','ready_for_pickup','shipped','out_for_delivery','delivered','picked_up','exception','cancelled')),
 carrier_name text, service_level text, tracking_number text, tracking_url text,
 shipping_label_reference text, package_count integer not null default 1 check(package_count between 1 and 100),
 pickup_location_id uuid references public.mme_store_locations(id) on delete restrict,
 pickup_ready_at timestamptz, pickup_completed_at timestamptz,
 recipient_name_snapshot text, recipient_contact_snapshot text, address_snapshot jsonb,
 created_by_identity_id uuid not null, updated_by_identity_id uuid not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((fulfillment_method='shipping' and pickup_location_id is null) or (fulfillment_method='pickup' and pickup_location_id is not null)),
 check(address_snapshot is null or jsonb_typeof(address_snapshot)='object')
);
create unique index mme_order_fulfillments_tracking_unique on public.mme_order_fulfillments(carrier_name,tracking_number) where tracking_number is not null;
create index mme_order_fulfillments_status_idx on public.mme_order_fulfillments(fulfillment_status,updated_at desc);
create table public.mme_fulfillment_events (
 id uuid primary key default gen_random_uuid(),
 fulfillment_id uuid not null references public.mme_order_fulfillments(id) on delete restrict,
 provider text not null check(provider in ('mme','ups','fedex','usps','dhl','local_delivery','pickup')),
 provider_event_id text not null, event_type text not null,
 event_status text not null check(event_status in ('accepted','rejected','exception','information')),
 location_text text, notes text, proof_sha256 text, payload_sha256 text,
 actor_identity_id uuid, occurred_at timestamptz not null default now(), received_at timestamptz not null default now(),
 unique(provider,provider_event_id),
 check(proof_sha256 is null or proof_sha256 ~ '^[0-9a-fA-F]{64}$'),
 check(payload_sha256 is null or payload_sha256 ~ '^[0-9a-fA-F]{64}$')
);
create index mme_fulfillment_events_history_idx on public.mme_fulfillment_events(fulfillment_id,occurred_at desc);
alter table public.mme_order_fulfillments enable row level security;
alter table public.mme_fulfillment_events enable row level security;
revoke all on public.mme_order_fulfillments,public.mme_fulfillment_events from public,anon,authenticated;
grant all on public.mme_order_fulfillments,public.mme_fulfillment_events to service_role;

create or replace function public.mme_create_order_fulfillment(p_order_id uuid,p_actor_identity_id uuid,p_pickup_location_id uuid default null,p_recipient_name text default null,p_recipient_contact text default null,p_address_snapshot jsonb default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_order public.mme_orders%rowtype; v_id uuid;
begin
 if p_order_id is null or p_actor_identity_id is null then raise exception 'Invalid fulfillment creation request' using errcode='22023'; end if;
 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found or v_order.status not in ('paid','partially_refunded') then raise exception 'Only paid orders can enter fulfillment' using errcode='23514'; end if;
 if v_order.fulfillment_method='pickup' and p_pickup_location_id is null then raise exception 'Pickup location is required' using errcode='22023'; end if;
 if v_order.fulfillment_method='shipping' and (p_address_snapshot is null or jsonb_typeof(p_address_snapshot)<>'object') then raise exception 'Shipping address snapshot is required' using errcode='22023'; end if;
 if p_pickup_location_id is not null and not exists(select 1 from public.mme_store_locations where id=p_pickup_location_id and active=true) then raise exception 'Pickup location is inactive or unknown' using errcode='23514'; end if;
 insert into public.mme_order_fulfillments(order_id,fulfillment_method,fulfillment_status,pickup_location_id,recipient_name_snapshot,recipient_contact_snapshot,address_snapshot,created_by_identity_id,updated_by_identity_id)
 values(p_order_id,v_order.fulfillment_method,'queued',p_pickup_location_id,left(p_recipient_name,180),left(p_recipient_contact,180),p_address_snapshot,p_actor_identity_id,p_actor_identity_id)
 on conflict(order_id) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.mme_order_fulfillments where order_id=p_order_id; end if;
 return v_id;
end; $$;

create or replace function public.mme_update_order_fulfillment(p_fulfillment_id uuid,p_next_status text,p_actor_identity_id uuid,p_carrier_name text default null,p_service_level text default null,p_tracking_number text default null,p_tracking_url text default null,p_label_reference text default null,p_package_count integer default 1,p_notes text default null,p_proof_sha256 text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_f public.mme_order_fulfillments%rowtype; v_allowed boolean:=false; v_event text;
begin
 if p_fulfillment_id is null or p_actor_identity_id is null or p_next_status not in ('picking','packed','ready_for_pickup','shipped','out_for_delivery','delivered','picked_up','exception','cancelled') or p_package_count is null or p_package_count not between 1 and 100 then raise exception 'Invalid fulfillment update' using errcode='22023'; end if;
 select * into v_f from public.mme_order_fulfillments where id=p_fulfillment_id for update;
 if not found then raise exception 'Fulfillment not found' using errcode='P0002'; end if;
 if v_f.fulfillment_status in ('delivered','picked_up','cancelled') then raise exception 'Fulfillment is terminal' using errcode='23514'; end if;
 v_allowed:=case v_f.fulfillment_status
  when 'queued' then p_next_status in ('picking','cancelled','exception')
  when 'picking' then p_next_status in ('packed','cancelled','exception')
  when 'packed' then p_next_status in ('shipped','ready_for_pickup','cancelled','exception')
  when 'ready_for_pickup' then p_next_status in ('picked_up','exception')
  when 'shipped' then p_next_status in ('out_for_delivery','delivered','exception')
  when 'out_for_delivery' then p_next_status in ('delivered','exception')
  when 'exception' then p_next_status in ('picking','packed','ready_for_pickup','shipped','out_for_delivery','cancelled')
  else false end;
 if not v_allowed then raise exception 'Invalid fulfillment status transition' using errcode='23514'; end if;
 if v_f.fulfillment_method='shipping' and p_next_status in ('shipped','out_for_delivery','delivered') and coalesce(p_tracking_number,v_f.tracking_number) is null then raise exception 'Shipping tracking number required' using errcode='23514'; end if;
 if v_f.fulfillment_method='pickup' and p_next_status in ('shipped','out_for_delivery','delivered') then raise exception 'Pickup orders cannot use carrier delivery states' using errcode='23514'; end if;
 if v_f.fulfillment_method='shipping' and p_next_status in ('ready_for_pickup','picked_up') then raise exception 'Shipping orders cannot use pickup states' using errcode='23514'; end if;
 if p_next_status in ('delivered','picked_up') and (p_proof_sha256 is null or p_proof_sha256 !~ '^[0-9a-fA-F]{64}$') then raise exception 'Completion requires a SHA-256 proof reference' using errcode='23514'; end if;
 update public.mme_order_fulfillments set fulfillment_status=p_next_status,carrier_name=coalesce(left(p_carrier_name,100),carrier_name),service_level=coalesce(left(p_service_level,100),service_level),tracking_number=coalesce(left(p_tracking_number,255),tracking_number),tracking_url=coalesce(left(p_tracking_url,1000),tracking_url),shipping_label_reference=coalesce(left(p_label_reference,255),shipping_label_reference),package_count=p_package_count, pickup_ready_at=case when p_next_status='ready_for_pickup' then now() else pickup_ready_at end,pickup_completed_at=case when p_next_status='picked_up' then now() else pickup_completed_at end,updated_by_identity_id=p_actor_identity_id,updated_at=now() where id=p_fulfillment_id;
 v_event:=case when p_next_status='exception' then 'fulfillment_exception' else 'status_'||p_next_status end;
 insert into public.mme_fulfillment_events(fulfillment_id,provider,provider_event_id,event_type,event_status,notes,proof_sha256,actor_identity_id)
 values(p_fulfillment_id,'mme','mme:'||p_fulfillment_id::text||':'||gen_random_uuid()::text,v_event,case when p_next_status='exception' then 'exception' else 'accepted' end,left(p_notes,1000),lower(p_proof_sha256),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_record_carrier_fulfillment_event(p_fulfillment_id uuid,p_provider text,p_provider_event_id text,p_event_type text,p_event_status text,p_location_text text,p_notes text,p_payload_sha256 text,p_occurred_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_f public.mme_order_fulfillments%rowtype; v_id uuid;
begin
 if p_fulfillment_id is null or p_provider not in ('ups','fedex','usps','dhl','local_delivery') or p_provider_event_id is null or length(btrim(p_provider_event_id)) not between 1 and 255 or p_event_type is null or length(btrim(p_event_type)) not between 1 and 120 or p_event_status not in ('accepted','rejected','exception','information') or p_payload_sha256 is null or p_payload_sha256 !~ '^[0-9a-fA-F]{64}$' then raise exception 'Invalid carrier event' using errcode='22023'; end if;
 select * into v_f from public.mme_order_fulfillments where id=p_fulfillment_id for update;
 if not found or v_f.fulfillment_method<>'shipping' then raise exception 'Shipping fulfillment not found' using errcode='P0002'; end if;
 insert into public.mme_fulfillment_events(fulfillment_id,provider,provider_event_id,event_type,event_status,location_text,notes,payload_sha256,occurred_at)
 values(p_fulfillment_id,p_provider,btrim(p_provider_event_id),btrim(p_event_type),p_event_status,left(p_location_text,255),left(p_notes,1000),lower(p_payload_sha256),coalesce(p_occurred_at,now()))
 on conflict(provider,provider_event_id) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.mme_fulfillment_events where provider=p_provider and provider_event_id=btrim(p_provider_event_id); end if;
 return v_id;
end; $$;

revoke all on function public.mme_create_order_fulfillment(uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_update_order_fulfillment(uuid,text,uuid,text,text,text,text,text,integer,text,text) from public,anon,authenticated;
revoke all on function public.mme_record_carrier_fulfillment_event(uuid,text,text,text,text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.mme_create_order_fulfillment(uuid,uuid,uuid,text,text,jsonb) to service_role;
grant execute on function public.mme_update_order_fulfillment(uuid,text,uuid,text,text,text,text,text,integer,text,text) to service_role;
grant execute on function public.mme_record_carrier_fulfillment_event(uuid,text,text,text,text,text,text,text,timestamptz) to service_role;
comment on table public.mme_order_fulfillments is 'Paid order shipping and pickup lifecycle with tracking, label and completion proof references.';
comment on table public.mme_fulfillment_events is 'Idempotent carrier and internal fulfillment event history; provider webhook signature verification occurs before ingestion.';