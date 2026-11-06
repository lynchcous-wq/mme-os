-- Build 009.63 — governed reverse logistics and inventory recovery bridge.
begin;
create table public.mme_return_reverse_logistics (
 reverse_logistics_id uuid primary key default gen_random_uuid(),
 return_item_id uuid not null unique references public.mme_return_case_items(return_item_id) on delete restrict,
 sku_reference text not null, location_code text not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 quantity bigint not null check(quantity>0),
 disposition text not null check(disposition in ('restock_new','restock_open_box','refurbishment','parts_recovery','vendor_return','quarantine','secure_disposal')),
 condition_grade text not null check(condition_grade in ('A','B','C','D','non_resellable')),
 serial_verified boolean not null default false,
 inspection_id uuid references public.mme_return_inspections(inspection_id) on delete restrict,
 status text not null default 'pending_approval' check(status in ('pending_approval','approved','rejected','posted','quarantined','vendor_return_pending','disposed')),
 requested_by uuid not null, approved_by uuid, approved_at timestamptz,
 ledger_entry_id uuid unique references public.mme_inventory_ledger(ledger_entry_id) on delete restrict,
 unit_cost numeric(18,6), reason text not null, idempotency_key text not null unique,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>requested_by),
 check(status not in ('approved','posted','quarantined','vendor_return_pending','disposed') or approved_by is not null)
);
create table public.mme_return_quarantine_inventory (
 quarantine_id uuid primary key default gen_random_uuid(),
 reverse_logistics_id uuid not null unique references public.mme_return_reverse_logistics(reverse_logistics_id) on delete restrict,
 sku_reference text not null, location_code text not null, quantity bigint not null check(quantity>0),
 reason text not null, evidence_reference text,
 status text not null default 'held' check(status in ('held','released_to_refurbishment','returned_to_vendor','disposed')),
 created_by uuid not null, created_at timestamptz not null default now(),
 resolved_by uuid, resolved_at timestamptz, resolution_note text
);
create table public.mme_return_reverse_logistics_events (
 event_id bigint generated always as identity primary key,
 reverse_logistics_id uuid not null references public.mme_return_reverse_logistics(reverse_logistics_id) on delete restrict,
 event_type text not null check(event_type in ('disposition_requested','disposition_approved','disposition_rejected','inventory_posted','quarantined','vendor_return_started','disposed')),
 actor_user_id uuid not null, event_data jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index mme_return_reverse_status_idx on public.mme_return_reverse_logistics(status,created_at);
create index mme_return_quarantine_queue_idx on public.mme_return_quarantine_inventory(location_code,status,created_at);
alter table public.mme_return_reverse_logistics enable row level security;
alter table public.mme_return_quarantine_inventory enable row level security;
alter table public.mme_return_reverse_logistics_events enable row level security;
revoke all on public.mme_return_reverse_logistics,public.mme_return_quarantine_inventory,public.mme_return_reverse_logistics_events from public,anon,authenticated;
grant select,insert,update on public.mme_return_reverse_logistics,public.mme_return_quarantine_inventory to service_role;
grant select,insert on public.mme_return_reverse_logistics_events to service_role;
revoke update,delete,truncate on public.mme_return_reverse_logistics_events from public,anon,authenticated,service_role;

create or replace function public.mme_return_reverse_request_disposition(
 p_return_item uuid,p_sku text,p_location text,p_currency text,p_quantity bigint,
 p_disposition text,p_grade text,p_inspection uuid,p_serial_verified boolean,
 p_actor uuid,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare i public.mme_return_case_items%rowtype; ins public.mme_return_inspections%rowtype; v uuid; old public.mme_return_reverse_logistics%rowtype;
begin
 if p_actor is null or p_quantity<1 or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Actor, quantity and idempotency key required' using errcode='22023'; end if;
 select * into old from public.mme_return_reverse_logistics where idempotency_key=p_idempotency_key;
 if found then
  if old.return_item_id<>p_return_item or old.sku_reference<>p_sku or old.quantity<>p_quantity or old.disposition<>p_disposition then raise exception 'Idempotency key reused with different disposition payload' using errcode='23505'; end if;
  return old.reverse_logistics_id;
 end if;
 select * into i from public.mme_return_case_items where return_item_id=p_return_item for update;
 if not found or i.item_status not in ('received','inspection_complete','accepted') then raise exception 'Return item must be received and inspected before disposition' using errcode='55000'; end if;
 if i.quantity<>p_quantity or p_disposition not in ('restock_new','restock_open_box','refurbishment','parts_recovery','vendor_return','quarantine','secure_disposal') or p_grade not in ('A','B','C','D','non_resellable') then raise exception 'Invalid disposition payload' using errcode='22023'; end if;
 select * into ins from public.mme_return_inspections where inspection_id=p_inspection and return_item_id=p_return_item;
 if not found or ins.inspection_status not in ('passed','needs_manager_review') then raise exception 'Completed inspection required' using errcode='55000'; end if;
 if (ins.serial_match is false or ins.activation_lock_status in ('locked','unknown')) and p_disposition in ('restock_new','restock_open_box') then raise exception 'Serial mismatch or activation lock prevents direct restock' using errcode='23514'; end if;
 if p_disposition in ('restock_new','restock_open_box') and (p_grade not in ('A','B') or ins.inspection_status<>'passed' or ins.activation_lock_status not in ('clear','not_applicable') or ins.serial_match is distinct from true) then
  raise exception 'Direct restock requires grade A/B, passed inspection, verified serial and clear activation lock' using errcode='23514';
 end if;
 insert into public.mme_return_reverse_logistics(return_item_id,sku_reference,location_code,currency_code,quantity,disposition,condition_grade,serial_verified,inspection_id,requested_by,reason,idempotency_key)
 values(p_return_item,p_sku,p_location,p_currency,p_quantity,p_disposition,p_grade,p_serial_verified,p_inspection,p_actor,left(p_reason,1000),p_idempotency_key)
 returning reverse_logistics_id into v;
 insert into public.mme_return_reverse_logistics_events(reverse_logistics_id,event_type,actor_user_id,event_data)
 values(v,'disposition_requested',p_actor,jsonb_build_object('disposition',p_disposition,'grade',p_grade,'quantity',p_quantity));
 return v;
end; $$;

create or replace function public.mme_return_reverse_decide_disposition(p_id uuid,p_actor uuid,p_approve boolean,p_reason text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_return_reverse_logistics%rowtype;
begin
 select * into r from public.mme_return_reverse_logistics where reverse_logistics_id=p_id for update;
 if not found or r.status<>'pending_approval' then raise exception 'Pending disposition request not found' using errcode='55000'; end if;
 if p_actor is null or p_actor=r.requested_by then raise exception 'Independent disposition approver required' using errcode='42501'; end if;
 update public.mme_return_reverse_logistics set status=case when p_approve then 'approved' else 'rejected' end,
 approved_by=case when p_approve then p_actor else null end,approved_at=case when p_approve then now() else null end,
 reason=left(r.reason||' | Decision: '||coalesce(p_reason,''),1500),updated_at=now() where reverse_logistics_id=p_id;
 update public.mme_return_case_items set disposition=r.disposition,condition_grade=r.condition_grade,
 item_status=case when p_approve and r.disposition in ('restock_new','restock_open_box') then 'accepted'
 when p_approve and r.disposition='quarantine' then 'quarantined'
 when p_approve and r.disposition='secure_disposal' then 'disposed'
 when p_approve then 'accepted' else 'inspection_complete' end,updated_at=now()
 where return_item_id=r.return_item_id;
 insert into public.mme_return_reverse_logistics_events(reverse_logistics_id,event_type,actor_user_id,event_data)
 values(p_id,case when p_approve then 'disposition_approved' else 'disposition_rejected' end,p_actor,jsonb_build_object('reason',p_reason));
end; $$;

create or replace function public.mme_return_reverse_post_disposition(p_id uuid,p_actor uuid,p_posting_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_return_reverse_logistics%rowtype; b public.mme_inventory_balances%rowtype; e uuid; v numeric(18,2);
begin
 if length(trim(coalesce(p_posting_key,'')))<12 then raise exception 'Posting idempotency key required' using errcode='22023'; end if;
 select * into r from public.mme_return_reverse_logistics where reverse_logistics_id=p_id for update;
 if not found then raise exception 'Reverse logistics record not found' using errcode='P0002'; end if;
 if r.status='posted' then return r.ledger_entry_id; end if;
 if r.status<>'approved' or r.approved_by is null or r.approved_by=r.requested_by then raise exception 'Independent approved disposition required' using errcode='55000'; end if;
 if r.disposition in ('restock_new','restock_open_box') then
  if r.serial_verified is not true then raise exception 'Serialized item identity verification required before restock' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended(r.sku_reference||'|'||r.location_code||'|'||r.currency_code,0));
  insert into public.mme_inventory_balances(sku_reference,location_code,currency_code) values(r.sku_reference,r.location_code,r.currency_code)
  on conflict(sku_reference,location_code,currency_code) do nothing;
  select * into b from public.mme_inventory_balances where sku_reference=r.sku_reference and location_code=r.location_code and currency_code=r.currency_code for update;
  v:=round(r.quantity*b.average_unit_cost,2);
  insert into public.mme_inventory_ledger(idempotency_key,sku_reference,location_code,movement_type,quantity_delta,unit_cost,value_delta,currency_code,source_type,source_id,actor_user_id,reason)
  values(p_posting_key,r.sku_reference,r.location_code,'return',r.quantity,b.average_unit_cost,v,r.currency_code,'return_reverse_logistics',r.reverse_logistics_id,p_actor,'Approved inspected customer return to sellable stock')
  returning ledger_entry_id into e;
  update public.mme_inventory_balances set on_hand_quantity=on_hand_quantity+r.quantity,inventory_value=inventory_value+v,
   average_unit_cost=case when on_hand_quantity+r.quantity=0 then b.average_unit_cost else round((inventory_value+v)/(on_hand_quantity+r.quantity),6) end,
   version=version+1,updated_at=now() where balance_id=b.balance_id;
  insert into public.mme_inventory_cost_layers(ledger_entry_id,sku_reference,location_code,currency_code,original_quantity,remaining_quantity,unit_cost)
  values(e,r.sku_reference,r.location_code,r.currency_code,r.quantity,r.quantity,b.average_unit_cost);
  update public.mme_return_reverse_logistics set status='posted',ledger_entry_id=e,unit_cost=b.average_unit_cost,updated_at=now() where reverse_logistics_id=p_id;
  update public.mme_return_case_items set item_status='restocked',updated_at=now() where return_item_id=r.return_item_id;
  insert into public.mme_return_reverse_logistics_events(reverse_logistics_id,event_type,actor_user_id,event_data)
  values(p_id,'inventory_posted',p_actor,jsonb_build_object('ledger_entry_id',e,'quantity',r.quantity));
 elsif r.disposition in ('quarantine','refurbishment','parts_recovery') then
  insert into public.mme_return_quarantine_inventory(reverse_logistics_id,sku_reference,location_code,quantity,reason,created_by)
  values(p_id,r.sku_reference,r.location_code,r.quantity,r.reason,p_actor);
  update public.mme_return_reverse_logistics set status='quarantined',updated_at=now() where reverse_logistics_id=p_id;
  insert into public.mme_return_reverse_logistics_events(reverse_logistics_id,event_type,actor_user_id,event_data)
  values(p_id,'quarantined',p_actor,jsonb_build_object('disposition',r.disposition));
 elsif r.disposition='vendor_return' then
  update public.mme_return_reverse_logistics set status='vendor_return_pending',updated_at=now() where reverse_logistics_id=p_id;
  insert into public.mme_return_reverse_logistics_events(reverse_logistics_id,event_type,actor_user_id,event_data)
  values(p_id,'vendor_return_started',p_actor,jsonb_build_object('quantity',r.quantity));
 elsif r.disposition='secure_disposal' then
  update public.mme_return_reverse_logistics set status='disposed',updated_at=now() where reverse_logistics_id=p_id;
  insert into public.mme_return_reverse_logistics_events(reverse_logistics_id,event_type,actor_user_id,event_data)
  values(p_id,'disposed',p_actor,jsonb_build_object('quantity',r.quantity,'requires_certificate',true));
 else raise exception 'Unsupported disposition; use an approved recovery workflow' using errcode='22023';
 end if;
 return e;
end; $$;
revoke all on function public.mme_return_reverse_request_disposition(uuid,text,text,text,bigint,text,text,uuid,boolean,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_return_reverse_decide_disposition(uuid,uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.mme_return_reverse_post_disposition(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_return_reverse_request_disposition(uuid,text,text,text,bigint,text,text,uuid,boolean,uuid,text,text) to service_role;
grant execute on function public.mme_return_reverse_decide_disposition(uuid,uuid,boolean,text) to service_role;
grant execute on function public.mme_return_reverse_post_disposition(uuid,uuid,text) to service_role;
commit;
