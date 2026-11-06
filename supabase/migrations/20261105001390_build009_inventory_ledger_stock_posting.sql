-- Build 009.59 — immutable inventory ledger, weighted-average valuation and authorized intake posting.
begin;
alter table public.mme_receiving_intake_staging
 add column requires_serial_validation boolean not null default false,
 add column valuation_status text not null default 'pending' check(valuation_status in ('pending','valued','blocked'));

create table public.mme_inventory_balances (
 balance_id uuid primary key default gen_random_uuid(),
 sku_reference text not null, location_code text not null, currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 on_hand_quantity bigint not null default 0 check(on_hand_quantity>=0),
 reserved_quantity bigint not null default 0 check(reserved_quantity>=0 and reserved_quantity<=on_hand_quantity),
 average_unit_cost numeric(18,6) not null default 0 check(average_unit_cost>=0),
 inventory_value numeric(18,2) not null default 0 check(inventory_value>=0),
 version bigint not null default 0, updated_at timestamptz not null default now(),
 unique(sku_reference,location_code,currency_code)
);
create table public.mme_inventory_ledger (
 ledger_entry_id uuid primary key default gen_random_uuid(),
 idempotency_key text not null unique,
 sku_reference text not null, location_code text not null,
 movement_type text not null check(movement_type in ('receipt','adjustment_in','adjustment_out','transfer_in','transfer_out','sale','return','reservation','release')),
 quantity_delta bigint not null check(quantity_delta<>0),
 unit_cost numeric(18,6) not null check(unit_cost>=0),
 value_delta numeric(18,2) not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 source_type text not null, source_id uuid not null,
 actor_user_id uuid not null, reason text,
 created_at timestamptz not null default now(),
 check((movement_type in ('receipt','adjustment_in','transfer_in','return','release') and quantity_delta>0)
    or (movement_type in ('adjustment_out','transfer_out','sale','reservation') and quantity_delta<0))
);
create index mme_inventory_ledger_sku_location_idx on public.mme_inventory_ledger(sku_reference,location_code,created_at desc);
create index mme_inventory_ledger_source_idx on public.mme_inventory_ledger(source_type,source_id);
create table public.mme_inventory_cost_layers (
 cost_layer_id uuid primary key default gen_random_uuid(),
 ledger_entry_id uuid not null unique references public.mme_inventory_ledger(ledger_entry_id) on delete restrict,
 sku_reference text not null, location_code text not null, currency_code text not null,
 original_quantity bigint not null check(original_quantity>0), remaining_quantity bigint not null check(remaining_quantity>=0 and remaining_quantity<=original_quantity),
 unit_cost numeric(18,6) not null check(unit_cost>=0), created_at timestamptz not null default now()
);
create index mme_inventory_cost_layers_available_idx on public.mme_inventory_cost_layers(sku_reference,location_code,created_at) where remaining_quantity>0;
create table public.mme_inventory_adjustment_requests (
 adjustment_request_id uuid primary key default gen_random_uuid(),
 sku_reference text not null, location_code text not null, currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 quantity_delta bigint not null check(quantity_delta<>0), unit_cost numeric(18,6) not null check(unit_cost>=0),
 reason_code text not null check(reason_code in ('count_correction','damage_writeoff','loss','found_stock','data_correction','other')),
 explanation text not null, status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled','posted')),
 requested_by uuid not null, reviewed_by uuid, reviewed_at timestamptz, ledger_entry_id uuid references public.mme_inventory_ledger(ledger_entry_id) on delete restrict,
 created_at timestamptz not null default now(), check(reviewed_by is null or reviewed_by<>requested_by)
);
create index mme_inventory_adjustment_pending_idx on public.mme_inventory_adjustment_requests(status,created_at);
create table public.mme_inventory_reconciliation_runs (
 reconciliation_id uuid primary key default gen_random_uuid(),
 sku_reference text not null, location_code text not null, currency_code text not null,
 ledger_quantity bigint not null, balance_quantity bigint not null, ledger_value numeric(18,2) not null, balance_value numeric(18,2) not null,
 status text not null check(status in ('matched','variance')), run_by uuid not null, run_at timestamptz not null default now()
);
create table public.mme_inventory_audit (
 audit_id bigint generated always as identity primary key, actor_user_id uuid not null,
 entity_type text not null, entity_id uuid, action text not null,
 prior_state jsonb not null default '{}'::jsonb, new_state jsonb not null default '{}'::jsonb,
 reason text, created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['mme_inventory_balances','mme_inventory_ledger','mme_inventory_cost_layers','mme_inventory_adjustment_requests','mme_inventory_reconciliation_runs','mme_inventory_audit']
 loop execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t); end loop;
