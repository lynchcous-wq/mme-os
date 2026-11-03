-- Build 001: two-person approval workflow for inter-location stock transfers.
create table public.mme_inventory_transfer_requests (
 id uuid primary key default gen_random_uuid(),
 request_reference text not null unique,
 transfer_kind text not null check(transfer_kind in ('aggregate','serialized')),
 product_id uuid references public.mme_products(id) on delete restrict,
 from_location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 to_location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 quantity integer,
 serialized_unit_ids uuid[],
 reason text not null check(length(btrim(reason)) between 5 and 500),
 request_status text not null default 'pending_approval' check(request_status in ('pending_approval','approved','rejected','cancelled','completed','failed')),
 requested_by_identity_id uuid not null,
 approved_by_identity_id uuid,
 approved_at timestamptz,
 rejected_by_identity_id uuid,
 rejected_at timestamptz,
 rejection_reason text,
 transfer_group_id uuid,
 failure_code text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(from_location_id<>to_location_id),
 check((transfer_kind='aggregate' and product_id is not null and quantity between 1 and 10000 and serialized_unit_ids is null)
    or (transfer_kind='serialized' and product_id is null and quantity is null and serialized_unit_ids is not null
        and cardinality(serialized_unit_ids) between 1 and 500))
);
create index mme_transfer_requests_pending_idx on public.mme_inventory_transfer_requests(created_at)
 where request_status='pending_approval';
alter table public.mme_inventory_transfer_requests enable row level security;
revoke all on public.mme_inventory_transfer_requests from public,anon,authenticated;
grant all on public.mme_inventory_transfer_requests to service_role;

create or replace function public.mme_request_inventory_transfer(
 p_request_reference text,p_transfer_kind text,p_product_id uuid,
 p_from_location_id uuid,p_to_location_id uuid,p_quantity integer,
 p_serialized_unit_ids uuid[],p_reason text,p_requester_identity_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if p_request_reference is null or length(btrim(p_request_reference)) not between 3 and 100
  or p_transfer_kind not in ('aggregate','serialized') or p_from_location_id is null
  or p_to_location_id is null or p_from_location_id=p_to_location_id
  or p_reason is null or length(btrim(p_reason)) not between 5 and 500
  or p_requester_identity_id is null then
  raise exception 'Invalid transfer request' using errcode='22023'; end if;
 if not exists(select 1 from public.mme_store_locations where id=p_from_location_id and active=true)
  or not exists(select 1 from public.mme_store_locations where id=p_to_location_id and active=true) then
  raise exception 'Transfer locations must be active' using errcode='P0002'; end if;
 if p_transfer_kind='aggregate' then
  if p_product_id is null or p_quantity is null or p_quantity not between 1 and 10000 or p_serialized_unit_ids is not null then
   raise exception 'Invalid aggregate transfer details' using errcode='22023'; end if;
  if not exists(select 1 from public.mme_products where id=p_product_id and active=true and serialized=false) then
   raise exception 'Aggregate product not available' using errcode='P0002'; end if;
 else
  if p_product_id is not null or p_quantity is not null or p_serialized_unit_ids is null
   or cardinality(p_serialized_unit_ids) not between 1 and 500
   or (select count(distinct x) from unnest(p_serialized_unit_ids) x)<>cardinality(p_serialized_unit_ids) then
   raise exception 'Invalid serialized transfer details' using errcode='22023'; end if;
  if exists(select 1 from public.mme_serialized_units where id=any(p_serialized_unit_ids)
    and (unit_status<>'in_stock' or location_id<>p_from_location_id)) then
   raise exception 'Every serialized unit must be in stock at the source location' using errcode='23514'; end if;
  if (select count(*) from public.mme_serialized_units where id=any(p_serialized_unit_ids))<>cardinality(p_serialized_unit_ids) then
   raise exception 'One or more serialized units not found' using errcode='P0002'; end if;
 end if;
 insert into public.mme_inventory_transfer_requests(request_reference,transfer_kind,product_id,
  from_location_id,to_location_id,quantity,serialized_unit_ids,reason,requested_by_identity_id)
 values(btrim(p_request_reference),p_transfer_kind,p_product_id,p_from_location_id,p_to_location_id,
  p_quantity,p_serialized_unit_ids,btrim(p_reason),p_requester_identity_id) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_decide_inventory_transfer_request(
 p_request_id uuid,p_approver_identity_id uuid,p_approve boolean,p_rejection_reason text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.mme_inventory_transfer_requests%rowtype; v_group uuid;
begin
 if p_request_id is null or p_approver_identity_id is null or p_approve is null then
  raise exception 'Invalid transfer decision' using errcode='22023'; end if;
 select * into v from public.mme_inventory_transfer_requests where id=p_request_id for update;
 if not found or v.request_status<>'pending_approval' then
  raise exception 'Transfer request is not pending approval' using errcode='23514'; end if;
 if v.requested_by_identity_id=p_approver_identity_id then
  raise exception 'Requester cannot approve their own transfer' using errcode='42501'; end if;
 if not p_approve then
  if p_rejection_reason is null or length(btrim(p_rejection_reason))<5 then
   raise exception 'A meaningful rejection reason is required' using errcode='22023'; end if;
  update public.mme_inventory_transfer_requests set request_status='rejected',
   rejected_by_identity_id=p_approver_identity_id,rejected_at=now(),
   rejection_reason=btrim(p_rejection_reason),updated_at=now() where id=p_request_id;
  return p_request_id;
 end if;
 if v.transfer_kind='aggregate' then
  v_group:=public.mme_transfer_inventory(v.product_id,v.from_location_id,v.to_location_id,
   v.quantity,v.reason,p_approver_identity_id,p_approver_identity_id);
 else
  v_group:=public.mme_transfer_serialized_units(v.serialized_unit_ids,v.to_location_id,
   v.reason,p_approver_identity_id,p_approver_identity_id,v.request_reference);
 end if;
 update public.mme_inventory_transfer_requests set request_status='completed',
  approved_by_identity_id=p_approver_identity_id,approved_at=now(),
  transfer_group_id=v_group,updated_at=now() where id=p_request_id;
 return v_group;
end; $$;

revoke all on function public.mme_request_inventory_transfer(text,text,uuid,uuid,uuid,integer,uuid[],text,uuid) from public,anon,authenticated;
revoke all on function public.mme_decide_inventory_transfer_request(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.mme_request_inventory_transfer(text,text,uuid,uuid,uuid,integer,uuid[],text,uuid) to service_role;
grant execute on function public.mme_decide_inventory_transfer_request(uuid,uuid,boolean,text) to service_role;
comment on table public.mme_inventory_transfer_requests is 'Two-person approval workflow for aggregate and serialized transfers. Inventory changes only on approved decision.';
