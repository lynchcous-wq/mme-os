-- Build 001: enforce independent purchase-order approval and reasoned rejection.
create or replace function public.mme_set_purchase_order_status(p_po_id uuid,p_action text,p_actor_identity_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_po public.mme_purchase_orders%rowtype; v_new text;
begin
 if p_po_id is null or p_actor_identity_id is null or p_action not in ('submit','approve','reject','issue','acknowledge','cancel') then raise exception 'Invalid PO transition' using errcode='22023'; end if;
 select * into v_po from public.mme_purchase_orders where id=p_po_id for update;
 if not found then return false; end if;
 v_new:=case p_action when 'submit' then 'submitted' when 'approve' then 'approved' when 'reject' then 'rejected' when 'issue' then 'issued' when 'acknowledge' then 'acknowledged' when 'cancel' then 'cancelled' end;
 if not ((v_po.status='draft' and p_action='submit') or (v_po.status='submitted' and p_action in ('approve','reject')) or (v_po.status='approved' and p_action='issue') or (v_po.status='issued' and p_action='acknowledge') or (v_po.status in ('draft','submitted','approved','issued','acknowledged','partially_received') and p_action='cancel')) then return false; end if;
 if p_action='approve' and p_actor_identity_id=v_po.created_by_identity_id then raise exception 'PO creator cannot approve own purchase order' using errcode='42501'; end if;
 if p_action='reject' and (p_note is null or length(btrim(p_note))<5) then raise exception 'Rejection reason is required' using errcode='22023'; end if;
 if p_action='cancel' and (p_note is null or length(btrim(p_note))<5) then raise exception 'Cancellation reason is required' using errcode='22023'; end if;
 update public.mme_purchase_orders set status=v_new,
  approved_by_identity_id=case when p_action='approve' then p_actor_identity_id else approved_by_identity_id end,
  approved_at=case when p_action='approve' then now() else approved_at end,
  issued_by_identity_id=case when p_action='issue' then p_actor_identity_id else issued_by_identity_id end,
  issued_at=case when p_action='issue' then now() else issued_at end,
  acknowledged_at=case when p_action='acknowledge' then now() else acknowledged_at end,
  decision_note=coalesce(left(btrim(p_note),1000),decision_note),updated_at=now() where id=p_po_id;
 insert into public.mme_purchase_order_events(purchase_order_id,event_type,event_data,actor_identity_id)
 values(p_po_id,p_action,jsonb_build_object('note',left(p_note,1000),'from',v_po.status,'to',v_new),p_actor_identity_id);
 return true;
end; $$;
revoke all on function public.mme_set_purchase_order_status(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_set_purchase_order_status(uuid,text,uuid,text) to service_role;
comment on function public.mme_set_purchase_order_status(uuid,text,uuid,text) is 'Enforces valid PO transitions, independent approval by a different identity, reasoned rejection/cancellation, and audit events. Trusted API must separately authenticate CEO-level purchasing permission.';