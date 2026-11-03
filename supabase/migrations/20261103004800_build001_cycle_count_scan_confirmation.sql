-- Build 001: barcode scan must explicitly confirm a physical count line.
create or replace function public.mme_record_cycle_count_scan(
 p_session_id uuid,p_scan_value text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_session public.mme_cycle_count_sessions%rowtype; v_scan jsonb; v_line uuid;
 v_product uuid; v_unit uuid; v_count integer;
begin
 if p_session_id is null or p_scan_value is null or p_actor_identity_id is null then
  raise exception 'Invalid cycle count scan' using errcode='22023';
 end if;
 select * into v_session from public.mme_cycle_count_sessions where id=p_session_id for update;
 if not found or v_session.status<>'open' then raise exception 'Cycle count is not open' using errcode='23514'; end if;
 v_scan:=public.mme_resolve_inventory_scan(p_scan_value,v_session.location_id,p_actor_identity_id,'cycle-count');
 if v_scan->>'result' not in ('aggregate_product','serialized_unit') then
  raise exception 'Scan did not resolve to an inventory item' using errcode='P0002';
 end if;
 v_product:=(v_scan->>'product_id')::uuid;
 v_unit:=case when v_scan->>'serialized_unit_id' is not null then (v_scan->>'serialized_unit_id')::uuid end;
 if v_scan->>'location_id' is distinct from v_session.location_id::text then
  raise exception 'Scanned serialized unit is assigned to another location' using errcode='23514';
 end if;
 if v_unit is not null then
  update public.mme_cycle_count_lines set counted_quantity=1,count_confirmed=true,scan_count=scan_count+1,
   status='counted',last_scanned_by_identity_id=p_actor_identity_id,last_scanned_at=now(),updated_at=now()
  where session_id=p_session_id and product_id=v_product and serialized_unit_id=v_unit returning id into v_line;
 else
  update public.mme_cycle_count_lines set counted_quantity=counted_quantity+1,count_confirmed=true,scan_count=scan_count+1,
   status='counted',last_scanned_by_identity_id=p_actor_identity_id,last_scanned_at=now(),updated_at=now()
  where session_id=p_session_id and product_id=v_product and serialized_unit_id is null returning id into v_line;
 end if;
 if v_line is null then raise exception 'Item is not included in this cycle count' using errcode='P0002'; end if;
 select counted_quantity into v_count from public.mme_cycle_count_lines where id=v_line;
 insert into public.mme_cycle_count_events(session_id,line_id,event_type,event_data,actor_identity_id)
 values(p_session_id,v_line,'item_scanned',jsonb_build_object('scan_value',p_scan_value,'counted_quantity',v_count),p_actor_identity_id);
 return v_line;
end; $$;

comment on function public.mme_record_cycle_count_scan(uuid,text,uuid) is 'Records a physical scan and marks its count line explicitly confirmed; duplicate serialized scans remain capped at one.';
