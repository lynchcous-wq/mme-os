-- Build 009.62 — order fulfillment orchestration over Build 009.61 reservations.
begin;
create table public.mme_fulfillment_orders (
 fulfillment_id uuid primary key default gen_random_uuid(),
 external_order_reference text not null unique,
 source_channel text not null check(source_channel in ('website','pos','local_pickup','shipping','subscription','auction')),
 fulfillment_method text not null check(fulfillment_method in ('ship','pickup','local_delivery')),
 status text not null default 'awaiting_payment' check(status in ('awaiting_payment','paid','allocated','picking','picked','packing','packed','ready_for_pickup','awaiting_carrier','shipped','in_transit','out_for_delivery','delivered','picked_up','exception','cancelled')),
 customer_reference text, destination_location text not null,
 recipient_name text, recipient_phone text, recipient_email text,
 address_line1 text, address_line2 text, city text, region text, postal_code text, country_code text,
 pickup_code_hash text, pickup_expires_at timestamptz,
 carrier text, tracking_number text, label_reference text,
 promised_at timestamptz, paid_at timestamptz, shipped_at timestamptz, completed_at timestamptz,
 created_by uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((fulfillment_method='ship' and address_line1 is not null) or fulfillment_method<>'ship'),
 check((fulfillment_method='pickup' and pickup_code_hash is not null) or fulfillment_method<>'pickup')
);
create table public.mme_fulfillment_order_lines (
 fulfillment_line_id uuid primary key default gen_random_uuid(),
 fulfillment_id uuid not null references public.mme_fulfillment_orders(fulfillment_id) on delete restrict,
 reservation_id uuid not null references public.mme_inventory_reservations(reservation_id) on delete restrict,
 sku_reference text not null, quantity bigint not null check(quantity>0),
 picked_quantity bigint not null default 0 check(picked_quantity>=0),
 packed_quantity bigint not null default 0 check(packed_quantity>=0),
 line_status text not null default 'allocated' check(line_status in ('allocated','picking','picked','packed','exception','cancelled')),
 unique(fulfillment_id,reservation_id),
 check(picked_quantity<=quantity),check(packed_quantity<=picked_quantity)
);
create table public.mme_fulfillment_packages (
 package_id uuid primary key default gen_random_uuid(),
 fulfillment_id uuid not null references public.mme_fulfillment_orders(fulfillment_id) on delete restrict,
 package_number integer not null check(package_number>0),
 weight_grams bigint check(weight_grams is null or weight_grams>0),
 length_mm bigint check(length_mm is null or length_mm>0),
 width_mm bigint check(width_mm is null or width_mm>0),
 height_mm bigint check(height_mm is null or height_mm>0),
 label_reference text, tracking_number text,
 status text not null default 'draft' check(status in ('draft','packed','label_created','handed_to_carrier','delivered','exception')),
 created_by uuid not null, created_at timestamptz not null default now(),
 unique(fulfillment_id,package_number)
);
create table public.mme_fulfillment_events (
 event_id bigint generated always as identity primary key,
 fulfillment_id uuid not null references public.mme_fulfillment_orders(fulfillment_id) on delete restrict,
 fulfillment_line_id uuid references public.mme_fulfillment_order_lines(fulfillment_line_id) on delete restrict,
 package_id uuid references public.mme_fulfillment_packages(package_id) on delete restrict,
 event_type text not null, actor_user_id uuid not null,
 event_data jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table public.mme_fulfillment_exceptions (
 exception_id uuid primary key default gen_random_uuid(),
 fulfillment_id uuid not null references public.mme_fulfillment_orders(fulfillment_id) on delete restrict,
 fulfillment_line_id uuid references public.mme_fulfillment_order_lines(fulfillment_line_id) on delete restrict,
 exception_type text not null check(exception_type in ('short_pick','wrong_item','serial_mismatch','packing_damage','label_failure','carrier_delay','failed_delivery','pickup_expired','other')),
 severity text not null default 'medium' check(severity in ('low','medium','high','critical')),
 description text not null, evidence_reference text,
 status text not null default 'open' check(status in ('open','investigating','resolved','waived')),
 resolution_note text, resolved_by uuid, resolved_at timestamptz,
 created_by uuid not null, created_at timestamptz not null default now()
);
create index mme_fulfillment_orders_status_idx on public.mme_fulfillment_orders(status,created_at desc);
create index mme_fulfillment_orders_tracking_idx on public.mme_fulfillment_orders(tracking_number) where tracking_number is not null;
create index mme_fulfillment_lines_order_idx on public.mme_fulfillment_order_lines(fulfillment_id);
do $$ declare t text; begin foreach t in array array['mme_fulfillment_orders','mme_fulfillment_order_lines','mme_fulfillment_packages','mme_fulfillment_events','mme_fulfillment_exceptions'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop; end $$;
grant select,insert,update on public.mme_fulfillment_orders,public.mme_fulfillment_order_lines,public.mme_fulfillment_packages,public.mme_fulfillment_exceptions to service_role;
grant select,insert on public.mme_fulfillment_events to service_role;
revoke update,delete,truncate on public.mme_fulfillment_events from public,anon,authenticated,service_role;

create or replace function public.mme_fulfillment_create_order(
 p_external_ref text,p_channel text,p_method text,p_location text,p_customer text,p_actor uuid,
 p_pickup_code_hash text default null,p_pickup_expires timestamptz default null,
 p_recipient text default null,p_phone text default null,p_email text default null,
 p_address1 text default null,p_address2 text default null,p_city text default null,p_region text default null,p_postal text default null,p_country text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v uuid;
begin
 if trim(coalesce(p_external_ref,''))='' or p_actor is null then raise exception 'Order reference and actor required' using errcode='22023'; end if;
 if p_method='pickup' and (p_pickup_code_hash is null or p_pickup_expires<=now()) then raise exception 'Pickup code hash and future expiry required' using errcode='22023'; end if;
 if p_method='ship' and trim(coalesce(p_address1,''))='' then raise exception 'Shipping address required' using errcode='22023'; end if;
 insert into public.mme_fulfillment_orders(external_order_reference,source_channel,fulfillment_method,destination_location,customer_reference,created_by,pickup_code_hash,pickup_expires_at,recipient_name,recipient_phone,recipient_email,address_line1,address_line2,city,region,postal_code,country_code)
 values(p_external_ref,p_channel,p_method,p_location,p_customer,p_actor,p_pickup_code_hash,p_pickup_expires,p_recipient,p_phone,p_email,p_address1,p_address2,p_city,p_region,p_postal,upper(p_country))
 returning fulfillment_id into v;
 insert into public.mme_fulfillment_events(fulfillment_id,event_type,actor_user_id,event_data) values(v,'order_intake_created',p_actor,jsonb_build_object('channel',p_channel,'method',p_method,'external_order_reference',p_external_ref));
 return v;
end; $$;

create or replace function public.mme_fulfillment_add_reserved_line(p_fulfillment uuid,p_reservation uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.mme_fulfillment_orders%rowtype; r public.mme_inventory_reservations%rowtype; v uuid;
begin
 select * into o from public.mme_fulfillment_orders where fulfillment_id=p_fulfillment for update;
 select * into r from public.mme_inventory_reservations where reservation_id=p_reservation;
 if not found or o.status not in ('awaiting_payment','paid','allocated') or r.status<>'active' or r.order_reference<>o.external_order_reference or r.location_code<>o.destination_location then
  raise exception 'Active reservation must match order and fulfillment location' using errcode='23514';
 end if;
 insert into public.mme_fulfillment_order_lines(fulfillment_id,reservation_id,sku_reference,quantity)
 values(p_fulfillment,p_reservation,r.sku_reference,r.quantity) returning fulfillment_line_id into v;
 insert into public.mme_fulfillment_events(fulfillment_id,fulfillment_line_id,event_type,actor_user_id,event_data)
 values(p_fulfillment,v,'reservation_attached',p_actor,jsonb_build_object('reservation_id',p_reservation,'quantity',r.quantity));
 return v;
end; $$;

create or replace function public.mme_fulfillment_confirm_paid(p_fulfillment uuid,p_actor uuid,p_posting_prefix text)
returns integer language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.mme_fulfillment_orders%rowtype; l record; n integer:=0;
begin
 select * into o from public.mme_fulfillment_orders where fulfillment_id=p_fulfillment for update;
 if not found or o.status not in ('awaiting_payment','paid') or length(trim(coalesce(p_posting_prefix,'')))<8 then raise exception 'Order state or posting key invalid' using errcode='55000'; end if;
 if o.status='paid' then return 0; end if;
 if not exists(select 1 from public.mme_fulfillment_order_lines where fulfillment_id=p_fulfillment) then raise exception 'Order requires reserved lines' using errcode='23514'; end if;
 for l in select * from public.mme_fulfillment_order_lines where fulfillment_id=p_fulfillment order by fulfillment_line_id loop
  perform public.mme_inventory_consume_reservation(l.reservation_id,p_actor,p_posting_prefix||':'||l.reservation_id::text);
  n:=n+1;
 end loop;
 update public.mme_fulfillment_orders set status='paid',paid_at=now(),updated_at=now() where fulfillment_id=p_fulfillment;
 insert into public.mme_fulfillment_events(fulfillment_id,event_type,actor_user_id,event_data) values(p_fulfillment,'payment_confirmed_and_stock_committed',p_actor,jsonb_build_object('line_count',n));
 return n;
end; $$;

create or replace function public.mme_fulfillment_pick_line(p_line uuid,p_quantity bigint,p_actor uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare l public.mme_fulfillment_order_lines%rowtype; o public.mme_fulfillment_orders%rowtype;
begin
 select * into l from public.mme_fulfillment_order_lines where fulfillment_line_id=p_line for update;
 select * into o from public.mme_fulfillment_orders where fulfillment_id=l.fulfillment_id for update;
 if not found or o.status not in ('paid','allocated','picking') or p_quantity<1 or l.picked_quantity+p_quantity>l.quantity then raise exception 'Invalid pick quantity or order state' using errcode='55000'; end if;
 update public.mme_fulfillment_order_lines set picked_quantity=picked_quantity+p_quantity,line_status=case when picked_quantity+p_quantity=quantity then 'picked' else 'picking' end where fulfillment_line_id=p_line;
 update public.mme_fulfillment_orders set status=case when not exists(select 1 from public.mme_fulfillment_order_lines where fulfillment_id=o.fulfillment_id and picked_quantity<quantity) then 'picked' else 'picking' end,updated_at=now() where fulfillment_id=o.fulfillment_id;
 insert into public.mme_fulfillment_events(fulfillment_id,fulfillment_line_id,event_type,actor_user_id,event_data) values(o.fulfillment_id,p_line,'items_picked',p_actor,jsonb_build_object('quantity',p_quantity));
end; $$;

create or replace function public.mme_fulfillment_pack_line(p_line uuid,p_quantity bigint,p_actor uuid,p_package integer)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare l public.mme_fulfillment_order_lines%rowtype; o public.mme_fulfillment_orders%rowtype; v uuid;
begin
 select * into l from public.mme_fulfillment_order_lines where fulfillment_line_id=p_line for update;
 select * into o from public.mme_fulfillment_orders where fulfillment_id=l.fulfillment_id for update;
 if not found or o.fulfillment_method<>'ship' or o.status not in ('picked','packing') or p_quantity<1 or l.packed_quantity+p_quantity>l.picked_quantity then raise exception 'Invalid packing operation' using errcode='55000'; end if;
 insert into public.mme_fulfillment_packages(fulfillment_id,package_number,created_by) values(o.fulfillment_id,p_package,p_actor)
 on conflict(fulfillment_id,package_number) do update set package_number=excluded.package_number returning package_id into v;
 update public.mme_fulfillment_order_lines set packed_quantity=packed_quantity+p_quantity,line_status=case when packed_quantity+p_quantity=quantity then 'packed' else 'picked' end where fulfillment_line_id=p_line;
 update public.mme_fulfillment_orders set status=case when not exists(select 1 from public.mme_fulfillment_order_lines where fulfillment_id=o.fulfillment_id and packed_quantity<quantity) then 'packed' else 'packing' end,updated_at=now() where fulfillment_id=o.fulfillment_id;
 insert into public.mme_fulfillment_events(fulfillment_id,fulfillment_line_id,package_id,event_type,actor_user_id,event_data) values(o.fulfillment_id,p_line,v,'items_packed',p_actor,jsonb_build_object('quantity',p_quantity));
 return v;
end; $$;

create or replace function public.mme_fulfillment_record_label(p_fulfillment uuid,p_actor uuid,p_carrier text,p_tracking text,p_label_ref text,p_package integer)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.mme_fulfillment_orders%rowtype; p public.mme_fulfillment_packages%rowtype;
begin
 select * into o from public.mme_fulfillment_orders where fulfillment_id=p_fulfillment for update;
 if not found or o.fulfillment_method<>'ship' or o.status<>'packed' or trim(coalesce(p_tracking,''))='' then raise exception 'Packed shipment and tracking number required' using errcode='55000'; end if;
 select * into p from public.mme_fulfillment_packages where fulfillment_id=p_fulfillment and package_number=p_package for update;
 if not found then raise exception 'Package not found' using errcode='22023'; end if;
 update public.mme_fulfillment_packages set label_reference=p_label_ref,tracking_number=p_tracking,status='label_created' where package_id=p.package_id;
 update public.mme_fulfillment_orders set status='awaiting_carrier',carrier=p_carrier,tracking_number=p_tracking,label_reference=p_label_ref,updated_at=now() where fulfillment_id=p_fulfillment;
 insert into public.mme_fulfillment_events(fulfillment_id,package_id,event_type,actor_user_id,event_data) values(p_fulfillment,p.package_id,'shipping_label_recorded',p_actor,jsonb_build_object('carrier',p_carrier,'tracking',p_tracking,'label_reference',p_label_ref));
 return p.package_id;
end; $$;

create or replace function public.mme_fulfillment_record_carrier_event(p_fulfillment uuid,p_actor uuid,p_event text,p_tracking text,p_evidence text default null)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.mme_fulfillment_orders%rowtype; s text;
begin
 select * into o from public.mme_fulfillment_orders where fulfillment_id=p_fulfillment for update;
 if not found or o.fulfillment_method<>'ship' or o.tracking_number is distinct from p_tracking then raise exception 'Tracking number does not match fulfillment' using errcode='55000'; end if;
 s:=case p_event when 'accepted' then 'in_transit' when 'in_transit' then 'in_transit' when 'out_for_delivery' then 'out_for_delivery' when 'delivered' then 'delivered' when 'delivery_failed' then 'exception' else null end;
 if s is null then raise exception 'Unsupported carrier event' using errcode='22023'; end if;
 update public.mme_fulfillment_orders set status=s,shipped_at=case when p_event='accepted' then coalesce(shipped_at,now()) else shipped_at end,completed_at=case when p_event='delivered' then now() else completed_at end,updated_at=now() where fulfillment_id=p_fulfillment;
 if p_event='delivery_failed' then insert into public.mme_fulfillment_exceptions(fulfillment_id,exception_type,severity,description,evidence_reference,created_by) values(p_fulfillment,'failed_delivery','high','Carrier reported failed delivery',p_evidence,p_actor); end if;
 insert into public.mme_fulfillment_events(fulfillment_id,event_type,actor_user_id,event_data) values(p_fulfillment,'carrier_'||p_event,p_actor,jsonb_build_object('tracking',p_tracking,'evidence',p_evidence));
end; $$;

create or replace function public.mme_fulfillment_confirm_pickup(p_fulfillment uuid,p_actor uuid,p_code_hash text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare o public.mme_fulfillment_orders%rowtype;
begin
 select * into o from public.mme_fulfillment_orders where fulfillment_id=p_fulfillment for update;
 if not found or o.fulfillment_method<>'pickup' or o.status not in ('paid','picked','ready_for_pickup') or o.pickup_expires_at<=now() or o.pickup_code_hash is distinct from p_code_hash then raise exception 'Pickup verification failed or expired' using errcode='55000'; end if;
 if exists(select 1 from public.mme_fulfillment_order_lines where fulfillment_id=p_fulfillment and picked_quantity<quantity) then raise exception 'All items must be picked before pickup' using errcode='23514'; end if;
 update public.mme_fulfillment_orders set status='picked_up',completed_at=now(),pickup_code_hash=null,updated_at=now() where fulfillment_id=p_fulfillment;
 insert into public.mme_fulfillment_events(fulfillment_id,event_type,actor_user_id) values(p_fulfillment,'customer_pickup_verified',p_actor);
end; $$;

create or replace function public.mme_fulfillment_raise_exception(p_fulfillment uuid,p_line uuid,p_actor uuid,p_type text,p_severity text,p_description text,p_evidence text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v uuid;
begin
 insert into public.mme_fulfillment_exceptions(fulfillment_id,fulfillment_line_id,exception_type,severity,description,evidence_reference,created_by)
 values(p_fulfillment,p_line,p_type,p_severity,left(p_description,2000),p_evidence,p_actor) returning exception_id into v;
 update public.mme_fulfillment_orders set status='exception',updated_at=now() where fulfillment_id=p_fulfillment;
 insert into public.mme_fulfillment_events(fulfillment_id,fulfillment_line_id,event_type,actor_user_id,event_data) values(p_fulfillment,p_line,'exception_opened',p_actor,jsonb_build_object('exception_id',v,'type',p_type,'severity',p_severity));
 return v;
end; $$;

do $$ declare f text; begin foreach f in array array[
'mme_fulfillment_create_order(text,text,text,text,text,uuid,text,timestamptz,text,text,text,text,text,text,text,text,text,text)',
'mme_fulfillment_add_reserved_line(uuid,uuid,uuid)','mme_fulfillment_confirm_paid(uuid,uuid,text)','mme_fulfillment_pick_line(uuid,bigint,uuid)',
'mme_fulfillment_pack_line(uuid,bigint,uuid,integer)','mme_fulfillment_record_label(uuid,uuid,text,text,text,integer)',
'mme_fulfillment_record_carrier_event(uuid,uuid,text,text,text)','mme_fulfillment_confirm_pickup(uuid,uuid,text)',
'mme_fulfillment_raise_exception(uuid,uuid,uuid,text,text,text,text)'
] loop execute format('revoke all on function public.%s from public,anon,authenticated',f); execute format('grant execute on function public.%s to service_role',f); end loop; end $$;
commit;
