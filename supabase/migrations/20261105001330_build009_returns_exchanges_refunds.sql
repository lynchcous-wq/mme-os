-- Build 009.53 — governed returns, exchanges, inspection, disposition and refund workflow.
begin;

create table public.mme_return_cases (
 return_case_id uuid primary key default gen_random_uuid(),
 service_request_id uuid not null unique references public.mme_customer_order_service_requests(request_id) on delete restrict,
 order_id uuid not null references public.mme_customer_order_portal(order_id) on delete restrict,
 person_id uuid not null,
 case_status text not null default 'submitted' check(case_status in ('submitted','eligibility_review','approved','rejected','awaiting_item','received','inspection_in_progress','inspection_complete','refund_pending_approval','refund_approved','refund_processing','refund_completed','exchange_pending','exchange_completed','closed')),
 eligibility_result text not null default 'pending' check(eligibility_result in ('pending','eligible','ineligible','exception_required')),
 eligibility_reason text,
 received_at timestamptz,
 opened_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 closed_at timestamptz,
 unique(return_case_id,order_id,person_id)
);
create index mme_return_cases_queue_idx on public.mme_return_cases(case_status,opened_at);
create index mme_return_cases_person_idx on public.mme_return_cases(person_id,opened_at desc);

create table public.mme_return_case_items (
 return_item_id uuid primary key default gen_random_uuid(),
 return_case_id uuid not null references public.mme_return_cases(return_case_id) on delete restrict,
 order_id uuid not null,
 person_id uuid not null,
 item_reference text not null,
 product_name_snapshot text not null,
 serial_or_imei_reference text,
 quantity integer not null default 1 check(quantity between 1 and 100),
 item_status text not null default 'requested' check(item_status in ('requested','authorized','received','inspection_in_progress','inspection_complete','accepted','rejected','exchanged','refunded','restocked','quarantined','disposed')),
 condition_grade text check(condition_grade in ('A','B','C','D','non_resellable')),
 disposition text check(disposition in ('restock_new','restock_open_box','refurbishment','parts_recovery','vendor_return','quarantine','secure_disposal')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(return_case_id,order_id,person_id) references public.mme_return_cases(return_case_id,order_id,person_id) on delete restrict
);
create index mme_return_case_items_case_idx on public.mme_return_case_items(return_case_id,item_status);

create table public.mme_return_inspections (
 inspection_id uuid primary key default gen_random_uuid(),
 return_item_id uuid not null references public.mme_return_case_items(return_item_id) on delete restrict,
 inspector_user_id uuid not null,
 inspection_status text not null default 'in_progress' check(inspection_status in ('in_progress','passed','failed','needs_manager_review')),
 checklist jsonb not null default '{}'::jsonb check(jsonb_typeof(checklist)='object'),
 defect_notes text,
 accessory_completeness text check(accessory_completeness in ('complete','incomplete','unknown')),
 activation_lock_status text check(activation_lock_status in ('clear','locked','unknown','not_applicable')),
 serial_match boolean,
 battery_health_percent smallint check(battery_health_percent between 0 and 100),
 screen_status text check(screen_status in ('pass','fail','not_applicable')),
 ports_status text check(ports_status in ('pass','fail','not_applicable')),
 camera_status text check(camera_status in ('pass','fail','not_applicable')),
 inspected_at timestamptz,
 created_at timestamptz not null default now()
);
create index mme_return_inspections_item_idx on public.mme_return_inspections(return_item_id,created_at desc);

create table public.mme_return_evidence (
 evidence_id uuid primary key default gen_random_uuid(),
 return_case_id uuid not null references public.mme_return_cases(return_case_id) on delete restrict,
 return_item_id uuid references public.mme_return_case_items(return_item_id) on delete restrict,
 storage_object_path text not null,
 evidence_type text not null check(evidence_type in ('customer_photo','received_condition','serial_label','inspection_photo','packing_photo','other')),
 uploaded_by uuid not null,
 created_at timestamptz not null default now(),
 unique(storage_object_path)
);

create table public.mme_return_refund_decisions (
 refund_decision_id uuid primary key default gen_random_uuid(),
 return_case_id uuid not null references public.mme_return_cases(return_case_id) on delete restrict,
 order_id uuid not null references public.mme_customer_order_portal(order_id) on delete restrict,
 amount numeric(14,2) not null check(amount>0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 decision_status text not null default 'pending' check(decision_status in ('pending','approved','rejected','submitted_to_processor','succeeded','failed','cancelled')),
 requested_by uuid not null,
 approved_by uuid,
 approved_at timestamptz,
 processor_reference text,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>requested_by),
 check(decision_status not in ('approved','submitted_to_processor','succeeded') or approved_by is not null)
);
create index mme_return_refund_decisions_case_idx on public.mme_return_refund_decisions(return_case_id,created_at desc);

create table public.mme_return_exchanges (
 exchange_id uuid primary key default gen_random_uuid(),
 return_case_id uuid not null references public.mme_return_cases(return_case_id) on delete restrict,
 returned_item_id uuid not null references public.mme_return_case_items(return_item_id) on delete restrict,
 replacement_order_reference text,
 replacement_item_reference text not null,
 exchange_status text not null default 'pending' check(exchange_status in ('pending','approved','reserved','fulfilled','cancelled')),
 price_difference numeric(14,2) not null default 0,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 created_by uuid not null,
 approved_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>created_by)
);
create index mme_return_exchanges_case_idx on public.mme_return_exchanges(return_case_id,exchange_status);

