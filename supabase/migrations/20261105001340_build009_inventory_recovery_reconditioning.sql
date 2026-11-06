begin;
create table public.mme_inventory_recovery_assets (
 recovery_asset_id uuid primary key default gen_random_uuid(),
 return_item_id uuid not null unique references public.mme_return_case_items(return_item_id) on delete restrict,
 order_id uuid not null, person_id uuid not null, asset_reference text not null unique,
 serial_or_imei_reference text,
 asset_status text not null default 'quarantined' check(asset_status in ('quarantined','repair_pending','reconditioning','quality_review','classified','posted_to_inventory','parts_recovery','vendor_return','secure_disposal','blocked')),
 resale_classification text check(resale_classification in ('open_box','refurbished','parts_only','non_resellable')),
 condition_grade text check(condition_grade in ('A','B','C','D','non_resellable')),
 quarantine_location_id uuid not null, inventory_location_id uuid,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.mme_refurbishment_work_orders (
 work_order_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 work_order_number text not null unique,
 work_status text not null default 'queued' check(work_status in ('queued','in_progress','waiting_parts','completed','quality_failed','cancelled')),
 opened_by uuid not null, diagnosis text, repair_summary text,
 estimated_cost numeric(14,2) check(estimated_cost is null or estimated_cost>=0),
 actual_cost numeric(14,2) not null default 0 check(actual_cost>=0),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.mme_refurbishment_operations (
 operation_id uuid primary key default gen_random_uuid(),
 work_order_id uuid not null references public.mme_refurbishment_work_orders(work_order_id) on delete restrict,
 operation_type text not null check(operation_type in ('diagnostic','battery_replacement','screen_replacement','port_repair','camera_repair','software_restore','cleaning','data_wipe','parts_recovery','other')),
 operation_status text not null default 'planned' check(operation_status in ('planned','in_progress','completed','failed','skipped')),
 labor_minutes integer not null default 0 check(labor_minutes>=0),
 labor_cost numeric(14,2) not null default 0 check(labor_cost>=0),
 parts_cost numeric(14,2) not null default 0 check(parts_cost>=0),
 notes text, performed_by uuid, completed_at timestamptz, created_at timestamptz not null default now()
);
create table public.mme_recovered_asset_cost_ledger (
 cost_entry_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 work_order_id uuid references public.mme_refurbishment_work_orders(work_order_id) on delete restrict,
 cost_type text not null check(cost_type in ('return_handling','diagnostic_labor','repair_labor','replacement_battery','replacement_screen','replacement_parts','cleaning','data_wipe','shipping','other')),
 amount numeric(14,2) not null check(amount>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 recorded_by uuid not null, recorded_at timestamptz not null default now()
);
create table public.mme_recovered_asset_valuations (
 valuation_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 recovered_cost numeric(14,2) not null check(recovered_cost>=0),
 estimated_resale_value numeric(14,2) not null check(estimated_resale_value>=0),
 estimated_net_recovery numeric(14,2) not null,
 valuation_method text not null check(valuation_method in ('manual','market_comparable','approved_pricing_engine')),
 valued_by uuid not null, valued_at timestamptz not null default now()
);
create table public.mme_recovered_inventory_posting_outbox (
 posting_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null unique references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 idempotency_key text not null unique,
 posting_status text not null default 'pending' check(posting_status in ('pending','processing','posted','failed','cancelled')),
 sku_reference text, resale_classification text not null check(resale_classification in ('open_box','refurbished','parts_only')),
 condition_grade text not null check(condition_grade in ('A','B','C','D')),
 unit_cost numeric(14,2) not null check(unit_cost>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 inventory_location_id uuid not null, inventory_transaction_reference text, last_error text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.mme_inventory_recovery_audit (
 audit_id bigint generated always as identity primary key,
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 actor_user_id uuid not null, action text not null, previous_state jsonb not null default '{}'::jsonb,
 new_state jsonb not null default '{}'::jsonb, reason text, created_at timestamptz not null default now()
);
alter table public.mme_inventory_recovery_assets enable row level security;
alter table public.mme_refurbishment_work_orders enable row level security;
alter table public.mme_refurbishment_operations enable row level security;
alter table public.mme_recovered_asset_cost_ledger enable row level security;
alter table public.mme_recovered_asset_valuations enable row level security;
alter table public.mme_recovered_inventory_posting_outbox enable row level security;
alter table public.mme_inventory_recovery_audit enable row level security;
revoke all on public.mme_inventory_recovery_assets,public.mme_refurbishment_work_orders,public.mme_refurbishment_operations,public.mme_recovered_asset_cost_ledger,public.mme_recovered_asset_valuations,public.mme_recovered_inventory_posting_outbox,public.mme_inventory_recovery_audit from public,anon,authenticated;
grant select,insert,update on public.mme_inventory_recovery_assets,public.mme_refurbishment_work_orders,public.mme_refurbishment_operations,public.mme_recovered_asset_cost_ledger,public.mme_recovered_asset_valuations,public.mme_recovered_inventory_posting_outbox to service_role;
grant select,insert on public.mme_inventory_recovery_audit to service_role;
revoke update,delete,truncate on public.mme_inventory_recovery_audit from public,anon,authenticated,service_role;

create or replace function public.mme_inventory_recovery_quarantine_return_item(p_return_item_id uuid,p_asset_reference text,p_serial_or_imei_reference text,p_quarantine_location_id uuid,p_actor_user_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_item public.mme_return_case_items%rowtype; v_id uuid;
begin
 if p_asset_reference is null or p_quarantine_location_id is null or p_actor_user_id is null then raise exception 'Asset reference, quarantine location and actor required' using errcode='22023'; end if;
 select * into v_item from public.mme_return_case_items where return_item_id=p_return_item_id for update;
 if not found or v_item.item_status not in ('received','inspection_in_progress','inspection_complete','accepted','quarantined') then raise exception 'Return item is not eligible for recovery intake' using errcode='55000'; end if;
 if exists(select 1 from public.mme_return_inspections where return_item_id=p_return_item_id and serial_match is false) then raise exception 'Serial mismatch requires loss-prevention review' using errcode='55000'; end if;
 insert into public.mme_inventory_recovery_assets(return_item_id,order_id,person_id,asset_reference,serial_or_imei_reference,quarantine_location_id)
 values(v_item.return_item_id,v_item.order_id,v_item.person_id,p_asset_reference,p_serial_or_imei_reference,p_quarantine_location_id)
 on conflict(return_item_id) do update set updated_at=now() returning recovery_asset_id into v_id;
 update public.mme_return_case_items set item_status='quarantined',disposition='quarantine',updated_at=now() where return_item_id=p_return_item_id;
 insert into public.mme_inventory_recovery_audit(recovery_asset_id,actor_user_id,action,new_state) values(v_id,p_actor_user_id,'asset_quarantined',jsonb_build_object('location',p_quarantine_location_id));
 return v_id;
end; $$;

create or replace function public.mme_refurbishment_work_order_open(p_recovery_asset_id uuid,p_work_order_number text,p_opened_by uuid,p_diagnosis text,p_estimated_cost numeric)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_asset public.mme_inventory_recovery_assets%rowtype; v_id uuid;
begin
 select * into v_asset from public.mme_inventory_recovery_assets where recovery_asset_id=p_recovery_asset_id for update;
 if not found or v_asset.asset_status not in ('quarantined','repair_pending') then raise exception 'Asset must be quarantined or awaiting repair' using errcode='55000'; end if;
 if p_opened_by is null or p_work_order_number is null or p_estimated_cost<0 then raise exception 'Invalid work order' using errcode='22023'; end if;
 insert into public.mme_refurbishment_work_orders(recovery_asset_id,work_order_number,opened_by,diagnosis,estimated_cost) values(p_recovery_asset_id,p_work_order_number,p_opened_by,left(p_diagnosis,4000),p_estimated_cost) returning work_order_id into v_id;
 update public.mme_inventory_recovery_assets set asset_status='repair_pending',updated_at=now() where recovery_asset_id=p_recovery_asset_id;
 insert into public.mme_inventory_recovery_audit(recovery_asset_id,actor_user_id,action,new_state) values(p_recovery_asset_id,p_opened_by,'work_order_opened',jsonb_build_object('work_order_number',p_work_order_number));
 return v_id;
end; $$;

create or replace function public.mme_refurbishment_record_operation(p_work_order_id uuid,p_operation_type text,p_operation_status text,p_labor_minutes integer,p_labor_cost numeric,p_parts_cost numeric,p_notes text,p_performed_by uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_work public.mme_refurbishment_work_orders%rowtype; v_id uuid;
begin
 select * into v_work from public.mme_refurbishment_work_orders where work_order_id=p_work_order_id for update;
 if not found or v_work.work_status not in ('queued','in_progress','waiting_parts') then raise exception 'Work order is not active' using errcode='55000'; end if;
 if p_operation_type not in ('diagnostic','battery_replacement','screen_replacement','port_repair','camera_repair','software_restore','cleaning','data_wipe','parts_recovery','other') or p_operation_status not in ('planned','in_progress','completed','failed','skipped') or p_labor_minutes<0 or p_labor_cost<0 or p_parts_cost<0 or p_performed_by is null then raise exception 'Invalid operation' using errcode='22023'; end if;
 insert into public.mme_refurbishment_operations(work_order_id,operation_type,operation_status,labor_minutes,labor_cost,parts_cost,notes,performed_by,completed_at)
 values(p_work_order_id,p_operation_type,p_operation_status,p_labor_minutes,p_labor_cost,p_parts_cost,left(p_notes,2000),p_performed_by,case when p_operation_status in ('completed','failed','skipped') then now() end) returning operation_id into v_id;
 update public.mme_refurbishment_work_orders set work_status='in_progress',updated_at=now() where work_order_id=p_work_order_id and work_status='queued';
 if p_operation_status='completed' then
  insert into public.mme_recovered_asset_cost_ledger(recovery_asset_id,work_order_id,cost_type,amount,currency_code,recorded_by)
  values(v_work.recovery_asset_id,p_work_order_id,case when p_operation_type='battery_replacement' then 'replacement_battery' when p_operation_type='screen_replacement' then 'replacement_screen' when p_labor_cost>0 then 'repair_labor' else 'other' end,p_labor_cost+p_parts_cost,'USD',p_performed_by);
 end if;
 return v_id;
end; $$;

create or replace function public.mme_refurbishment_complete_work_order(p_work_order_id uuid,p_repair_summary text,p_actor_user_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_work public.mme_refurbishment_work_orders%rowtype; v_total numeric(14,2);
begin
 select * into v_work from public.mme_refurbishment_work_orders where work_order_id=p_work_order_id for update;
 if not found or v_work.work_status not in ('queued','in_progress','waiting_parts') then raise exception 'Active work order required' using errcode='55000'; end if;
 if exists(select 1 from public.mme_refurbishment_operations where work_order_id=p_work_order_id and operation_status in ('planned','in_progress')) then raise exception 'Resolve all planned operations first' using errcode='55000'; end if;
 select coalesce(sum(labor_cost+parts_cost),0) into v_total from public.mme_refurbishment_operations where work_order_id=p_work_order_id and operation_status='completed';
 update public.mme_refurbishment_work_orders set work_status='completed',repair_summary=left(p_repair_summary,4000),actual_cost=v_total,updated_at=now() where work_order_id=p_work_order_id;
 update public.mme_inventory_recovery_assets set asset_status='quality_review',updated_at=now() where recovery_asset_id=v_work.recovery_asset_id;
 insert into public.mme_inventory_recovery_audit(recovery_asset_id,actor_user_id,action,new_state) values(v_work.recovery_asset_id,p_actor_user_id,'refurbishment_completed',jsonb_build_object('actual_cost',v_total));
end; $$;

create or replace function public.mme_inventory_recovery_classify_asset(p_recovery_asset_id uuid,p_classification text,p_condition_grade text,p_inventory_location_id uuid,p_valued_by uuid,p_currency_code text,p_estimated_resale_value numeric)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_asset public.mme_inventory_recovery_assets%rowtype; v_cost numeric(14,2); v_id uuid;
begin
 select * into v_asset from public.mme_inventory_recovery_assets where recovery_asset_id=p_recovery_asset_id for update;
 if not found or v_asset.asset_status<>'quality_review' then raise exception 'Asset must pass quality review before classification' using errcode='55000'; end if;
 if p_classification not in ('open_box','refurbished','parts_only','non_resellable') or p_condition_grade not in ('A','B','C','D','non_resellable') or p_inventory_location_id is null or p_valued_by is null or p_currency_code !~ '^[A-Z]{3}$' or p_estimated_resale_value<0 then raise exception 'Invalid classification or valuation' using errcode='22023'; end if;
 if p_classification='open_box' and p_condition_grade not in ('A','B') then raise exception 'Open-box requires grade A or B' using errcode='55000'; end if;
 if p_classification='refurbished' and p_condition_grade not in ('A','B','C') then raise exception 'Refurbished requires grade A, B or C' using errcode='55000'; end if;
 if p_classification='parts_only' and p_condition_grade not in ('C','D') then raise exception 'Parts-only requires grade C or D' using errcode='55000'; end if;
 if p_classification='non_resellable' and p_condition_grade<>'non_resellable' then raise exception 'Non-resellable classification requires non-resellable grade' using errcode='55000'; end if;
 if exists(select 1 from public.mme_return_inspections where return_item_id=v_asset.return_item_id and (serial_match is false or activation_lock_status='locked' or inspection_status<>'passed')) then raise exception 'Inspection failure, serial mismatch or activation lock blocks resale' using errcode='55000'; end if;
 select coalesce(sum(amount),0) into v_cost from public.mme_recovered_asset_cost_ledger where recovery_asset_id=p_recovery_asset_id;
 insert into public.mme_recovered_asset_valuations(recovery_asset_id,currency_code,recovered_cost,estimated_resale_value,estimated_net_recovery,valuation_method,valued_by)
 values(p_recovery_asset_id,p_currency_code,v_cost,p_estimated_resale_value,p_estimated_resale_value-v_cost,'manual',p_valued_by) returning valuation_id into v_id;
 update public.mme_inventory_recovery_assets set resale_classification=p_classification,condition_grade=p_condition_grade,asset_status='classified',inventory_location_id=p_inventory_location_id,updated_at=now() where recovery_asset_id=p_recovery_asset_id;
 insert into public.mme_inventory_recovery_audit(recovery_asset_id,actor_user_id,action,new_state) values(p_recovery_asset_id,p_valued_by,'asset_classified',jsonb_build_object('classification',p_classification,'grade',p_condition_grade,'recovered_cost',v_cost,'resale_value',p_estimated_resale_value));
 return v_id;
end; $$;

create or replace function public.mme_inventory_recovery_queue_inventory_posting(p_recovery_asset_id uuid,p_idempotency_key text,p_sku_reference text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_asset public.mme_inventory_recovery_assets%rowtype; v_cost numeric(14,2); v_id uuid;
begin
 select * into v_asset from public.mme_inventory_recovery_assets where recovery_asset_id=p_recovery_asset_id for update;
 if not found or v_asset.asset_status<>'classified' or v_asset.resale_classification not in ('open_box','refurbished','parts_only') then raise exception 'Classified resale-eligible asset required' using errcode='55000'; end if;
 select coalesce(sum(amount),0) into v_cost from public.mme_recovered_asset_cost_ledger where recovery_asset_id=p_recovery_asset_id;
 insert into public.mme_recovered_inventory_posting_outbox(recovery_asset_id,idempotency_key,sku_reference,resale_classification,condition_grade,unit_cost,currency_code,inventory_location_id)
 values(p_recovery_asset_id,p_idempotency_key,p_sku_reference,v_asset.resale_classification,v_asset.condition_grade,v_cost,'USD',v_asset.inventory_location_id)
 on conflict(recovery_asset_id) do update set updated_at=now() returning posting_id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_inventory_recovery_mark_posted(p_posting_id uuid,p_inventory_transaction_reference text,p_actor_user_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_post public.mme_recovered_inventory_posting_outbox%rowtype;
begin
 select * into v_post from public.mme_recovered_inventory_posting_outbox where posting_id=p_posting_id for update;
 if not found or v_post.posting_status not in ('pending','processing') or p_inventory_transaction_reference is null or p_actor_user_id is null then raise exception 'Pending posting and valid transaction reference required' using errcode='55000'; end if;
 update public.mme_recovered_inventory_posting_outbox set posting_status='posted',inventory_transaction_reference=p_inventory_transaction_reference,updated_at=now() where posting_id=p_posting_id;
 update public.mme_inventory_recovery_assets set asset_status='posted_to_inventory',updated_at=now() where recovery_asset_id=v_post.recovery_asset_id;
 insert into public.mme_inventory_recovery_audit(recovery_asset_id,actor_user_id,action,new_state) values(v_post.recovery_asset_id,p_actor_user_id,'inventory_posting_confirmed',jsonb_build_object('posting_id',p_posting_id,'inventory_transaction_reference',p_inventory_transaction_reference));
end; $$;

revoke all on function public.mme_inventory_recovery_quarantine_return_item(uuid,text,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_refurbishment_work_order_open(uuid,text,uuid,text,numeric) from public,anon,authenticated;
revoke all on function public.mme_refurbishment_record_operation(uuid,text,text,integer,numeric,numeric,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_refurbishment_complete_work_order(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_recovery_classify_asset(uuid,text,text,uuid,uuid,text,numeric) from public,anon,authenticated;
revoke all on function public.mme_inventory_recovery_queue_inventory_posting(uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_inventory_recovery_mark_posted(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_recovery_quarantine_return_item(uuid,text,text,uuid,uuid) to service_role;
grant execute on function public.mme_refurbishment_work_order_open(uuid,text,uuid,text,numeric) to service_role;
grant execute on function public.mme_refurbishment_record_operation(uuid,text,text,integer,numeric,numeric,text,uuid) to service_role;
grant execute on function public.mme_refurbishment_complete_work_order(uuid,text,uuid) to service_role;
grant execute on function public.mme_inventory_recovery_classify_asset(uuid,text,text,uuid,uuid,text,numeric) to service_role;
grant execute on function public.mme_inventory_recovery_queue_inventory_posting(uuid,text,text) to service_role;
grant execute on function public.mme_inventory_recovery_mark_posted(uuid,text,uuid) to service_role;
commit;