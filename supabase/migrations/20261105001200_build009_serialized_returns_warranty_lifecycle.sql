-- Build 009.40 — Serialized returns, warranty and condition lifecycle bridge.
begin;

alter table public.mme_inventory_serial_cost_units
 drop constraint if exists mme_inventory_serial_cost_units_status_check;
alter table public.mme_inventory_serial_cost_units
 add constraint mme_inventory_serial_cost_units_status_check
 check(status in ('available','reserved','sold','repair','quarantined','written_off','returned_to_supplier','returned'));
alter table public.mme_inventory_serial_cost_events
 drop constraint if exists mme_inventory_serial_cost_events_event_type_check;
alter table public.mme_inventory_serial_cost_events
 add constraint mme_inventory_serial_cost_events_event_type_check
 check(event_type in ('received','reserved','released','sold','repair','quarantined','returned','written_off','returned_to_supplier'));

create table public.mme_serialized_return_policies(
 location_id uuid primary key references public.mme_store_locations(id) on delete restrict,
 enabled boolean not null default false,
 return_window_days integer not null check(return_window_days between 1 and 365),
 require_inspection boolean not null default true,
 require_manager_approval boolean not null default true,
 updated_by_identity_id uuid,
 updated_at timestamptz not null default now()
);
create table public.mme_serialized_return_requests(
 id uuid primary key default gen_random_uuid(),
 idempotency_key text not null unique,
 request_fingerprint text not null,
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 order_line_id uuid not null references public.mme_order_lines(id) on delete restrict,
 serialized_unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 customer_identity_id uuid not null,
 reason text not null check(length(btrim(reason)) between 5 and 1000),
 status text not null default 'requested'
  check(status in ('requested','inspection_pending','inspection_resolved','refund_pending','refunded','rejected','manual_review','closed')),
 inspection_id uuid unique references public.mme_inventory_inspections(id) on delete restrict,
 refund_status text not null default 'not_started'
  check(refund_status in ('not_started','pending_provider','confirmed','failed','manual_review')),
 refund_provider_reference text,
 refund_amount_cents bigint check(refund_amount_cents is null or refund_amount_cents>=0),
 requested_at timestamptz not null default now(),
 received_at timestamptz,
 resolved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index mme_serialized_return_one_open_per_line
 on public.mme_serialized_return_requests(order_line_id)
 where status in ('requested','inspection_pending','inspection_resolved','refund_pending');

create table public.mme_serialized_warranties(
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 order_line_id uuid not null unique references public.mme_order_lines(id) on delete restrict,
 serialized_unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 customer_identity_id uuid not null,
 provider_name text not null check(length(btrim(provider_name)) between 1 and 160),
 plan_name text not null check(length(btrim(plan_name)) between 1 and 160),
 terms_snapshot jsonb not null check(jsonb_typeof(terms_snapshot)='object'),
 provider_contract_reference text,
 starts_at timestamptz not null,
 expires_at timestamptz not null,
 status text not null default 'active' check(status in ('active','claim_pending','expired','void','fulfilled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(expires_at>starts_at)
);
create table public.mme_serialized_warranty_claims(
 id uuid primary key default gen_random_uuid(),
 warranty_id uuid not null references public.mme_serialized_warranties(id) on delete restrict,
 idempotency_key text not null unique,
 claim_reference text not null unique,
 request_fingerprint text not null,
 reason text not null check(length(btrim(reason)) between 5 and 1000),
 evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object'),
 status text not null default 'submitted'
  check(status in ('submitted','inspection_pending','inspection_resolved','approved','denied','manual_review','closed')),
 inspection_id uuid unique references public.mme_inventory_inspections(id) on delete restrict,
 submitted_at timestamptz not null default now(),
 resolved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create index mme_serialized_returns_customer_idx on public.mme_serialized_return_requests(customer_identity_id,requested_at desc);
create index mme_serialized_returns_status_idx on public.mme_serialized_return_requests(location_id,status,requested_at);
create index mme_serialized_warranties_customer_idx on public.mme_serialized_warranties(customer_identity_id,expires_at);
create index mme_serialized_warranty_claim_status_idx on public.mme_serialized_warranty_claims(status,submitted_at);

alter table public.mme_serialized_return_policies enable row level security;
alter table public.mme_serialized_return_requests enable row level security;
alter table public.mme_serialized_warranties enable row level security;
alter table public.mme_serialized_warranty_claims enable row level security;
revoke all on public.mme_serialized_return_policies,public.mme_serialized_return_requests,
 public.mme_serialized_warranties,public.mme_serialized_warranty_claims from public,anon,authenticated;
grant all on public.mme_serialized_return_policies,public.mme_serialized_return_requests,
 public.mme_serialized_warranties,public.mme_serialized_warranty_claims to service_role;

-- Synchronize the legacy Build 001 inspection workflow with the cost-bearing
-- serialized unit and aggregate stock ledger. A saleable return is counted
-- back into on-hand stock exactly once when inspection is resolved.
create or replace function public.mme_pos_sync_serialized_inspection_cost_ledger()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_unit public.mme_inventory_serial_cost_units%rowtype;
 v_balance public.mme_inventory_balances%rowtype;
 v_before integer; v_after integer; v_new_status text; v_event_type text;
begin
 if tg_op='INSERT' then
  if new.serialized_unit_id is null then return new; end if;
  select * into v_unit from public.mme_inventory_serial_cost_units
   where legacy_serialized_unit_id=new.serialized_unit_id for update;
  if not found then return new; end if;
  if v_unit.status not in ('available','sold') then
   raise exception 'Cost-ledger unit is not eligible for inspection' using errcode='23514';
  end if;
  if v_unit.status='available' then
   select * into v_balance from public.mme_inventory_balances
    where product_id=v_unit.product_id and location_id=v_unit.location_id for update;
   if not found or v_balance.on_hand_quantity-v_balance.reserved_quantity<1 then
    raise exception 'Available serialized unit has no unreserved aggregate stock' using errcode='23514';
   end if;
   v_before:=v_balance.on_hand_quantity; v_after:=v_before-1;
   update public.mme_inventory_balances set on_hand_quantity=v_after,updated_at=now() where id=v_balance.id;
   insert into public.mme_inventory_movements(product_id,location_id,movement_type,quantity_delta,
    on_hand_before,on_hand_after,reserved_before,reserved_after,unit_cost_cents,reason,reference_text,actor_identity_id,approved_by_identity_id)
   values(v_unit.product_id,v_unit.location_id,'adjustment_decrease',-1,v_before,v_after,
    v_balance.reserved_quantity,v_balance.reserved_quantity,v_unit.unit_cost_cents,
    'Serialized unit moved to inspection',new.inspection_reference,new.inspected_by_identity_id,new.approved_by_identity_id);
  end if;
  v_new_status:=case when new.disposition='repair' then 'repair' else 'quarantined' end;
  update public.mme_inventory_serial_cost_units set status=v_new_status,
   sold_order_id=null,reserved_order_id=null where id=v_unit.id;
  v_event_type:=case when v_new_status='repair' then 'repair' else 'quarantined' end;
  insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,actor_kind,order_id,event_data)
  values(v_unit.id,v_event_type,null,'system',null,jsonb_build_object(
   'inspection_id',new.id,'inspection_reference',new.inspection_reference,
   'prior_cost_status',v_unit.status,'prior_sold_order_id',v_unit.sold_order_id,
   'inspected_by_identity_id',new.inspected_by_identity_id));
  return new;
 end if;

 if tg_op='UPDATE' and old.disposition='pending'
  and new.disposition in ('return_to_stock','write_off','return_to_supplier')
  and new.serialized_unit_id is not null then
  select * into v_unit from public.mme_inventory_serial_cost_units
   where legacy_serialized_unit_id=new.serialized_unit_id for update;
  if not found then
   if new.disposition='return_to_stock' then
    raise exception 'Cost ledger match required before serialized unit can return to sellable stock' using errcode='23514';
   end if;
   return new;
  end if;
  if v_unit.status not in ('repair','quarantined') then
   raise exception 'Serialized cost unit is not held for inspection' using errcode='23514';
  end if;
  if new.disposition='return_to_stock' then
   if new.condition_after not in ('new','open_box','refurbished','used') then
    raise exception 'Return to stock requires a saleable condition grade' using errcode='23514';
   end if;
   select * into v_balance from public.mme_inventory_balances
    where product_id=v_unit.product_id and location_id=v_unit.location_id for update;
   if not found then
    insert into public.mme_inventory_balances(product_id,location_id,on_hand_quantity,reserved_quantity,average_unit_cost_cents)
    values(v_unit.product_id,v_unit.location_id,1,0,v_unit.unit_cost_cents);
    v_before:=0;v_after:=1;v_balance.reserved_quantity:=0;
   else
    v_before:=v_balance.on_hand_quantity;v_after:=v_before+1;
    update public.mme_inventory_balances set on_hand_quantity=v_after,
     average_unit_cost_cents=case when v_before=0 then v_unit.unit_cost_cents
      else round((v_before::numeric*average_unit_cost_cents+v_unit.unit_cost_cents)/(v_before+1))::bigint end,
     updated_at=now() where id=v_balance.id;
   end if;
   insert into public.mme_inventory_movements(product_id,location_id,movement_type,quantity_delta,
    on_hand_before,on_hand_after,reserved_before,reserved_after,unit_cost_cents,reason,reference_text,actor_identity_id,approved_by_identity_id)
   values(v_unit.product_id,v_unit.location_id,'adjustment_increase',1,v_before,v_after,
    coalesce(v_balance.reserved_quantity,0),coalesce(v_balance.reserved_quantity,0),v_unit.unit_cost_cents,
    'Serialized unit passed return inspection',new.inspection_reference,new.resolved_by_identity_id,new.approved_by_identity_id);
   update public.mme_inventory_serial_cost_units set status='available',sold_order_id=null,
    sold_at=null,reserved_order_id=null where id=v_unit.id;
   v_event_type:='returned';
  elsif new.disposition='write_off' then
   update public.mme_inventory_serial_cost_units set status='written_off',sold_order_id=null,
    reserved_order_id=null where id=v_unit.id;
   v_event_type:='written_off';
  else
   update public.mme_inventory_serial_cost_units set status='returned_to_supplier',sold_order_id=null,
    reserved_order_id=null where id=v_unit.id;
   v_event_type:='returned_to_supplier';
  end if;
  insert into public.mme_inventory_serial_cost_events(serial_unit_id,event_type,actor_person_id,actor_kind,order_id,event_data)
  values(v_unit.id,v_event_type,null,'system',null,jsonb_build_object(
   'inspection_id',new.id,'inspection_reference',new.inspection_reference,
   'resolution',new.disposition,'condition_after',new.condition_after,
   'resolved_by_identity_id',new.resolved_by_identity_id,
   'approved_by_identity_id',new.approved_by_identity_id));
  update public.mme_serialized_return_requests set status='inspection_resolved',
   resolved_at=now(),updated_at=now() where inspection_id=new.id and status='inspection_pending';
  update public.mme_serialized_warranty_claims set status='inspection_resolved',
   resolved_at=now(),updated_at=now() where inspection_id=new.id and status='inspection_pending';
 end if;
 return new;
end;
$$;
drop trigger if exists mme_pos_sync_serialized_inspection_cost_ledger on public.mme_inventory_inspections;
create trigger mme_pos_sync_serialized_inspection_cost_ledger
after insert or update of disposition on public.mme_inventory_inspections
for each row execute function public.mme_pos_sync_serialized_inspection_cost_ledger();

create or replace function public.mme_pos_request_serialized_return(
 p_order_line_id uuid,p_customer_identity_id uuid,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_line public.mme_order_lines%rowtype; v_order public.mme_orders%rowtype;
 v_policy public.mme_serialized_return_policies%rowtype; v_unit public.mme_serialized_units%rowtype;
 v_existing public.mme_serialized_return_requests%rowtype; v_id uuid; v_fp text;
begin
 if p_order_line_id is null or p_customer_identity_id is null
  or p_reason is null or length(btrim(p_reason)) not between 5 and 1000
  or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 or length(p_idempotency_key)>128 then
  raise exception 'Invalid serialized return request' using errcode='22023';
 end if;
 select * into v_line from public.mme_order_lines where id=p_order_line_id for update;
 if not found or v_line.serialized_unit_id is null then raise exception 'Serialized order line not found' using errcode='P0002'; end if;
 select * into v_order from public.mme_orders where id=v_line.order_id for update;
 if not found or v_order.status not in ('paid','partially_refunded') or v_order.customer_identity_id<>p_customer_identity_id
  or v_order.paid_at is null then raise exception 'Customer is not eligible to return this paid order' using errcode='42501'; end if;
 v_fp:=encode(digest(jsonb_build_object('order_line_id',p_order_line_id,'customer_identity_id',p_customer_identity_id,'reason',btrim(p_reason))::text,'sha256'),'hex');
 select * into v_existing from public.mme_serialized_return_requests where idempotency_key=p_idempotency_key for update;
 if found then
  if v_existing.request_fingerprint<>v_fp then raise exception 'Return idempotency key reused with different request' using errcode='23505'; end if;
  return v_existing.id;
 end if;
 select * into v_policy from public.mme_serialized_return_policies
  where location_id=v_line.location_id and enabled=true;
 if not found then raise exception 'Serialized return policy is not configured for this store' using errcode='55000'; end if;
 if now()>v_order.paid_at+(v_policy.return_window_days||' days')::interval then
  raise exception 'Serialized return window has expired' using errcode='23514';
 end if;
 select * into v_unit from public.mme_serialized_units where id=v_line.serialized_unit_id for update;
 if not found or v_unit.unit_status<>'sold' then raise exception 'Serialized unit is not currently eligible for return intake' using errcode='23514'; end if;
 insert into public.mme_serialized_return_requests(idempotency_key,request_fingerprint,order_id,order_line_id,
  serialized_unit_id,location_id,customer_identity_id,reason)
 values(p_idempotency_key,v_fp,v_order.id,v_line.id,v_line.serialized_unit_id,v_line.location_id,p_customer_identity_id,btrim(p_reason))
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_receive_serialized_return(
 p_return_id uuid,p_actor_user_id uuid,p_actor_identity_id uuid,p_reference text,
 p_reason text,p_findings jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_return public.mme_serialized_return_requests%rowtype; v_inspection_id uuid;
begin
 select * into v_return from public.mme_serialized_return_requests where id=p_return_id for update;
 if not found or v_return.status<>'requested' then raise exception 'Return request is not awaiting intake' using errcode='23514'; end if;
 if not public.mme_employee_authorize_inventory_action(p_actor_user_id,'inventory.inspection.submit',
  (select product_id from public.mme_order_lines where id=v_return.order_line_id),v_return.location_id) then
  raise exception 'Employee is not authorized to receive this return' using errcode='42501';
 end if;
 v_inspection_id:=public.mme_submit_serialized_inspection(
  p_reference,v_return.serialized_unit_id,'customer_return',p_reason,p_findings,
  null,'not_applicable','not_applicable','not_applicable','not_applicable','not_applicable',
  'not_applicable','not_applicable','not_applicable',left(p_reason,4000),p_actor_user_id,p_actor_identity_id
 );
 update public.mme_serialized_return_requests set status='inspection_pending',
  inspection_id=v_inspection_id,received_at=now(),updated_at=now() where id=v_return.id;
 return v_inspection_id;
end;
$$;

create or replace function public.mme_pos_resolve_serialized_return(
 p_return_id uuid,p_actor_user_id uuid,p_actor_identity_id uuid,
 p_approver_user_id uuid,p_approver_identity_id uuid,
 p_resolution text,p_condition_after text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_return public.mme_serialized_return_requests%rowtype; v_product_id uuid;
begin
 select * into v_return from public.mme_serialized_return_requests where id=p_return_id for update;
 if not found or v_return.status<>'inspection_pending' or v_return.inspection_id is null then
  raise exception 'Return inspection is not awaiting resolution' using errcode='23514';
 end if;
 select product_id into v_product_id from public.mme_order_lines where id=v_return.order_line_id;
 if p_actor_user_id=p_approver_user_id or p_actor_identity_id=p_approver_identity_id
  or not public.mme_employee_authorize_inventory_action(p_actor_user_id,'inventory.inspection.resolve',v_product_id,v_return.location_id)
  or not public.mme_employee_authorize_inventory_action(p_approver_user_id,'inventory.inspection.approve',v_product_id,v_return.location_id) then
  raise exception 'Return resolution requires separate authorized resolver and approver' using errcode='42501';
 end if;
 return public.mme_resolve_serialized_inspection(v_return.inspection_id,p_resolution,p_condition_after,
  p_reason,p_actor_identity_id,p_approver_identity_id);
end;
$$;

create or replace function public.mme_pos_register_serialized_warranty(
 p_order_line_id uuid,p_customer_identity_id uuid,p_provider_name text,p_plan_name text,
 p_terms_snapshot jsonb,p_provider_contract_reference text,p_expires_at timestamptz
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_line public.mme_order_lines%rowtype; v_order public.mme_orders%rowtype;
 v_unit public.mme_serialized_units%rowtype; v_id uuid;
begin
 if p_order_line_id is null or p_customer_identity_id is null
  or p_provider_name is null or length(btrim(p_provider_name)) not between 1 and 160
  or p_plan_name is null or length(btrim(p_plan_name)) not between 1 and 160
  or p_terms_snapshot is null or jsonb_typeof(p_terms_snapshot)<>'object'
  or p_expires_at is null then raise exception 'Invalid warranty registration' using errcode='22023'; end if;
 select * into v_line from public.mme_order_lines where id=p_order_line_id;
 if not found or v_line.serialized_unit_id is null then raise exception 'Serialized order line not found' using errcode='P0002'; end if;
 select * into v_order from public.mme_orders where id=v_line.order_id;
 if not found or v_order.status not in ('paid','partially_refunded') or v_order.customer_identity_id<>p_customer_identity_id
  or v_order.paid_at is null then raise exception 'Warranty registration requires the purchasing customer and paid order' using errcode='42501'; end if;
 select * into v_unit from public.mme_serialized_units where id=v_line.serialized_unit_id;
 if not found or v_unit.unit_status<>'sold' then raise exception 'Serialized unit must be sold before warranty registration' using errcode='23514'; end if;
 if p_expires_at<=v_order.paid_at then raise exception 'Warranty expiry must follow the sale date' using errcode='22023'; end if;
 insert into public.mme_serialized_warranties(order_id,order_line_id,serialized_unit_id,customer_identity_id,
  provider_name,plan_name,terms_snapshot,provider_contract_reference,starts_at,expires_at)
 values(v_order.id,v_line.id,v_unit.id,p_customer_identity_id,btrim(p_provider_name),btrim(p_plan_name),
  p_terms_snapshot,p_provider_contract_reference,v_order.paid_at,p_expires_at)
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_submit_serialized_warranty_claim(
 p_warranty_id uuid,p_customer_identity_id uuid,p_claim_reference text,p_idempotency_key text,
 p_reason text,p_evidence jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_warranty public.mme_serialized_warranties%rowtype; v_id uuid; v_fp text; v_existing public.mme_serialized_warranty_claims%rowtype;
begin
 if p_warranty_id is null or p_customer_identity_id is null
  or p_claim_reference is null or length(btrim(p_claim_reference)) not between 3 and 100
  or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 or length(p_idempotency_key)>128
  or p_reason is null or length(btrim(p_reason)) not between 5 and 1000
  or p_evidence is null or jsonb_typeof(p_evidence)<>'object' then
  raise exception 'Invalid serialized warranty claim' using errcode='22023';
 end if;
 select * into v_warranty from public.mme_serialized_warranties where id=p_warranty_id for update;
 if not found or v_warranty.customer_identity_id<>p_customer_identity_id then
  raise exception 'Warranty is not registered to this customer' using errcode='42501';
 end if;
 v_fp:=encode(digest(jsonb_build_object('warranty_id',p_warranty_id,'customer_identity_id',p_customer_identity_id,
  'claim_reference',btrim(p_claim_reference),'reason',btrim(p_reason),'evidence',p_evidence)::text,'sha256'),'hex');
 select * into v_existing from public.mme_serialized_warranty_claims where idempotency_key=p_idempotency_key for update;
 if found then
  if v_existing.request_fingerprint<>v_fp then raise exception 'Warranty claim idempotency key reused with different request' using errcode='23505'; end if;
  return v_existing.id;
 end if;
 if v_warranty.status not in ('active','claim_pending') or now()>v_warranty.expires_at then
  raise exception 'Warranty is not active for a new claim' using errcode='23514';
 end if;
 insert into public.mme_serialized_warranty_claims(warranty_id,idempotency_key,claim_reference,request_fingerprint,reason,evidence)
 values(v_warranty.id,p_idempotency_key,btrim(p_claim_reference),v_fp,btrim(p_reason),p_evidence)
 returning id into v_id;
 update public.mme_serialized_warranties set status='claim_pending',updated_at=now() where id=v_warranty.id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_receive_serialized_warranty_claim(
 p_claim_id uuid,p_actor_user_id uuid,p_actor_identity_id uuid,p_reference text,
 p_reason text,p_findings jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_claim public.mme_serialized_warranty_claims%rowtype; v_warranty public.mme_serialized_warranties%rowtype;
 v_inspection_id uuid; v_location_id uuid; v_product_id uuid;
begin
 select * into v_claim from public.mme_serialized_warranty_claims where id=p_claim_id for update;
 if not found or v_claim.status<>'submitted' then raise exception 'Warranty claim is not awaiting intake' using errcode='23514'; end if;
 select * into v_warranty from public.mme_serialized_warranties where id=v_claim.warranty_id;
 select location_id,product_id into v_location_id,v_product_id from public.mme_serialized_units where id=v_warranty.serialized_unit_id;
 if not public.mme_employee_authorize_inventory_action(p_actor_user_id,'inventory.inspection.submit',v_product_id,v_location_id) then
  raise exception 'Employee is not authorized to receive warranty inspection' using errcode='42501';
 end if;
 v_inspection_id:=public.mme_submit_serialized_inspection(
  p_reference,v_warranty.serialized_unit_id,'warranty_return',p_reason,p_findings,
  null,'not_applicable','not_applicable','not_applicable','not_applicable','not_applicable',
  'not_applicable','not_applicable','not_applicable',left(p_reason,4000),p_actor_user_id,p_actor_identity_id
 );
 update public.mme_serialized_warranty_claims set status='inspection_pending',
  inspection_id=v_inspection_id,updated_at=now() where id=v_claim.id;
 return v_inspection_id;
end;
$$;

revoke all on function public.mme_pos_sync_serialized_inspection_cost_ledger() from public,anon,authenticated;
revoke all on function public.mme_pos_request_serialized_return(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_receive_serialized_return(uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_pos_resolve_serialized_return(uuid,uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_register_serialized_warranty(uuid,uuid,text,text,jsonb,text,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_pos_submit_serialized_warranty_claim(uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_pos_receive_serialized_warranty_claim(uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mme_pos_request_serialized_return(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_pos_receive_serialized_return(uuid,uuid,uuid,text,text,jsonb) to service_role;
grant execute on function public.mme_pos_resolve_serialized_return(uuid,uuid,uuid,uuid,uuid,text,text,text) to service_role;
grant execute on function public.mme_pos_register_serialized_warranty(uuid,uuid,text,text,jsonb,text,timestamptz) to service_role;
grant execute on function public.mme_pos_submit_serialized_warranty_claim(uuid,uuid,text,text,text,jsonb) to service_role;
grant execute on function public.mme_pos_receive_serialized_warranty_claim(uuid,uuid,uuid,text,text,jsonb) to service_role;

comment on table public.mme_serialized_return_requests is
 'Customer serialized return intake and inspection workflow. Refunds remain pending until a separately verified provider refund outcome is recorded.';
comment on table public.mme_serialized_warranties is
 'Sale-linked warranty registration with the exact provider terms and dates supplied at registration; no warranty term is assumed.';
comment on function public.mme_pos_sync_serialized_inspection_cost_ledger() is
 'Synchronizes Build 001 serialized inspection/disposition transitions with Build 009.38 unit costs and aggregate inventory balances.';

commit;