create table public.mme_return_audit_events (
 audit_event_id bigint generated always as identity primary key,
 return_case_id uuid not null references public.mme_return_cases(return_case_id) on delete restrict,
 return_item_id uuid references public.mme_return_case_items(return_item_id) on delete restrict,
 actor_user_id uuid not null,
 action text not null,
 previous_state jsonb not null default '{}'::jsonb,
 new_state jsonb not null default '{}'::jsonb,
 reason text,
 created_at timestamptz not null default now()
);
create index mme_return_audit_case_idx on public.mme_return_audit_events(return_case_id,audit_event_id);

alter table public.mme_return_cases enable row level security;
alter table public.mme_return_case_items enable row level security;
alter table public.mme_return_inspections enable row level security;
alter table public.mme_return_evidence enable row level security;
alter table public.mme_return_refund_decisions enable row level security;
alter table public.mme_return_exchanges enable row level security;
alter table public.mme_return_audit_events enable row level security;

revoke all on public.mme_return_cases,public.mme_return_case_items,public.mme_return_inspections,
 public.mme_return_evidence,public.mme_return_refund_decisions,public.mme_return_exchanges,
 public.mme_return_audit_events from public,anon,authenticated;
grant select on public.mme_return_cases,public.mme_return_case_items,public.mme_return_refund_decisions,
 public.mme_return_exchanges to authenticated;
grant select,insert,update on public.mme_return_cases,public.mme_return_case_items,
 public.mme_return_inspections,public.mme_return_evidence,public.mme_return_refund_decisions,
 public.mme_return_exchanges to service_role;
grant select,insert on public.mme_return_audit_events to service_role;
revoke update,delete,truncate on public.mme_return_audit_events from public,anon,authenticated,service_role;

create policy mme_return_case_customer_read on public.mme_return_cases for select to authenticated
 using(exists(select 1 from public.mme_customer_account_links l where l.auth_user_id=auth.uid()
  and l.person_id=mme_return_cases.person_id and l.link_status='active'));
create policy mme_return_item_customer_read on public.mme_return_case_items for select to authenticated
 using(exists(select 1 from public.mme_return_cases c join public.mme_customer_account_links l
  on l.person_id=c.person_id where c.return_case_id=mme_return_case_items.return_case_id
  and l.auth_user_id=auth.uid() and l.link_status='active'));
create policy mme_return_refund_customer_read on public.mme_return_refund_decisions for select to authenticated
 using(exists(select 1 from public.mme_return_cases c join public.mme_customer_account_links l
  on l.person_id=c.person_id where c.return_case_id=mme_return_refund_decisions.return_case_id
  and l.auth_user_id=auth.uid() and l.link_status='active'));
create policy mme_return_exchange_customer_read on public.mme_return_exchanges for select to authenticated
 using(exists(select 1 from public.mme_return_cases c join public.mme_customer_account_links l
  on l.person_id=c.person_id where c.return_case_id=mme_return_exchanges.return_case_id
  and l.auth_user_id=auth.uid() and l.link_status='active'));