end $$;
grant select on public.mme_inventory_balances,public.mme_inventory_ledger,public.mme_inventory_cost_layers,
 public.mme_inventory_adjustment_requests,public.mme_inventory_reconciliation_runs to service_role;
grant insert,select on public.mme_inventory_adjustment_requests to service_role;
grant select,insert on public.mme_inventory_reconciliation_runs,public.mme_inventory_audit to service_role;
revoke update,delete,truncate on public.mme_inventory_ledger,public.mme_inventory_audit from public,anon,authenticated,service_role;
revoke update,delete,truncate on public.mme_inventory_cost_layers from public,anon,authenticated,service_role;

create or replace function public.mme_inventory_post_receiving_intake(p_intake_id uuid,p_actor uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare i public.mme_receiving_intake_staging%rowtype; l public.mme_receiving_lines%rowtype; s public.mme_receiving_sessions%rowtype;
 b public.mme_inventory_balances%rowtype; new_entry uuid; new_value numeric(18,2); new_qty bigint; v_unit numeric(18,6);
 serial_count bigint; open_discrepancies bigint; key text;
begin
 if p_idempotency_key is null or length(trim(p_idempotency_key))<12 then raise exception 'Idempotency key must contain at least 12 characters' using errcode='22023'; end if;
 key:='receiving-intake:'||p_intake_id::text||':'||p_idempotency_key;
 select * into i from public.mme_receiving_intake_staging where intake_id=p_intake_id for update;
 if not found then raise exception 'Intake staging record not found' using errcode='22023'; end if;
 if i.intake_status='posted' then
  select ledger_entry_id into new_entry from public.mme_inventory_ledger where source_type='receiving_intake' and source_id=i.intake_id;
  if new_entry is not null then return new_entry; end if;
  raise exception 'Posted intake has no matching ledger entry; manual investigation required' using errcode='55000';
 end if;
 if i.intake_status<>'pending_inventory_post' then raise exception 'Intake is not eligible for posting' using errcode='55000'; end if;
 select * into l from public.mme_receiving_lines where receiving_line_id=i.receiving_line_id;
 select * into s from public.mme_receiving_sessions where receiving_session_id=l.receiving_session_id;
 if s.session_status not in ('reconciled','exception') then raise exception 'Receiving session must be finalized before posting' using errcode='55000'; end if;
 if l.accepted_quantity<>i.accepted_quantity or l.sku_reference<>i.sku_reference or s.location_code<>i.location_code then raise exception 'Staging record no longer matches accepted receiving line' using errcode='23514'; end if;
 select count(*) into open_discrepancies from public.mme_receiving_discrepancies d where d.receiving_line_id=l.receiving_line_id and d.resolution_status not in ('resolved','waived');
 if open_discrepancies>0 then raise exception 'Resolve receiving-line discrepancies before posting' using errcode='55000'; end if;
 if i.requires_serial_validation then
  select count(*) into serial_count from public.mme_receiving_serials rs where rs.receiving_line_id=l.receiving_line_id and rs.serial_status='accepted' and rs.device_test_status='passed' and coalesce(rs.activation_lock_status,'unknown') in ('clear','not_applicable');
  if serial_count<i.accepted_quantity then raise exception 'Accepted, tested and unlocked serial/IMEI records required for all accepted units' using errcode='55000'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(i.sku_reference||'|'||i.location_code||'|'||i.currency_code,0));
 insert into public.mme_inventory_balances(sku_reference,location_code,currency_code)
 values(i.sku_reference,i.location_code,i.currency_code) on conflict(sku_reference,location_code,currency_code) do nothing;
 select * into b from public.mme_inventory_balances where sku_reference=i.sku_reference and location_code=i.location_code and currency_code=i.currency_code for update;
 new_qty:=b.on_hand_quantity+i.accepted_quantity;
 new_value:=round(b.inventory_value+(i.accepted_quantity*i.unit_cost+i.allocated_landed_cost),2);
 v_unit:=case when new_qty=0 then 0 else round(new_value/new_qty,6) end;
 insert into public.mme_inventory_ledger(idempotency_key,sku_reference,location_code,movement_type,quantity_delta,unit_cost,value_delta,currency_code,source_type,source_id,actor_user_id,reason)
 values(key,i.sku_reference,i.location_code,'receipt',i.accepted_quantity,i.unit_cost+i.allocated_landed_cost/i.accepted_quantity,
 round(i.accepted_quantity*i.unit_cost+i.allocated_landed_cost,2),i.currency_code,'receiving_intake',i.intake_id,p_actor,'Authorized receiving intake posting')
 returning ledger_entry_id into new_entry;
 update public.mme_inventory_balances set on_hand_quantity=new_qty,inventory_value=new_value,average_unit_cost=v_unit,version=version+1,updated_at=now() where balance_id=b.balance_id;
 insert into public.mme_inventory_cost_layers(ledger_entry_id,sku_reference,location_code,currency_code,original_quantity,remaining_quantity,unit_cost)
 values(new_entry,i.sku_reference,i.location_code,i.currency_code,i.accepted_quantity,i.accepted_quantity,i.unit_cost+i.allocated_landed_cost/i.accepted_quantity);
 update public.mme_receiving_intake_staging set intake_status='posted',valuation_status='valued',posted_inventory_reference=new_entry::text,posted_at=now() where intake_id=i.intake_id;
 insert into public.mme_inventory_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'inventory_ledger',new_entry,'receiving_intake_posted',jsonb_build_object('intake_id',i.intake_id,'sku',i.sku_reference,'location',i.location_code,'quantity',i.accepted_quantity,'inventory_value',new_value,'average_unit_cost',v_unit));
 return new_entry;
