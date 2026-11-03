-- Build 001: receiving reconciliation and exception gate before PO receipt posting.
create or replace view public.mme_receiving_po_reconciliation_v
with (security_invoker=true) as
with session_scan as (
 select s.session_id,s.product_id,
  sum(s.quantity) filter(where s.scan_result='matched')::bigint as matched_scanned_quantity,
  count(*) filter(where s.scan_result='unmatched')::bigint as unmatched_scan_count,
  count(*) filter(where s.scan_result='rejected')::bigint as rejected_scan_count,
  count(*) filter(where s.scan_result='duplicate')::bigint as duplicate_scan_count
 from public.mme_receiving_station_scans s
 group by s.session_id,s.product_id
), session_exception as (
 select session_id,
  count(*) filter(where scan_result='unmatched')::bigint as session_unmatched_scan_count,
  count(*) filter(where scan_result='rejected')::bigint as session_rejected_scan_count,
  count(*) filter(where scan_result='duplicate')::bigint as session_duplicate_scan_count
 from public.mme_receiving_station_scans group by session_id
)
select rs.id as session_id,rs.session_reference,rs.session_status,rs.location_id,
 po.id as purchase_order_id,po.po_number,pol.id as purchase_order_line_id,
 pol.product_id,p.sku,pol.description_snapshot,pol.ordered_quantity,pol.received_quantity,
 coalesce(ss.matched_scanned_quantity,0)::bigint as matched_scanned_quantity,
 greatest(pol.ordered_quantity-pol.received_quantity-coalesce(ss.matched_scanned_quantity,0),0)::bigint as remaining_after_session_if_completed,
 coalesce(ss.unmatched_scan_count,0)::bigint as line_unmatched_scan_count,
 coalesce(ss.rejected_scan_count,0)::bigint as line_rejected_scan_count,
 coalesce(ss.duplicate_scan_count,0)::bigint as line_duplicate_scan_count,
 coalesce(se.session_unmatched_scan_count,0)::bigint as session_unmatched_scan_count,
 coalesce(se.session_rejected_scan_count,0)::bigint as session_rejected_scan_count,
 coalesce(se.session_duplicate_scan_count,0)::bigint as session_duplicate_scan_count,
 case when coalesce(se.session_unmatched_scan_count,0)+coalesce(se.session_rejected_scan_count,0)+coalesce(se.session_duplicate_scan_count,0)>0 then 'exceptions_open'
  when coalesce(ss.matched_scanned_quantity,0)=0 then 'not_scanned'
  when pol.received_quantity+coalesce(ss.matched_scanned_quantity,0)>pol.ordered_quantity then 'overage'
  when pol.received_quantity+coalesce(ss.matched_scanned_quantity,0)<pol.ordered_quantity then 'partial'
  else 'reconciled' end as reconciliation_status
from public.mme_receiving_station_sessions rs
join public.mme_purchase_orders po on po.id=rs.purchase_order_id
join public.mme_purchase_order_lines pol on pol.purchase_order_id=po.id and pol.location_id=rs.location_id
join public.mme_products p on p.id=pol.product_id and p.serialized=false
left join session_scan ss on ss.session_id=rs.id and ss.product_id=pol.product_id
left join session_exception se on se.session_id=rs.id;

create or replace function public.mme_complete_receiving_station_session(
 p_session_id uuid,p_receipt_reference text,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_session record; v_lines jsonb; v_receipt uuid;
begin
 select * into v_session from public.mme_receiving_station_sessions where id=p_session_id for update;
 if not found or v_session.session_status<>'submitted' or v_session.purchase_order_id is null then
  raise exception 'Submitted PO-linked receiving session required' using errcode='P0001';
 end if;
 if p_actor_identity_id is null or p_approved_by_identity_id is null then
  raise exception 'Verified receiving approval required' using errcode='22023'; end if;
 if exists(select 1 from public.mme_receiving_station_scans
  where session_id=p_session_id and scan_result in ('unmatched','rejected','duplicate')) then
  raise exception 'Resolve all unmatched, rejected and duplicate scans before completing receipt' using errcode='23514';
 end if;
 if exists(
  select 1 from public.mme_receiving_station_scans s
  where s.session_id=p_session_id and s.scan_result='matched'
   and not exists(select 1 from public.mme_purchase_order_lines pl
    where pl.purchase_order_id=v_session.purchase_order_id
     and pl.product_id=s.product_id and pl.location_id=v_session.location_id)
   and not exists(select 1 from public.mme_serialized_units u
    where u.id=s.serialized_unit_id and u.product_id=s.product_id and u.location_id=v_session.location_id)
 ) then raise exception 'Scanned product is not on this PO at this receiving location' using errcode='23514'; end if;
 select jsonb_agg(jsonb_build_object('line_id',pl.id,'quantity',sum(s.quantity)) order by pl.id)
 into v_lines
 from public.mme_receiving_station_scans s
 join public.mme_purchase_order_lines pl on pl.purchase_order_id=v_session.purchase_order_id
 join public.mme_products p on p.id=pl.product_id and p.id=s.product_id
 where s.session_id=p_session_id and s.scan_result='matched'
  and p.serialized=false and pl.location_id=v_session.location_id
 group by pl.id;
 if v_lines is null then raise exception 'No aggregate PO lines scanned for receipt' using errcode='22023'; end if;
 v_receipt:=public.mme_receive_purchase_order_lines(v_session.purchase_order_id,p_receipt_reference,p_actor_identity_id,p_approved_by_identity_id,v_lines);
 update public.mme_receiving_station_sessions set session_status='completed',completed_by_identity_id=p_actor_identity_id,completed_at=now()
 where id=p_session_id and session_status='submitted';
 return v_receipt;
end; $$;

revoke all on public.mme_receiving_po_reconciliation_v from public,anon,authenticated;
grant select on public.mme_receiving_po_reconciliation_v to service_role;
revoke all on function public.mme_complete_receiving_station_session(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_complete_receiving_station_session(uuid,text,uuid,uuid) to service_role;
comment on view public.mme_receiving_po_reconciliation_v is 'PO-line receiving reconciliation per scanner session. Shows matched scan quantity, remaining quantity and session-wide exceptions. Overage and unresolved exception states require resolution before completion.';
