-- Build 001: require completed return inspections before refund approval.
create or replace function public.mme_guard_return_refund_inspection()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_case public.mme_return_cases%rowtype; v_count bigint; v_invalid bigint;
begin
 select * into v_case from public.mme_return_cases where id=new.return_case_id for update;
 if not found or v_case.status not in ('inspection_pending','partially_resolved','resolved') then
  raise exception 'Return must be received and under inspection before refund approval' using errcode='23514';
 end if;
 select count(*),count(*) filter(where rl.inspection_id is null or i.id is null
  or i.product_id<>rl.product_id or i.location_id<>rl.location_id
  or i.serialized_unit_id is distinct from rl.serialized_unit_id
  or i.inspection_type<>'customer_return' or i.disposition='pending')
 into v_count,v_invalid
 from public.mme_return_case_lines rl
 left join public.mme_inventory_inspections i on i.id=rl.inspection_id
 where rl.return_case_id=new.return_case_id and rl.return_status<>'rejected';
 if v_count=0 or v_invalid>0 then
  raise exception 'Every accepted return line requires a completed matching inspection before refund approval' using errcode='23514';
 end if;
 return new;
end; $$;

drop trigger if exists mme_return_refund_inspection_guard on public.mme_return_refund_approvals;
create trigger mme_return_refund_inspection_guard
before insert on public.mme_return_refund_approvals
for each row execute function public.mme_guard_return_refund_inspection();

create or replace function public.mme_finalize_return_line_inspection(
 p_return_line_id uuid,p_inspection_id uuid,p_resolution text,p_condition_after text,
 p_reason text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns boolean language plpgsql security definer set search_path='' as $$
declare v_line public.mme_return_case_lines%rowtype; v_case public.mme_return_cases%rowtype;
 v_inspection public.mme_inventory_inspections%rowtype; v_ok boolean; v_status text;
begin
 if p_return_line_id is null or p_inspection_id is null or p_actor_identity_id is null
  or p_approved_by_identity_id is null or p_actor_identity_id=p_approved_by_identity_id
  or p_resolution not in ('return_to_stock','repair','quarantine','write_off','return_to_supplier')
  or p_reason is null or length(btrim(p_reason))<5 then
  raise exception 'Invalid return inspection disposition' using errcode='22023';
 end if;
 select * into v_line from public.mme_return_case_lines where id=p_return_line_id for update;
 if not found or v_line.return_status<>'inspection_pending' then
  raise exception 'Return line is not awaiting inspection' using errcode='23514';
 end if;
 select * into v_case from public.mme_return_cases where id=v_line.return_case_id for update;
 if not found or v_case.status not in ('inspection_pending','partially_resolved') then
  raise exception 'Return case is not in inspection workflow' using errcode='23514';
 end if;
 select * into v_inspection from public.mme_inventory_inspections where id=p_inspection_id for update;
 if not found or v_inspection.product_id<>v_line.product_id or v_inspection.location_id<>v_line.location_id
  or v_inspection.serialized_unit_id is distinct from v_line.serialized_unit_id
  or v_inspection.inspection_type<>'customer_return' or v_inspection.disposition<>'pending' then
  raise exception 'Inspection does not match this return line or is already resolved' using errcode='23514';
 end if;
 if v_line.serialized_unit_id is not null then
  v_ok:=public.mme_resolve_serialized_inspection(p_inspection_id,p_resolution,p_condition_after,p_reason,p_actor_identity_id,p_approved_by_identity_id);
 else
  if p_resolution='repair' then
   raise exception 'Aggregate return repair must be handled by the repair workflow, not stock disposition' using errcode='22023';
  end if;
  v_ok:=public.mme_resolve_aggregate_inspection(p_inspection_id,p_resolution,p_condition_after,p_reason,p_actor_identity_id,p_approved_by_identity_id);
 end if;
 if not coalesce(v_ok,false) then raise exception 'Inspection resolution failed' using errcode='23514'; end if;
 v_status:=case p_resolution when 'return_to_stock' then 'restocked' when 'repair' then 'repair'
  when 'quarantine' then 'quarantine' when 'write_off' then 'write_off' when 'return_to_supplier' then 'quarantine' end;
 update public.mme_return_case_lines set inspection_id=p_inspection_id,return_status=v_status,updated_at=now()
 where id=p_return_line_id;
 update public.mme_return_cases rc set status=case
  when exists(select 1 from public.mme_return_case_lines x where x.return_case_id=rc.id and x.return_status in ('requested','authorized','received','inspection_pending')) then 'partially_resolved'
  else 'resolved' end,updated_at=now()
 where rc.id=v_case.id;
 return true;
end; $$;

revoke all on function public.mme_guard_return_refund_inspection() from public,anon,authenticated;
revoke all on function public.mme_finalize_return_line_inspection(uuid,uuid,text,text,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_finalize_return_line_inspection(uuid,uuid,text,text,text,uuid,uuid) to service_role;
comment on function public.mme_return_refund_approvals is 'Refund approvals are rejected until every accepted return line has a completed, matching customer-return inspection.';
