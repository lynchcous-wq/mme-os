-- Build 001: explicit terminal dispositions for serialized devices.
-- Keep a durable, append-only record for each manager decision.

alter table public.mme_serialized_units
  drop constraint if exists mme_serialized_units_unit_status_check;
alter table public.mme_serialized_units
  add constraint mme_serialized_units_unit_status_check
  check (unit_status in ('in_stock','reserved','sold','repair','quarantine','written_off','returned_to_supplier'));

create table public.mme_serialized_unit_dispositions (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null unique references public.mme_inventory_inspections(id) on delete restrict,
  unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
  product_id uuid not null references public.mme_products(id) on delete restrict,
  location_id uuid not null references public.mme_store_locations(id) on delete restrict,
  resolution text not null check (resolution in ('return_to_stock','write_off','return_to_supplier')),
  prior_unit_status text not null check (prior_unit_status in ('repair','quarantine')),
  resulting_unit_status text not null check (resulting_unit_status in ('in_stock','written_off','returned_to_supplier')),
  condition_before text not null check (condition_before in ('new','open_box','refurbished','used')),
  condition_after text check (condition_after is null or condition_after in ('new','open_box','refurbished','used','damaged','unusable')),
  reason text not null check (length(btrim(reason)) between 5 and 1000),
  actor_identity_id uuid not null,
  approved_by_identity_id uuid not null,
  created_at timestamptz not null default now(),
  check (
    (resolution='return_to_stock' and resulting_unit_status='in_stock'
      and condition_after in ('new','open_box','refurbished','used'))
    or (resolution='write_off' and resulting_unit_status='written_off')
    or (resolution='return_to_supplier' and resulting_unit_status='returned_to_supplier')
  )
);

create index mme_serialized_unit_dispositions_unit_created_idx
  on public.mme_serialized_unit_dispositions(unit_id,created_at desc);

alter table public.mme_serialized_unit_dispositions enable row level security;
revoke all on public.mme_serialized_unit_dispositions from public,anon,authenticated;
grant all on public.mme_serialized_unit_dispositions to service_role;

create or replace function public.mme_resolve_serialized_inspection(
  p_inspection_id uuid,p_resolution text,p_condition_after text,
  p_reason text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_i record; v_unit record; v_next_status text;
begin
  if p_inspection_id is null
     or p_resolution not in ('return_to_stock','write_off','return_to_supplier')
     or p_reason is null or length(btrim(p_reason)) not between 5 and 1000
     or p_actor_identity_id is null or p_approved_by_identity_id is null
     or p_actor_identity_id <> p_approved_by_identity_id
     or (p_condition_after is not null and p_condition_after not in ('new','open_box','refurbished','used','damaged','unusable')) then
    raise exception 'Invalid serialized inspection resolution' using errcode='22023';
  end if;

  select * into v_i from public.mme_inventory_inspections
   where id=p_inspection_id for update;
  if not found or v_i.disposition<>'pending' or v_i.serialized_unit_id is null then
    return false;
  end if;

  select * into v_unit from public.mme_serialized_units
   where id=v_i.serialized_unit_id for update;
  if not found or v_unit.unit_status not in ('repair','quarantine') then
    return false;
  end if;

  if p_resolution='return_to_stock' then
    if p_condition_after not in ('new','open_box','refurbished','used') then
      raise exception 'Return to stock requires a saleable condition grade' using errcode='22023';
    end if;
    v_next_status := 'in_stock';
  elsif p_resolution='write_off' then
    if p_condition_after is not null then
      raise exception 'Written-off devices cannot receive a saleable condition grade' using errcode='22023';
    end if;
    v_next_status := 'written_off';
  else
    if p_condition_after is not null then
      raise exception 'Supplier returns cannot receive a saleable condition grade' using errcode='22023';
    end if;
    v_next_status := 'returned_to_supplier';
  end if;

  insert into public.mme_serialized_unit_dispositions(
    inspection_id,unit_id,product_id,location_id,resolution,
    prior_unit_status,resulting_unit_status,condition_before,condition_after,
    reason,actor_identity_id,approved_by_identity_id
  ) values (
    v_i.id,v_unit.id,v_unit.product_id,v_unit.location_id,p_resolution,
    v_unit.unit_status,v_next_status,v_unit.condition_grade,p_condition_after,
    btrim(p_reason),p_actor_identity_id,p_approved_by_identity_id
  );

  update public.mme_serialized_units
   set unit_status=v_next_status,
       condition_grade=case when p_resolution='return_to_stock' then p_condition_after else condition_grade end,
       sold_at=case when p_resolution='return_to_stock' then null else sold_at end,
       updated_at=now()
   where id=v_unit.id;

  update public.mme_inventory_inspections
   set disposition=p_resolution,condition_after=p_condition_after,
       reason=reason||' | Resolution: '||btrim(p_reason),
       resolved_by_identity_id=p_actor_identity_id,
       approved_by_identity_id=p_approved_by_identity_id,
       resolved_at=now(),updated_at=now()
   where id=p_inspection_id;

  return true;
end;
$$;

revoke all on function public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_resolve_serialized_inspection(uuid,text,text,text,uuid,uuid) to service_role;

comment on table public.mme_serialized_unit_dispositions is
  'Append-only manager disposition ledger for serialized device return-to-stock, write-off and supplier-return decisions.';
