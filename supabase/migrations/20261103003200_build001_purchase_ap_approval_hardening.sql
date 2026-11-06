-- Build 001: close approval-path gaps in purchase budgets and AP schedule release.
-- Backend must still authenticate and authorize both identities before calling these RPCs.

create or replace function public.mme_guard_purchase_order_approval()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_policy public.mme_purchase_budget_policies%rowtype;
 v_location uuid; v_month_committed numeric;
begin
 if new.status='approved' and old.status is distinct from 'approved' then
  select distinct location_id into v_location from public.mme_purchase_order_lines
   where purchase_order_id=new.id;
  if v_location is null or exists(select 1 from public.mme_purchase_order_lines
    where purchase_order_id=new.id and location_id<>v_location) then
   raise exception 'Purchase order must target one location for budget approval' using errcode='23514';
  end if;
  select * into v_policy from public.mme_purchase_budget_policies
   where location_id=v_location and active=true and effective_from<=current_date
    and (effective_until is null or effective_until>=current_date)
   order by effective_from desc limit 1 for update;
  if not found then raise exception 'Active purchase budget policy required before approval' using errcode='23514'; end if;
  if new.total_cents>v_policy.max_purchase_order_cents then
   raise exception 'Purchase order exceeds location maximum' using errcode='23514';
  end if;
  select coalesce(sum(po.total_cents),0) into v_month_committed
   from public.mme_purchase_orders po
   join public.mme_purchase_order_lines pol on pol.purchase_order_id=po.id
   where pol.location_id=v_location and po.id<>new.id
    and po.status in ('approved','issued','acknowledged','partially_received','received')
    and po.created_at>=date_trunc('month',now());
  if v_month_committed+new.total_cents>v_policy.monthly_budget_cents then
   raise exception 'Purchase order exceeds remaining monthly budget' using errcode='23514';
  end if;
  if new.total_cents>=v_policy.approval_threshold_cents and
   (new.approved_by_identity_id is null or new.approved_by_identity_id=new.created_by_identity_id) then
   raise exception 'Independent approval identity required at configured spending threshold' using errcode='23514';
  end if;
 end if;
 return new;
end; $$;

create or replace function public.mme_approve_supplier_payment_schedule(
 p_schedule_id uuid,p_approver_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_schedule public.mme_supplier_payment_schedules%rowtype;
 v_invoice public.mme_supplier_invoices%rowtype; v_requested uuid;
begin
 if p_schedule_id is null or p_approver_identity_id is null then
  raise exception 'Invalid payment schedule approval' using errcode='22023';
 end if;
 select * into v_schedule from public.mme_supplier_payment_schedules
  where id=p_schedule_id for update;
 if not found or v_schedule.payment_status<>'draft' then return false; end if;
 select * into v_invoice from public.mme_supplier_invoices where id=v_schedule.invoice_id for update;
 if not found or v_invoice.match_status<>'matched' or not exists(
  select 1 from public.mme_supplier_invoice_approvals a
  where a.invoice_id=v_invoice.id and a.decision='approved'
 ) then raise exception 'Invoice must be matched and independently approved' using errcode='23514'; end if;
 select a.decided_by_identity_id into v_requested from public.mme_supplier_invoice_approvals a
 where a.invoice_id=v_invoice.id and a.decision='approved' limit 1;
 if p_approver_identity_id=v_schedule.created_by_identity_id
  or p_approver_identity_id=v_requested then
  raise exception 'Payment scheduler or invoice approver cannot approve payment release' using errcode='23514';
 end if;
 update public.mme_supplier_payment_schedules set payment_status='approved',
  approved_by_identity_id=p_approver_identity_id,approved_at=now(),updated_at=now()
 where id=p_schedule_id and payment_status='draft';
 return found;
end; $$;

revoke all on function public.mme_approve_supplier_payment_schedule(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_approve_supplier_payment_schedule(uuid,uuid) to service_role;
comment on function public.mme_approve_supplier_payment_schedule(uuid,uuid) is
 'Independent AP release approval; approver must differ from schedule creator and invoice approver.';
