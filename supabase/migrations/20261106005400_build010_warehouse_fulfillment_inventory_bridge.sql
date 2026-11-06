begin;
create table if not exists public.mme_warehouse_fulfillment_jobs(
 fulfillment_job_id uuid primary key default gen_random_uuid(),
 fulfillment_number text not null unique,
 wave_id uuid not null unique references public.mme_warehouse_pick_waves(wave_id) on delete restrict,
 source_type text not null check(source_type in('customer_order','transfer','return','manual')),
 source_reference text not null,
 fulfillment_status text not null default 'staged' check(fulfillment_status in('staged','awaiting_inventory_post','inventory_posted','ready_to_ship','shipped','cancelled','blocked')),
 inventory_posting_status text not null default 'pending' check(inventory_posting_status in('pending','processing','posted','failed','not_required')),
 idempotency_key text not null unique,
 staged_by_auth_user_id uuid not null,
 staged_at timestamptz not null default now(),
 inventory_posted_at timestamptz,
 shipped_at timestamptz,
 failure_code text,
 failure_detail text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_warehouse_fulfillment_job_lines(
 fulfillment_job_line_id uuid primary key default gen_random_uuid(),
 fulfillment_job_id uuid not null references public.mme_warehouse_fulfillment_jobs(fulfillment_job_id) on delete restrict,
 pick_line_id uuid not null unique references public.mme_warehouse_pick_lines(pick_line_id) on delete restrict,
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 source_location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 fulfilled_quantity integer not null check(fulfilled_quantity>0),
 created_at timestamptz not null default now()
);
create table if not exists public.mme_warehouse_inventory_posting_queue(
 posting_id uuid primary key default gen_random_uuid(),
 fulfillment_job_id uuid not null unique references public.mme_warehouse_fulfillment_jobs(fulfillment_job_id) on delete restrict,
 posting_status text not null default 'pending' check(posting_status in('pending','processing','posted','failed','cancelled')),
 attempt_count integer not null default 0 check(attempt_count>=0),
 last_attempt_at timestamptz,
 posted_movement_reference text,
 error_code text,
 error_detail text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists mme_warehouse_posting_queue_status_idx on public.mme_warehouse_inventory_posting_queue(posting_status,created_at);
create table if not exists public.mme_warehouse_fulfillment_events(
 event_id uuid primary key default gen_random_uuid(),
 fulfillment_job_id uuid not null references public.mme_warehouse_fulfillment_jobs(fulfillment_job_id) on delete restrict,
 event_type text not null check(event_type in('staged','posting_queued','inventory_posted','posting_failed','ready_to_ship','shipped','cancelled','blocked')),
 event_detail text,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_warehouse_fulfillment_events_history_idx on public.mme_warehouse_fulfillment_events(fulfillment_job_id,created_at desc);
create or replace function public.mme_warehouse_stage_fulfillment(p_wave uuid,p_number text,p_source_type text,p_source_reference text,p_idempotency_key text,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare w public.mme_warehouse_pick_waves%rowtype; existing public.mme_warehouse_fulfillment_jobs%rowtype; job public.mme_warehouse_fulfillment_jobs%rowtype; line_count integer; total_units integer;
begin
 if p_wave is null or length(trim(coalesce(p_number,'')))=0 or length(trim(coalesce(p_source_reference,'')))=0 or length(trim(coalesce(p_idempotency_key,'')))=0 or p_source_type not in('customer_order','transfer','return','manual') then raise exception 'invalid_fulfillment_stage_payload'; end if;
 select * into w from public.mme_warehouse_pick_waves where wave_id=p_wave for update;
 if not found then raise exception 'pick_wave_not_found'; end if;
 select * into existing from public.mme_warehouse_fulfillment_jobs where wave_id=p_wave or idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('fulfillment_job_id',existing.fulfillment_job_id,'fulfillment_status',existing.fulfillment_status,'inventory_posting_status',existing.inventory_posting_status,'idempotent_replay',true); end if;
 if w.wave_status not in('picked','packing','staged') then raise exception 'wave_not_ready_for_fulfillment'; end if;
 if w.source_type<>p_source_type or coalesce(w.source_reference,'')<>p_source_reference then raise exception 'fulfillment_source_mismatch'; end if;
 select count(*),coalesce(sum(requested_quantity),0) into line_count,total_units from public.mme_warehouse_pick_lines where wave_id=p_wave;
 if line_count=0 then raise exception 'empty_pick_wave'; end if;
 if exists(select 1 from public.mme_warehouse_pick_lines where wave_id=p_wave and (line_status<>'complete' or picked_quantity<>requested_quantity)) then raise exception 'pick_lines_incomplete'; end if;
 if exists(select 1 from public.mme_warehouse_pack_checks where wave_id=p_wave and verification_status<>'verified') then raise exception 'packing_discrepancy_unresolved'; end if;
 if not exists(select 1 from public.mme_warehouse_pack_checks where wave_id=p_wave) then raise exception 'packing_verification_required'; end if;
 insert into public.mme_warehouse_fulfillment_jobs(fulfillment_number,wave_id,source_type,source_reference,fulfillment_status,inventory_posting_status,idempotency_key,staged_by_auth_user_id)
 values(p_number,p_wave,p_source_type,p_source_reference,'awaiting_inventory_post','pending',p_idempotency_key,p_actor) returning * into job;
 insert into public.mme_warehouse_fulfillment_job_lines(fulfillment_job_id,pick_line_id,inventory_item_id,source_location_id,fulfilled_quantity)
 select job.fulfillment_job_id,pick_line_id,inventory_item_id,source_location_id,picked_quantity from public.mme_warehouse_pick_lines where wave_id=p_wave;
 insert into public.mme_warehouse_inventory_posting_queue(fulfillment_job_id) values(job.fulfillment_job_id);
 insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(job.fulfillment_job_id,'staged','Warehouse pick and pack checks passed; awaiting authoritative inventory ledger posting.',p_actor),(job.fulfillment_job_id,'posting_queued','Inventory posting queued; stock balances have not yet changed.',p_actor);
 update public.mme_warehouse_pick_waves set wave_status='staged',updated_at=now() where wave_id=p_wave;
 return jsonb_build_object('fulfillment_job_id',job.fulfillment_job_id,'fulfillment_number',job.fulfillment_number,'fulfillment_status',job.fulfillment_status,'inventory_posting_status',job.inventory_posting_status,'line_count',line_count,'total_units',total_units,'inventory_changed',false);
end $$;
revoke all on function public.mme_warehouse_stage_fulfillment(uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_warehouse_stage_fulfillment(uuid,text,text,text,text,uuid) to service_role;
do $$declare t text;begin foreach t in array array['mme_warehouse_fulfillment_jobs','mme_warehouse_fulfillment_job_lines','mme_warehouse_inventory_posting_queue','mme_warehouse_fulfillment_events'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
commit;