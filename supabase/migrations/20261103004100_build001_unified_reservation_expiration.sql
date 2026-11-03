-- Build 001: route expired pending orders through the correct aggregate or serialized release path.
-- The original expiry worker used only aggregate release, leaving serialized units reserved.
create or replace function public.mme_expire_inventory_reservations(p_limit integer default 100)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order_id uuid;
  v_is_serialized boolean;
  v_count integer:=0;
begin
  if p_limit is null or p_limit<1 or p_limit>1000 then
    raise exception 'Expiry batch limit must be between 1 and 1000' using errcode='22023';
  end if;

  for v_order_id in
    select o.id
    from public.mme_orders o
    join public.mme_inventory_reservations r on r.order_id=o.id
    where o.status='pending_payment'
      and r.status='active'
      and r.expires_at<=now()
    order by r.expires_at,o.id
    for update of o skip locked
    limit p_limit
  loop
    select exists(
      select 1 from public.mme_order_lines l
      where l.order_id=v_order_id and l.serialized_unit_id is not null
    ) into v_is_serialized;

    if v_is_serialized then
      if public.mme_release_serialized_order_reservation(v_order_id,'expired') then
        v_count:=v_count+1;
      end if;
    else
      if public.mme_release_order_reservation(v_order_id,'expired') then
        v_count:=v_count+1;
      end if;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.mme_expire_inventory_reservations(integer) from public,anon,authenticated;
grant execute on function public.mme_expire_inventory_reservations(integer) to service_role;
comment on function public.mme_expire_inventory_reservations(integer) is
'Expires due pending-payment reservations. Dispatches serialized orders to serialized-unit release and aggregate orders to balance release; service-role worker only.';
