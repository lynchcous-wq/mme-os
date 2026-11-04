-- Build 001: executive inventory control-center KPIs and auditable movement feed.
-- All read functions are trusted-service only; the application server enforces MME role access.

create or replace function public.mme_get_inventory_control_summary(
 p_location_id uuid default null
) returns table(
 active_sku_count bigint,
 aggregate_on_hand bigint,
 aggregate_reserved bigint,
 aggregate_available bigint,
 aggregate_inventory_value_cents bigint,
 serialized_in_stock bigint,
 serialized_reserved bigint,
 serialized_sold bigint,
 serialized_repair_quarantine bigint,
 reorder_alert_count bigint,
 products_not_configured_count bigint,
 open_receiving_sessions bigint,
 open_stocktake_sessions bigint,
 pending_purchase_proposals bigint,
 generated_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_location_id is not null and not exists(
  select 1 from public.mme_store_locations where id=p_location_id and active=true
 ) then raise exception 'Active location not found' using errcode='P0002'; end if;
 return query
 select
  count(distinct d.product_id),
  coalesce(sum(d.aggregate_on_hand),0),
  coalesce(sum(d.aggregate_reserved),0),
  coalesce(sum(d.aggregate_available),0),
  coalesce(sum(d.aggregate_inventory_value_cents),0),
  coalesce(sum(d.serialized_on_hand),0),
  coalesce(sum(d.serialized_reserved),0),
  coalesce(sum(d.serialized_sold),0),
  coalesce(sum(d.serialized_repair_quarantine),0),
  count(*) filter(where d.reorder_status='reorder'),
  count(*) filter(where d.reorder_status='not_configured'),
  (select count(*) from public.mme_receiving_station_sessions s
   where s.session_status in ('open','submitted') and (p_location_id is null or s.location_id=p_location_id)),
  (select count(*) from public.mme_inventory_count_sessions s
   where s.status in ('open','submitted') and (p_location_id is null or s.location_id=p_location_id)),
  (select count(*) from public.mme_purchase_proposals p
   where p.status in ('draft','submitted') and (p_location_id is null or p.location_id=p_location_id)),
  now()
 from public.mme_inventory_dashboard_v d
 where p_location_id is null or d.location_id=p_location_id;
end; $$;

create or replace function public.mme_get_inventory_movement_feed(
 p_location_id uuid default null,
 p_product_id uuid default null,
 p_movement_type text default null,
 p_from timestamptz default null,
 p_to timestamptz default null,
 p_limit integer default 100,
 p_offset integer default 0
) returns table(
 movement_id uuid,product_id uuid,sku text,product_title text,
 location_id uuid,location_code text,movement_type text,quantity_delta integer,
 on_hand_before integer,on_hand_after integer,reserved_before integer,reserved_after integer,
 unit_cost_cents bigint,receipt_id uuid,transfer_group_id uuid,reason text,
 reference_text text,actor_identity_id uuid,approved_by_identity_id uuid,created_at timestamptz
) language plpgsql stable security definer set search_path=''
as $$
begin
 if p_limit is null or p_limit<1 or p_limit>500 or p_offset is null or p_offset<0
  or p_from is not null and p_to is not null and p_from>p_to
  or p_movement_type is not null and p_movement_type not in
   ('receipt','adjustment_increase','adjustment_decrease','transfer_in','transfer_out','damage','repair','quarantine','release_quarantine') then
  raise exception 'Invalid movement feed query' using errcode='22023';
 end if;
 return query
 select m.id,m.product_id,p.sku,p.title,m.location_id,l.location_code,m.movement_type,m.quantity_delta,
  m.on_hand_before,m.on_hand_after,m.reserved_before,m.reserved_after,m.unit_cost_cents,
  m.receipt_id,m.transfer_group_id,m.reason,m.reference_text,m.actor_identity_id,m.approved_by_identity_id,m.created_at
 from public.mme_inventory_movements m
 join public.mme_products p on p.id=m.product_id
 join public.mme_store_locations l on l.id=m.location_id
 where (p_location_id is null or m.location_id=p_location_id)
  and (p_product_id is null or m.product_id=p_product_id)
  and (p_movement_type is null or m.movement_type=p_movement_type)
  and (p_from is null or m.created_at>=p_from)
  and (p_to is null or m.created_at<p_to)
 order by m.created_at desc,m.id desc
 limit p_limit offset p_offset;
end; $$;

revoke all on function public.mme_get_inventory_control_summary(uuid) from public,anon,authenticated;
revoke all on function public.mme_get_inventory_movement_feed(uuid,uuid,text,timestamptz,timestamptz,integer,integer) from public,anon,authenticated;
grant execute on function public.mme_get_inventory_control_summary(uuid) to service_role;
grant execute on function public.mme_get_inventory_movement_feed(uuid,uuid,text,timestamptz,timestamptz,integer,integer) to service_role;

comment on function public.mme_get_inventory_control_summary(uuid) is
 'Location-scoped KPIs for the MME inventory command center. Inventory cost value excludes serialized units.';
comment on function public.mme_get_inventory_movement_feed(uuid,uuid,text,timestamptz,timestamptz,integer,integer) is
 'Paginated, filterable immutable inventory movement feed for audit and reconciliation.';
