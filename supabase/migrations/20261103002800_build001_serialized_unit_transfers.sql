-- Build 001: auditable serialized-device movements and location transfers.
-- Trusted server must authenticate the employee and verify source/destination permissions.

create table public.mme_serialized_unit_movements (
 id uuid primary key default gen_random_uuid(),
 unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 movement_type text not null check(movement_type in ('transfer','status_change','receiving','sale','return')),
 from_location_id uuid references public.mme_store_locations(id) on delete restrict,
 to_location_id uuid references public.mme_store_locations(id) on delete restrict,
 status_before text check(status_before in ('in_stock','reserved','sold','repair','quarantine')),
 status_after text check(status_after in ('in_stock','reserved','sold','repair','quarantine')),
 transfer_group_id uuid,
 reason text not null check(length(btrim(reason)) between 3 and 500),
 reference_text text,
 actor_identity_id uuid not null,
 approved_by_identity_id uuid,
 created_at timestamptz not null default now(),
 check(from_location_id is distinct from to_location_id or status_before is distinct from status_after)
);
create index mme_serialized_unit_movements_unit_idx
 on public.mme_serialized_unit_movements(unit_id,created_at desc);
create index mme_serialized_unit_movements_transfer_idx
 on public.mme_serialized_unit_movements(transfer_group_id) where transfer_group_id is not null;
alter table public.mme_serialized_unit_movements enable row level security;
revoke all on public.mme_serialized_unit_movements from public,anon,authenticated;
grant all on public.mme_serialized_unit_movements to service_role;

create or replace function public.mme_transfer_serialized_units(
 p_unit_ids uuid[],p_to_location_id uuid,p_reason text,p_actor_identity_id uuid,
 p_approved_by_identity_id uuid,p_reference_text text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_group uuid:=gen_random_uuid(); v_unit record; v_count integer;
begin
 if p_unit_ids is null or coalesce(array_length(p_unit_ids,1),0)<1
  or array_length(p_unit_ids,1)>500 or p_to_location_id is null
  or p_reason is null or length(btrim(p_reason)) not between 3 and 500
  or p_actor_identity_id is null then
  raise exception 'Invalid serialized transfer request' using errcode='22023';
 end if;
 if (select count(distinct x) from unnest(p_unit_ids) x)<>array_length(p_unit_ids,1) then
  raise exception 'Duplicate unit ID in transfer request' using errcode='22023';
 end if;
 perform 1 from public.mme_store_locations where id=p_to_location_id and active=true;
 if not found then raise exception 'Active destination location not found' using errcode='P0002'; end if;
 -- Lock in UUID order so overlapping transfers cannot deadlock in opposite request order.
 perform 1 from public.mme_serialized_units where id=any(p_unit_ids) order by id for update;
 select count(*) into v_count from public.mme_serialized_units where id=any(p_unit_ids);
 if v_count<>array_length(p_unit_ids,1) then raise exception 'One or more serialized units were not found' using errcode='P0002'; end if;
 for v_unit in select * from public.mme_serialized_units where id=any(p_unit_ids) order by id loop
  if v_unit.unit_status<>'in_stock' then
   raise exception 'Only in-stock serialized units may be transferred; unit % is %',v_unit.id,v_unit.unit_status using errcode='23514';
  end if;
  if v_unit.location_id=p_to_location_id then
   raise exception 'Unit is already assigned to destination location' using errcode='23514';
  end if;
  update public.mme_serialized_units set location_id=p_to_location_id,updated_at=now() where id=v_unit.id;
  insert into public.mme_serialized_unit_movements(unit_id,movement_type,from_location_id,to_location_id,
   status_before,status_after,transfer_group_id,reason,reference_text,actor_identity_id,approved_by_identity_id)
  values(v_unit.id,'transfer',v_unit.location_id,p_to_location_id,v_unit.unit_status,v_unit.unit_status,
   v_group,btrim(p_reason),left(p_reference_text,100),p_actor_identity_id,p_approved_by_identity_id);
 end loop;
 return v_group;
end; $$;

create or replace function public.mme_change_serialized_unit_status(
 p_unit_id uuid,p_new_status text,p_reason text,p_actor_identity_id uuid,
 p_approved_by_identity_id uuid,p_reference_text text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_unit public.mme_serialized_units%rowtype; v_movement uuid;
begin
 if p_unit_id is null or p_new_status not in ('in_stock','repair','quarantine')
  or p_reason is null or length(btrim(p_reason)) not between 3 and 500
  or p_actor_identity_id is null then
  raise exception 'Invalid serialized unit status change' using errcode='22023';
 end if;
 select * into v_unit from public.mme_serialized_units where id=p_unit_id for update;
 if not found then raise exception 'Serialized unit not found' using errcode='P0002'; end if;
 if v_unit.unit_status='sold' or v_unit.unit_status='reserved' then
  raise exception 'Sold or reserved units require their dedicated return or reservation workflow' using errcode='23514';
 end if;
 if v_unit.unit_status=p_new_status then raise exception 'Unit already has requested status' using errcode='23514'; end if;
 if v_unit.unit_status='quarantine' and p_new_status='in_stock' and p_approved_by_identity_id is null then
  raise exception 'Release from quarantine requires an approver' using errcode='23514';
 end if;
 update public.mme_serialized_units set unit_status=p_new_status,updated_at=now() where id=p_unit_id;
 insert into public.mme_serialized_unit_movements(unit_id,movement_type,from_location_id,to_location_id,
  status_before,status_after,reason,reference_text,actor_identity_id,approved_by_identity_id)
 values(p_unit_id,'status_change',v_unit.location_id,v_unit.location_id,v_unit.unit_status,p_new_status,
  btrim(p_reason),left(p_reference_text,100),p_actor_identity_id,p_approved_by_identity_id)
 returning id into v_movement;
 return v_movement;
end; $$;

revoke all on function public.mme_transfer_serialized_units(uuid[],uuid,text,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_change_serialized_unit_status(uuid,text,text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_transfer_serialized_units(uuid[],uuid,text,uuid,uuid,text) to service_role;
grant execute on function public.mme_change_serialized_unit_status(uuid,text,text,uuid,uuid,text) to service_role;

comment on table public.mme_serialized_unit_movements is
 'Immutable per-device location and status movement history, separate from aggregate quantity movements.';