end; $$;

create or replace function public.mme_inventory_request_adjustment(p_sku text,p_location text,p_currency text,p_delta bigint,p_unit_cost numeric,p_reason text,p_explanation text,p_actor uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid;
begin
 if p_delta=0 or trim(coalesce(p_explanation,''))='' then raise exception 'Nonzero adjustment and explanation required' using errcode='22023'; end if;
 insert into public.mme_inventory_adjustment_requests(sku_reference,location_code,currency_code,quantity_delta,unit_cost,reason_code,explanation,requested_by)
 values(p_sku,p_location,p_currency,p_delta,p_unit_cost,p_reason,left(p_explanation,2000),p_actor) returning adjustment_request_id into v_id;
 insert into public.mme_inventory_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'inventory_adjustment',v_id,'adjustment_requested',jsonb_build_object('sku',p_sku,'location',p_location,'delta',p_delta,'reason',p_reason));
 return v_id;
end; $$;

create or replace function public.mme_inventory_approve_adjustment(p_request uuid,p_reviewer uuid,p_note text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare a public.mme_inventory_adjustment_requests%rowtype; b public.mme_inventory_balances%rowtype; e uuid; q bigint; val numeric(18,2); typ text;
begin
 select * into a from public.mme_inventory_adjustment_requests where adjustment_request_id=p_request for update;
 if not found or a.status<>'pending' or p_reviewer is null or p_reviewer=a.requested_by then raise exception 'Pending adjustment requires independent reviewer' using errcode='55000'; end if;
 perform pg_advisory_xact_lock(hashtextextended(a.sku_reference||'|'||a.location_code||'|'||a.currency_code,0));
 insert into public.mme_inventory_balances(sku_reference,location_code,currency_code) values(a.sku_reference,a.location_code,a.currency_code)
 on conflict(sku_reference,location_code,currency_code) do nothing;
 select * into b from public.mme_inventory_balances where sku_reference=a.sku_reference and location_code=a.location_code and currency_code=a.currency_code for update;
 q:=b.on_hand_quantity+a.quantity_delta;
 if q< b.reserved_quantity then raise exception 'Adjustment cannot reduce stock below reserved quantity' using errcode='23514'; end if;
 if q<0 then raise exception 'Adjustment would create negative stock' using errcode='23514'; end if;
 typ:=case when a.quantity_delta>0 then 'adjustment_in' else 'adjustment_out' end;
 val:=case when a.quantity_delta>0 then round(abs(a.quantity_delta)*a.unit_cost,2) else -round(abs(a.quantity_delta)*b.average_unit_cost,2) end;
 if b.inventory_value+val<0 then raise exception 'Adjustment would create negative inventory value' using errcode='23514'; end if;
 insert into public.mme_inventory_ledger(idempotency_key,sku_reference,location_code,movement_type,quantity_delta,unit_cost,value_delta,currency_code,source_type,source_id,actor_user_id,reason)
 values('adjustment:'||a.adjustment_request_id::text,a.sku_reference,a.location_code,typ,a.quantity_delta,a.unit_cost,val,a.currency_code,'adjustment_request',a.adjustment_request_id,p_reviewer,left(p_note,2000))
 returning ledger_entry_id into e;
 update public.mme_inventory_balances set on_hand_quantity=q,inventory_value=inventory_value+val,
 average_unit_cost=case when q=0 then 0 else round((inventory_value+val)/q,6) end,
 version=version+1,updated_at=now() where balance_id=b.balance_id;
 update public.mme_inventory_adjustment_requests set status='posted',reviewed_by=p_reviewer,reviewed_at=now(),ledger_entry_id=e where adjustment_request_id=p_request;
 insert into public.mme_inventory_audit(actor_user_id,entity_type,entity_id,action,new_state,reason)
 values(p_reviewer,'inventory_adjustment',p_request,'adjustment_approved_and_posted',jsonb_build_object('ledger_entry_id',e,'quantity_delta',a.quantity_delta),p_note);
 return e;
end; $$;

create or replace function public.mme_inventory_reconcile_balance(p_sku text,p_location text,p_currency text,p_actor uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare b public.mme_inventory_balances%rowtype; lq bigint; lv numeric(18,2); rid uuid; st text;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_sku||'|'||p_location||'|'||p_currency,0));
 select * into b from public.mme_inventory_balances where sku_reference=p_sku and location_code=p_location and currency_code=p_currency for update;
 if not found then raise exception 'Inventory balance not found' using errcode='22023'; end if;
 select coalesce(sum(quantity_delta),0),coalesce(sum(value_delta),0) into lq,lv from public.mme_inventory_ledger where sku_reference=p_sku and location_code=p_location and currency_code=p_currency;
 st:=case when lq=b.on_hand_quantity and round(lv,2)=round(b.inventory_value,2) then 'matched' else 'variance' end;
 insert into public.mme_inventory_reconciliation_runs(sku_reference,location_code,currency_code,ledger_quantity,balance_quantity,ledger_value,balance_value,status,run_by)
 values(p_sku,p_location,p_currency,lq,b.on_hand_quantity,lv,b.inventory_value,st,p_actor) returning reconciliation_id into rid;
 insert into public.mme_inventory_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'inventory_reconciliation',rid,'inventory_balance_reconciled',jsonb_build_object('status',st,'ledger_quantity',lq,'balance_quantity',b.on_hand_quantity,'ledger_value',lv,'balance_value',b.inventory_value));
 return rid;
end; $$;

create or replace view public.mme_inventory_location_stock as
select sku_reference,location_code,currency_code,on_hand_quantity,reserved_quantity,
 on_hand_quantity-reserved_quantity as available_quantity,average_unit_cost,inventory_value,version,updated_at
from public.mme_inventory_balances;
revoke all on public.mme_inventory_location_stock from public,anon,authenticated;
grant select on public.mme_inventory_location_stock to service_role;

revoke all on function public.mme_inventory_post_receiving_intake(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_inventory_request_adjustment(text,text,text,bigint,numeric,text,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_approve_adjustment(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_inventory_reconcile_balance(text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_post_receiving_intake(uuid,uuid,text) to service_role;
grant execute on function public.mme_inventory_request_adjustment(text,text,text,bigint,numeric,text,text,uuid) to service_role;
grant execute on function public.mme_inventory_approve_adjustment(uuid,uuid,text) to service_role;
grant execute on function public.mme_inventory_reconcile_balance(text,text,text,uuid) to service_role;
commit;
