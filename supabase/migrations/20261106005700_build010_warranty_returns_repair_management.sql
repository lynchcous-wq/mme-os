begin;
create table if not exists public.mme_device_warranties(
 warranty_id uuid primary key default gen_random_uuid(),
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 customer_reference text not null,
 sale_reference text not null,
 warranty_type text not null check(warranty_type in('manufacturer','mme_limited','mme_extended','seller')),
 provider_name text,
 coverage_summary text not null,
 starts_on date not null,
 expires_on date not null,
 warranty_status text not null default 'active' check(warranty_status in('active','expired','void','transferred','closed')),
 terms_version text,
 registered_by_auth_user_id uuid not null,
 registered_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(expires_on>=starts_on),
 unique(device_asset_id,warranty_type,sale_reference)
);
create index if not exists mme_device_warranties_device_idx on public.mme_device_warranties(device_asset_id,expires_on desc);
create index if not exists mme_device_warranties_customer_idx on public.mme_device_warranties(customer_reference);
create table if not exists public.mme_warranty_claims(
 claim_id uuid primary key default gen_random_uuid(),
 claim_number text not null unique,
 warranty_id uuid not null references public.mme_device_warranties(warranty_id) on delete restrict,
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 customer_reference text not null,
 claim_type text not null check(claim_type in('repair','replacement','diagnostic','refund_review')),
 issue_description text not null,
 evidence_reference text,
 claim_status text not null default 'submitted' check(claim_status in('submitted','under_review','approved','denied','in_repair','resolved','withdrawn')),
 decision_reason text,
 assigned_to_auth_user_id uuid,
 submitted_at timestamptz not null default now(),
 decided_at timestamptz,
 resolved_at timestamptz,
 created_by_auth_user_id uuid not null,
 updated_at timestamptz not null default now()
);
create index if not exists mme_warranty_claims_device_idx on public.mme_warranty_claims(device_asset_id,submitted_at desc);
create index if not exists mme_warranty_claims_status_idx on public.mme_warranty_claims(claim_status,submitted_at);
create table if not exists public.mme_repair_tickets(
 repair_ticket_id uuid primary key default gen_random_uuid(),
 ticket_number text not null unique,
 claim_id uuid references public.mme_warranty_claims(claim_id) on delete restrict,
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 customer_reference text not null,
 repair_type text not null check(repair_type in('warranty','paid_repair','diagnostic','refurbishment')),
 repair_status text not null default 'received' check(repair_status in('received','diagnosing','awaiting_approval','awaiting_parts','in_progress','quality_check','completed','cancelled')),
 symptom_summary text not null,
 diagnosis text,
 resolution_summary text,
 assigned_technician_auth_user_id uuid,
 estimated_cost numeric(12,2) check(estimated_cost is null or estimated_cost>=0),
 actual_labor_cost numeric(12,2) not null default 0 check(actual_labor_cost>=0),
 opened_at timestamptz not null default now(),
 completed_at timestamptz,
 created_by_auth_user_id uuid not null,
 updated_at timestamptz not null default now()
);
create index if not exists mme_repair_tickets_status_idx on public.mme_repair_tickets(repair_status,opened_at desc);
create index if not exists mme_repair_tickets_device_idx on public.mme_repair_tickets(device_asset_id,opened_at desc);
create table if not exists public.mme_repair_parts(
 repair_part_id uuid primary key default gen_random_uuid(),
 repair_ticket_id uuid not null references public.mme_repair_tickets(repair_ticket_id) on delete restrict,
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 quantity numeric(12,3) not null check(quantity>0),
 unit_cost numeric(12,2) not null check(unit_cost>=0),
 part_status text not null default 'planned' check(part_status in('planned','issued','returned','cancelled')),
 issued_by_auth_user_id uuid,
 issued_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists mme_repair_parts_ticket_idx on public.mme_repair_parts(repair_ticket_id);
create table if not exists public.mme_return_authorizations(
 rma_id uuid primary key default gen_random_uuid(),
 rma_number text not null unique,
 device_asset_id uuid not null references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 warranty_id uuid references public.mme_device_warranties(warranty_id) on delete restrict,
 claim_id uuid references public.mme_warranty_claims(claim_id) on delete restrict,
 customer_reference text not null,
 sale_reference text not null,
 return_reason text not null,
 rma_status text not null default 'requested' check(rma_status in('requested','approved','rejected','in_transit','received','inspected','refund_pending','replacement_pending','completed','cancelled')),
 inspection_grade text check(inspection_grade is null or inspection_grade in('new','open_box','excellent','good','fair','parts_only')),
 disposition text check(disposition is null or disposition in('restock','repair','refurbish','vendor_return','recycle','customer_return')),
 refund_reference text,
 replacement_device_asset_id uuid references public.mme_inventory_device_assets(device_asset_id) on delete restrict,
 requested_at timestamptz not null default now(),
 received_at timestamptz,
 completed_at timestamptz,
 created_by_auth_user_id uuid not null,
 updated_at timestamptz not null default now()
);
create index if not exists mme_return_authorizations_status_idx on public.mme_return_authorizations(rma_status,requested_at desc);
create table if not exists public.mme_service_management_events(
 service_event_id uuid primary key default gen_random_uuid(),
 entity_type text not null check(entity_type in('warranty','claim','repair','rma')),
 entity_id uuid not null,
 event_type text not null,
 previous_status text,
 new_status text,
 detail text,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_service_events_entity_idx on public.mme_service_management_events(entity_type,entity_id,created_at desc);

create or replace function public.mme_service_register_warranty(p_device uuid,p_customer text,p_sale text,p_type text,p_provider text,p_coverage text,p_start date,p_expiry date,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.mme_inventory_device_assets%rowtype; w public.mme_device_warranties%rowtype;
begin
 if p_actor is null or nullif(trim(p_customer),'') is null or nullif(trim(p_sale),'') is null then raise exception 'warranty_customer_sale_actor_required'; end if;
 select * into d from public.mme_inventory_device_assets where device_asset_id=p_device for update;
 if not found then raise exception 'device_asset_not_found'; end if;
 if d.asset_status not in('sold','returned') then raise exception 'warranty_requires_sold_device'; end if;
 insert into public.mme_device_warranties(device_asset_id,customer_reference,sale_reference,warranty_type,provider_name,coverage_summary,starts_on,expires_on,registered_by_auth_user_id)
 values(p_device,trim(p_customer),trim(p_sale),p_type,nullif(trim(coalesce(p_provider,'')),''),trim(p_coverage),p_start,p_expiry,p_actor) returning * into w;
 insert into public.mme_service_management_events(entity_type,entity_id,event_type,new_status,detail,actor_auth_user_id)
 values('warranty',w.warranty_id,'registered',w.warranty_status,'Warranty registered against verified serialized device record.',p_actor);
 return jsonb_build_object('warranty_id',w.warranty_id,'warranty_status',w.warranty_status,'expires_on',w.expires_on);
end $$;

create or replace function public.mme_service_submit_claim(p_warranty uuid,p_type text,p_issue text,p_evidence text,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare w public.mme_device_warranties%rowtype; c public.mme_warranty_claims%rowtype; n text;
begin
 select * into w from public.mme_device_warranties where warranty_id=p_warranty for update;
 if not found then raise exception 'warranty_not_found'; end if;
 if w.warranty_status<>'active' or current_date not between w.starts_on and w.expires_on then raise exception 'warranty_not_eligible'; end if;
 n:='CLM-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into public.mme_warranty_claims(claim_number,warranty_id,device_asset_id,customer_reference,claim_type,issue_description,evidence_reference,created_by_auth_user_id)
 values(n,p_warranty,w.device_asset_id,w.customer_reference,p_type,trim(p_issue),p_evidence,p_actor) returning * into c;
 insert into public.mme_service_management_events(entity_type,entity_id,event_type,new_status,detail,actor_auth_user_id)
 values('claim',c.claim_id,'submitted',c.claim_status,left(c.issue_description,500),p_actor);
 return jsonb_build_object('claim_id',c.claim_id,'claim_number',c.claim_number,'claim_status',c.claim_status);
end $$;

create or replace function public.mme_service_create_repair(p_device uuid,p_customer text,p_claim uuid,p_type text,p_symptom text,p_technician uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.mme_inventory_device_assets%rowtype; c public.mme_warranty_claims%rowtype; t public.mme_repair_tickets%rowtype; n text;
begin
 select * into d from public.mme_inventory_device_assets where device_asset_id=p_device for update;
 if not found then raise exception 'device_asset_not_found'; end if;
 if p_claim is not null then select * into c from public.mme_warranty_claims where claim_id=p_claim for update; if not found or c.device_asset_id<>p_device then raise exception 'claim_device_mismatch'; end if; end if;
 n:='RPR-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into public.mme_repair_tickets(ticket_number,claim_id,device_asset_id,customer_reference,repair_type,symptom_summary,assigned_technician_auth_user_id,created_by_auth_user_id)
 values(n,p_claim,p_device,trim(p_customer),p_type,trim(p_symptom),p_technician,p_actor) returning * into t;
 update public.mme_inventory_device_assets set asset_status='repair',updated_at=now() where device_asset_id=p_device and asset_status in('available','returned','sold');
 insert into public.mme_inventory_device_events(device_asset_id,event_type,from_status,to_status,source_reference,event_detail,actor_auth_user_id)
 values(p_device,'repair_started',d.asset_status,'repair',n,'Repair ticket opened.',p_actor);
 insert into public.mme_service_management_events(entity_type,entity_id,event_type,new_status,detail,actor_auth_user_id)
 values('repair',t.repair_ticket_id,'opened',t.repair_status,n,p_actor);
 return jsonb_build_object('repair_ticket_id',t.repair_ticket_id,'ticket_number',t.ticket_number,'repair_status',t.repair_status);
end $$;

create or replace function public.mme_service_update_status(p_entity text,p_id uuid,p_status text,p_detail text,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare old_status text; allowed boolean:=false; table_name text; id_column text;
begin
 if p_actor is null then raise exception 'actor_required'; end if;
 if p_entity='claim' then table_name:='mme_warranty_claims'; id_column:='claim_id';
 elsif p_entity='repair' then table_name:='mme_repair_tickets'; id_column:='repair_ticket_id';
 elsif p_entity='rma' then table_name:='mme_return_authorizations'; id_column:='rma_id';
 else raise exception 'unsupported_service_entity'; end if;
 if p_entity='claim' then
  select claim_status into old_status from public.mme_warranty_claims where claim_id=p_id for update;
  allowed:=p_status in('under_review','approved','denied','in_repair','resolved','withdrawn') and (case old_status when 'submitted' then p_status in('under_review','approved','denied','withdrawn') when 'under_review' then p_status in('approved','denied','withdrawn') when 'approved' then p_status in('in_repair','resolved','withdrawn') when 'in_repair' then p_status in('resolved') else false end);
  if not found then raise exception 'claim_not_found'; end if;
  update public.mme_warranty_claims set claim_status=p_status,decision_reason=case when p_status in('approved','denied') then left(p_detail,1000) else decision_reason end,decided_at=case when p_status in('approved','denied') then now() else decided_at end,resolved_at=case when p_status='resolved' then now() else resolved_at end,updated_at=now() where claim_id=p_id;
 elsif p_entity='repair' then
  select repair_status into old_status from public.mme_repair_tickets where repair_ticket_id=p_id for update;
  allowed:=case old_status when 'received' then p_status in('diagnosing','cancelled') when 'diagnosing' then p_status in('awaiting_approval','awaiting_parts','in_progress','cancelled') when 'awaiting_approval' then p_status in('awaiting_parts','in_progress','cancelled') when 'awaiting_parts' then p_status in('in_progress','cancelled') when 'in_progress' then p_status in('awaiting_parts','quality_check','cancelled') when 'quality_check' then p_status in('in_progress','completed') else false end;
  if not found then raise exception 'repair_ticket_not_found'; end if;
  update public.mme_repair_tickets set repair_status=p_status,diagnosis=case when p_detail is not null and p_status in('diagnosing','awaiting_approval') then left(p_detail,2000) else diagnosis end,resolution_summary=case when p_status='completed' then left(p_detail,2000) else resolution_summary end,completed_at=case when p_status='completed' then now() else completed_at end,updated_at=now() where repair_ticket_id=p_id;
 elsif p_entity='rma' then
  select rma_status into old_status from public.mme_return_authorizations where rma_id=p_id for update;
  allowed:=case old_status when 'requested' then p_status in('approved','rejected','cancelled') when 'approved' then p_status in('in_transit','received','cancelled') when 'in_transit' then p_status='received' when 'received' then p_status='inspected' when 'inspected' then p_status in('refund_pending','replacement_pending','completed') when 'refund_pending' then p_status='completed' when 'replacement_pending' then p_status='completed' else false end;
  if not found then raise exception 'rma_not_found'; end if;
  update public.mme_return_authorizations set rma_status=p_status,received_at=case when p_status='received' then now() else received_at end,completed_at=case when p_status='completed' then now() else completed_at end,updated_at=now() where rma_id=p_id;
 end if;
 if not allowed then raise exception 'invalid_service_status_transition'; end if;
 insert into public.mme_service_management_events(entity_type,entity_id,event_type,previous_status,new_status,detail,actor_auth_user_id)
 values(p_entity,p_id,'status_changed',old_status,p_status,left(coalesce(p_detail,''),1000),p_actor);
 return jsonb_build_object('entity_type',p_entity,'entity_id',p_id,'previous_status',old_status,'new_status',p_status);
end $$;

create or replace function public.mme_service_create_rma(p_device uuid,p_warranty uuid,p_claim uuid,p_customer text,p_sale text,p_reason text,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.mme_inventory_device_assets%rowtype; n text; r public.mme_return_authorizations%rowtype;
begin
 select * into d from public.mme_inventory_device_assets where device_asset_id=p_device for update;
 if not found then raise exception 'device_asset_not_found'; end if;
 if p_warranty is not null and not exists(select 1 from public.mme_device_warranties where warranty_id=p_warranty and device_asset_id=p_device) then raise exception 'warranty_device_mismatch'; end if;
 if p_claim is not null and not exists(select 1 from public.mme_warranty_claims where claim_id=p_claim and device_asset_id=p_device) then raise exception 'claim_device_mismatch'; end if;
 if d.asset_status not in('sold','returned') then raise exception 'rma_requires_sold_or_returned_device'; end if;
 n:='RMA-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into public.mme_return_authorizations(rma_number,device_asset_id,warranty_id,claim_id,customer_reference,sale_reference,return_reason,created_by_auth_user_id)
 values(n,p_device,p_warranty,p_claim,trim(p_customer),trim(p_sale),trim(p_reason),p_actor) returning * into r;
 insert into public.mme_service_management_events(entity_type,entity_id,event_type,new_status,detail,actor_auth_user_id)
 values('rma',r.rma_id,'requested',r.rma_status,n,p_actor);
 return jsonb_build_object('rma_id',r.rma_id,'rma_number',r.rma_number,'rma_status',r.rma_status);
end $$;

create or replace function public.mme_service_add_repair_part(p_ticket uuid,p_item uuid,p_qty numeric,p_cost numeric,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t public.mme_repair_tickets%rowtype; p public.mme_repair_parts%rowtype;
begin
 select * into t from public.mme_repair_tickets where repair_ticket_id=p_ticket for update;
 if not found then raise exception 'repair_ticket_not_found'; end if;
 if t.repair_status in('completed','cancelled') then raise exception 'repair_ticket_closed'; end if;
 insert into public.mme_repair_parts(repair_ticket_id,inventory_item_id,quantity,unit_cost,issued_by_auth_user_id)
 values(p_ticket,p_item,p_qty,p_cost,p_actor) returning * into p;
 return jsonb_build_object('repair_part_id',p.repair_part_id,'part_status',p.part_status);
end $$;

do $$declare f text;begin
 foreach f in array array[
 'mme_service_register_warranty(uuid,text,text,text,text,text,date,date,uuid)',
 'mme_service_submit_claim(uuid,text,text,text,uuid)',
 'mme_service_create_repair(uuid,text,uuid,text,text,uuid,uuid)',
 'mme_service_update_status(text,uuid,text,text,uuid)',
 'mme_service_create_rma(uuid,uuid,uuid,text,text,text,uuid)',
 'mme_service_add_repair_part(uuid,uuid,numeric,numeric,uuid)'
 ] loop execute format('revoke all on function public.%s from public,anon,authenticated',f); execute format('grant execute on function public.%s to service_role',f); end loop;
end $$;
do $$declare t text;begin foreach t in array array['mme_device_warranties','mme_warranty_claims','mme_repair_tickets','mme_repair_parts','mme_return_authorizations','mme_service_management_events'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);grant all on public.mme_device_warranties to service_role;grant all on public.mme_warranty_claims to service_role;grant all on public.mme_repair_tickets to service_role;grant all on public.mme_repair_parts to service_role;grant all on public.mme_return_authorizations to service_role;grant all on public.mme_service_management_events to service_role;end loop;end$$;
commit;