create or replace function public.mme_return_case_open_from_customer_request(
 p_service_request_id uuid,p_actor_user_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_req public.mme_customer_order_service_requests%rowtype; v_id uuid;
begin
 if p_service_request_id is null or p_actor_user_id is null then raise exception 'Request and actor required' using errcode='22023'; end if;
 select * into v_req from public.mme_customer_order_service_requests where request_id=p_service_request_id for update;
 if not found or v_req.request_type<>'return' then raise exception 'Eligible return request not found' using errcode='P0002'; end if;
 insert into public.mme_return_cases(service_request_id,order_id,person_id)
 values(v_req.request_id,v_req.order_id,v_req.person_id)
 on conflict(service_request_id) do update set service_request_id=excluded.service_request_id
 returning return_case_id into v_id;
 insert into public.mme_return_audit_events(return_case_id,actor_user_id,action,new_state)
 values(v_id,p_actor_user_id,'case_opened',jsonb_build_object('service_request_id',v_req.request_id));
 return v_id;
end;
$$;

create or replace function public.mme_return_case_set_eligibility(
 p_return_case_id uuid,p_result text,p_reason text,p_actor_user_id uuid
) returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_old public.mme_return_cases%rowtype;
begin
 if p_result not in ('eligible','ineligible','exception_required') or p_actor_user_id is null then
  raise exception 'Invalid eligibility decision' using errcode='22023'; end if;
 select * into v_old from public.mme_return_cases where return_case_id=p_return_case_id for update;
 if not found then raise exception 'Return case not found' using errcode='P0002'; end if;
 update public.mme_return_cases set eligibility_result=p_result,eligibility_reason=left(p_reason,1000),
  case_status=case when p_result='eligible' then 'approved' when p_result='ineligible' then 'rejected' else 'eligibility_review' end,
  updated_at=now() where return_case_id=p_return_case_id;
 update public.mme_customer_order_service_requests set request_status=case when p_result='eligible' then 'approved' when p_result='ineligible' then 'rejected' else 'under_review' end,updated_at=now()
 where request_id=v_old.service_request_id;
 insert into public.mme_return_audit_events(return_case_id,actor_user_id,action,previous_state,new_state,reason)
 values(p_return_case_id,p_actor_user_id,'eligibility_decided',jsonb_build_object('result',v_old.eligibility_result),
  jsonb_build_object('result',p_result),left(p_reason,1000));
end;
$$;

create or replace function public.mme_return_item_record_inspection(
 p_return_item_id uuid,p_inspector_user_id uuid,p_checklist jsonb,p_defect_notes text,
 p_accessory_completeness text,p_activation_lock_status text,p_serial_match boolean,
 p_battery_health_percent smallint,p_screen_status text,p_ports_status text,p_camera_status text,
 p_condition_grade text,p_disposition text,p_inspection_status text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_item public.mme_return_case_items%rowtype; v_id uuid;
begin
 if p_inspector_user_id is null or p_checklist is null or jsonb_typeof(p_checklist)<>'object'
  or p_condition_grade not in ('A','B','C','D','non_resellable')
  or p_disposition not in ('restock_new','restock_open_box','refurbishment','parts_recovery','vendor_return','quarantine','secure_disposal')
  or p_inspection_status not in ('passed','failed','needs_manager_review') then
  raise exception 'Invalid return inspection' using errcode='22023'; end if;
 select * into v_item from public.mme_return_case_items where return_item_id=p_return_item_id for update;
 if not found then raise exception 'Return item not found' using errcode='P0002'; end if;
 if p_condition_grade='non_resellable' and p_disposition in ('restock_new','restock_open_box') then
  raise exception 'Non-resellable item cannot be restocked' using errcode='55000'; end if;
 if (p_serial_match is false or p_activation_lock_status='locked') and p_disposition in ('restock_new','restock_open_box') then
  raise exception 'Serial mismatch or activation lock prevents restocking' using errcode='55000'; end if;
 insert into public.mme_return_inspections(return_item_id,inspector_user_id,inspection_status,checklist,
  defect_notes,accessory_completeness,activation_lock_status,serial_match,battery_health_percent,
  screen_status,ports_status,camera_status,inspected_at)
 values(p_return_item_id,p_inspector_user_id,p_inspection_status,p_checklist,left(p_defect_notes,4000),
  p_accessory_completeness,p_activation_lock_status,p_serial_match,p_battery_health_percent,
  p_screen_status,p_ports_status,p_camera_status,now()) returning inspection_id into v_id;
 update public.mme_return_case_items set item_status='inspection_complete',condition_grade=p_condition_grade,
  disposition=p_disposition,updated_at=now() where return_item_id=p_return_item_id;
 insert into public.mme_return_audit_events(return_case_id,return_item_id,actor_user_id,action,new_state)
 values(v_item.return_case_id,p_return_item_id,p_inspector_user_id,'item_inspected',
  jsonb_build_object('grade',p_condition_grade,'disposition',p_disposition,'inspection_status',p_inspection_status));
 return v_id;
end;
$$;

create or replace function public.mme_return_refund_request(
 p_return_case_id uuid,p_amount numeric,p_currency_code text,p_requested_by uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_case public.mme_return_cases%rowtype; v_id uuid;
begin
 if p_amount is null or p_amount<=0 or p_currency_code !~ '^[A-Z]{3}$' or p_requested_by is null
  or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180 then
  raise exception 'Invalid refund request' using errcode='22023'; end if;
 select * into v_case from public.mme_return_cases where return_case_id=p_return_case_id for update;
 if not found or v_case.eligibility_result<>'eligible' then raise exception 'Eligible return case required' using errcode='55000'; end if;
 if exists(select 1 from public.mme_return_case_items where return_case_id=p_return_case_id
  and item_status not in ('accepted','rejected','exchanged','refunded','restocked','quarantined','disposed')) then
  raise exception 'All returned items require completed inspection' using errcode='55000'; end if;
 insert into public.mme_return_refund_decisions(return_case_id,order_id,amount,currency_code,requested_by,idempotency_key)
 values(p_return_case_id,v_case.order_id,p_amount,p_currency_code,p_requested_by,p_idempotency_key)
 on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key
 returning refund_decision_id into v_id;
 update public.mme_return_cases set case_status='refund_pending_approval',updated_at=now() where return_case_id=p_return_case_id;
 insert into public.mme_return_audit_events(return_case_id,actor_user_id,action,new_state)
 values(p_return_case_id,p_requested_by,'refund_requested',jsonb_build_object('refund_decision_id',v_id,'amount',p_amount,'currency',p_currency_code));
 return v_id;
end;
$$;

create or replace function public.mme_return_refund_decide(
 p_refund_decision_id uuid,p_approver_user_id uuid,p_approve boolean,p_reason text
) returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_refund public.mme_return_refund_decisions%rowtype;
begin
 select * into v_refund from public.mme_return_refund_decisions where refund_decision_id=p_refund_decision_id for update;
 if not found then raise exception 'Refund decision not found' using errcode='P0002'; end if;
 if p_approver_user_id is null or p_approver_user_id=v_refund.requested_by then
  raise exception 'Independent refund approver required' using errcode='42501'; end if;
 if v_refund.decision_status<>'pending' then raise exception 'Refund decision already finalized' using errcode='55000'; end if;
 update public.mme_return_refund_decisions set decision_status=case when p_approve then 'approved' else 'rejected' end,
  approved_by=case when p_approve then p_approver_user_id else null end,
  approved_at=case when p_approve then now() else null end,updated_at=now()
 where refund_decision_id=p_refund_decision_id;
 update public.mme_return_cases set case_status=case when p_approve then 'refund_approved' else 'inspection_complete' end,
  updated_at=now() where return_case_id=v_refund.return_case_id;
 insert into public.mme_return_audit_events(return_case_id,actor_user_id,action,previous_state,new_state,reason)
 values(v_refund.return_case_id,p_approver_user_id,'refund_decided',
  jsonb_build_object('status',v_refund.decision_status),
  jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end),left(p_reason,1000));
end;
$$;

create or replace function public.mme_return_refund_mark_processor_result(
 p_refund_decision_id uuid,p_processor_reference text,p_succeeded boolean,p_actor_user_id uuid
) returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_refund public.mme_return_refund_decisions%rowtype;
begin
 select * into v_refund from public.mme_return_refund_decisions where refund_decision_id=p_refund_decision_id for update;
 if not found or v_refund.decision_status<>'approved' then raise exception 'Approved refund required' using errcode='55000'; end if;
 if p_processor_reference is null or length(p_processor_reference)>200 or p_actor_user_id is null then
  raise exception 'Processor reference and actor required' using errcode='22023'; end if;
 update public.mme_return_refund_decisions set decision_status=case when p_succeeded then 'succeeded' else 'failed' end,
  processor_reference=p_processor_reference,updated_at=now() where refund_decision_id=p_refund_decision_id;
 update public.mme_return_cases set case_status=case when p_succeeded then 'refund_completed' else 'refund_approved' end,
  updated_at=now() where return_case_id=v_refund.return_case_id;
 insert into public.mme_return_audit_events(return_case_id,actor_user_id,action,new_state)
 values(v_refund.return_case_id,p_actor_user_id,'refund_processor_result',
  jsonb_build_object('status',case when p_succeeded then 'succeeded' else 'failed' end,
   'processor_reference',p_processor_reference));
end;
$$;

create or replace function public.mme_return_case_set_item_disposition(
 p_return_item_id uuid,p_item_status text,p_disposition text,p_actor_user_id uuid
) returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_item public.mme_return_case_items%rowtype;
begin
 select * into v_item from public.mme_return_case_items where return_item_id=p_return_item_id for update;
 if not found or p_actor_user_id is null then raise exception 'Return item and actor required' using errcode='P0002'; end if;
 if p_item_status not in ('accepted','rejected','exchanged','refunded','restocked','quarantined','disposed')
  or p_disposition not in ('restock_new','restock_open_box','refurbishment','parts_recovery','vendor_return','quarantine','secure_disposal') then
  raise exception 'Invalid item disposition' using errcode='22023'; end if;
 if p_disposition in ('restock_new','restock_open_box') and
  (v_item.condition_grade not in ('A','B') or exists(select 1 from public.mme_return_inspections i
   where i.return_item_id=p_return_item_id and (i.serial_match is false or i.activation_lock_status='locked'
    or i.inspection_status<>'passed'))) then
  raise exception 'Item has not passed restock safety gates' using errcode='55000'; end if;
 update public.mme_return_case_items set item_status=p_item_status,disposition=p_disposition,updated_at=now()
 where return_item_id=p_return_item_id;
 insert into public.mme_return_audit_events(return_case_id,return_item_id,actor_user_id,action,new_state)
 values(v_item.return_case_id,p_return_item_id,p_actor_user_id,'item_disposition_set',
  jsonb_build_object('item_status',p_item_status,'disposition',p_disposition));
end;
$$;

revoke all on function public.mme_return_case_open_from_customer_request(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_return_case_set_eligibility(uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_return_item_record_inspection(uuid,uuid,jsonb,text,text,text,boolean,smallint,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_return_refund_request(uuid,numeric,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_return_refund_decide(uuid,uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.mme_return_refund_mark_processor_result(uuid,text,boolean,uuid) from public,anon,authenticated;
revoke all on function public.mme_return_case_set_item_disposition(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_return_case_open_from_customer_request(uuid,uuid) to service_role;
grant execute on function public.mme_return_case_set_eligibility(uuid,text,text,uuid) to service_role;
grant execute on function public.mme_return_item_record_inspection(uuid,uuid,jsonb,text,text,text,boolean,smallint,text,text,text,text,text,text) to service_role;
grant execute on function public.mme_return_refund_request(uuid,numeric,text,uuid,text) to service_role;
grant execute on function public.mme_return_refund_decide(uuid,uuid,boolean,text) to service_role;
grant execute on function public.mme_return_refund_mark_processor_result(uuid,text,boolean,uuid) to service_role;
grant execute on function public.mme_return_case_set_item_disposition(uuid,text,text,uuid) to service_role;

comment on table public.mme_return_cases is 'Governed RMA case lifecycle linked to a customer-originated return request.';
comment on table public.mme_return_case_items is 'Item-level inspection, grading and disposition; no automatic restock.';
comment on table public.mme_return_refund_decisions is 'Dual-control refund approval ledger; processor execution is delegated to a trusted Stripe adapter.';
comment on table public.mme_return_audit_events is 'Append-only return and refund action history.';

commit;
