begin;
create table if not exists public.mme_inventory_stock_balances(
 stock_balance_id uuid primary key default gen_random_uuid(),
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 quantity_on_hand integer not null default 0 check(quantity_on_hand>=0),
 quantity_reserved integer not null default 0 check(quantity_reserved>=0 and quantity_reserved<=quantity_on_hand),
 version bigint not null default 1 check(version>0),
 updated_at timestamptz not null default now(),
 unique(inventory_item_id,location_id)
);
create table if not exists public.mme_inventory_movements(
 movement_id uuid primary key default gen_random_uuid(),
 movement_number text not null unique,
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 movement_type text not null check(movement_type in('opening_balance','fulfillment_sale','count_adjustment','reservation_release','return_receipt','transfer_out','transfer_in')),
 quantity_delta integer not null check(quantity_delta<>0),
 quantity_before integer not null check(quantity_before>=0),
 quantity_after integer not null check(quantity_after>=0),
 source_type text not null,
 source_reference text not null,
 fulfillment_job_id uuid references public.mme_warehouse_fulfillment_jobs(fulfillment_job_id) on delete restrict,
 idempotency_key text not null unique,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 check(quantity_after=quantity_before+quantity_delta)
);
create index if not exists mme_inventory_movements_item_location_idx on public.mme_inventory_movements(inventory_item_id,location_id,created_at desc);
create table if not exists public.mme_inventory_reservations(
 reservation_id uuid primary key default gen_random_uuid(),
 fulfillment_job_id uuid not null references public.mme_warehouse_fulfillment_jobs(fulfillment_job_id) on delete restrict,
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 quantity integer not null check(quantity>0),
 reservation_status text not null check(reservation_status in('reserved','consumed','released')),
 idempotency_key text not null unique,
 reserved_at timestamptz not null default now(),
 finalized_at timestamptz,
 actor_auth_user_id uuid not null
);
create index if not exists mme_inventory_reservations_job_idx on public.mme_inventory_reservations(fulfillment_job_id,reservation_status);
create table if not exists public.mme_inventory_count_sessions(
 count_session_id uuid primary key default gen_random_uuid(),
 count_number text not null unique,
 location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 count_status text not null default 'draft' check(count_status in('draft','submitted','posted','cancelled')),
 opened_by_auth_user_id uuid not null,
 submitted_by_auth_user_id uuid,
 posted_by_auth_user_id uuid,
 opened_at timestamptz not null default now(),
 submitted_at timestamptz,
 posted_at timestamptz
);
create table if not exists public.mme_inventory_count_lines(
 count_line_id uuid primary key default gen_random_uuid(),
 count_session_id uuid not null references public.mme_inventory_count_sessions(count_session_id) on delete restrict,
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 counted_quantity integer not null check(counted_quantity>=0),
 system_quantity_at_count integer check(system_quantity_at_count>=0),
 variance integer,
 unique(count_session_id,inventory_item_id)
);
create table if not exists public.mme_inventory_reconciliation_events(
 reconciliation_event_id uuid primary key default gen_random_uuid(),
 count_session_id uuid not null references public.mme_inventory_count_sessions(count_session_id) on delete restrict,
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 system_quantity integer not null,
 counted_quantity integer not null,
 variance integer not null,
 movement_id uuid references public.mme_inventory_movements(movement_id) on delete restrict,
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create or replace function public.mme_inventory_post_fulfillment(p_job uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare j public.mme_warehouse_fulfillment_jobs%rowtype; q public.mme_warehouse_inventory_posting_queue%rowtype; l record; bal public.mme_inventory_stock_balances%rowtype; before_qty integer; after_qty integer; n integer:=0; total integer:=0; movement_ref text;
begin
 if p_job is null or p_actor is null then raise exception 'posting_job_and_actor_required'; end if;
 select * into j from public.mme_warehouse_fulfillment_jobs where fulfillment_job_id=p_job for update;
 if not found then raise exception 'fulfillment_job_not_found'; end if;
 select * into q from public.mme_warehouse_inventory_posting_queue where fulfillment_job_id=p_job for update;
 if not found then raise exception 'posting_queue_not_found'; end if;
 if q.posting_status='posted' or j.inventory_posting_status='posted' then return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','idempotent_replay',true,'inventory_changed',false); end if;
 if j.fulfillment_status in('cancelled','shipped') or (j.fulfillment_status='blocked' and j.inventory_posting_status<>'failed') then raise exception 'fulfillment_job_not_postable'; end if;
 if j.source_type<>'customer_order' then raise exception 'source_type_requires_specialized_inventory_workflow'; end if;
 if q.posting_status not in('pending','failed','processing') then raise exception 'posting_queue_not_retryable'; end if;
 update public.mme_warehouse_inventory_posting_queue set posting_status='processing',attempt_count=attempt_count+1,last_attempt_at=now(),updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
 update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='processing',updated_at=now() where fulfillment_job_id=p_job;
 begin
  if exists(select 1 from public.mme_warehouse_fulfillment_job_lines fl join public.mme_inventory_items i on i.inventory_item_id=fl.inventory_item_id where fl.fulfillment_job_id=p_job and (coalesce(i.track_serial,false) or coalesce(i.track_imei,false))) then raise exception 'serialized_inventory_requires_unit_level_scan_manifest'; end if;
  if not exists(select 1 from public.mme_warehouse_fulfillment_job_lines where fulfillment_job_id=p_job) then raise exception 'fulfillment_has_no_lines'; end if;
  for l in select fl.*,i.sku from public.mme_warehouse_fulfillment_job_lines fl join public.mme_inventory_items i on i.inventory_item_id=fl.inventory_item_id where fl.fulfillment_job_id=p_job order by fl.inventory_item_id,fl.source_location_id,fl.fulfillment_job_line_id
  loop
   select * into bal from public.mme_inventory_stock_balances where inventory_item_id=l.inventory_item_id and location_id=l.source_location_id for update;
   if not found then raise exception 'inventory_balance_not_initialized_for_sku_%',l.sku; end if;
   before_qty:=bal.quantity_on_hand;
   if before_qty-bal.quantity_reserved<l.fulfilled_quantity then raise exception 'insufficient_available_stock_for_sku_%',l.sku; end if;
   after_qty:=before_qty-l.fulfilled_quantity;
   update public.mme_inventory_stock_balances set quantity_on_hand=after_qty,version=version+1,updated_at=now() where stock_balance_id=bal.stock_balance_id;
   insert into public.mme_inventory_reservations(fulfillment_job_id,inventory_item_id,location_id,quantity,reservation_status,idempotency_key,finalized_at,actor_auth_user_id)
   values(p_job,l.inventory_item_id,l.source_location_id,l.fulfilled_quantity,'consumed','fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,now(),p_actor);
   insert into public.mme_inventory_movements(movement_number,inventory_item_id,location_id,movement_type,quantity_delta,quantity_before,quantity_after,source_type,source_reference,fulfillment_job_id,idempotency_key,actor_auth_user_id)
   values('FUL-'||replace(gen_random_uuid()::text,'-',''),l.inventory_item_id,l.source_location_id,'fulfillment_sale',-l.fulfilled_quantity,before_qty,after_qty,j.source_type,j.source_reference,p_job,'fulfillment:'||p_job::text||':'||l.fulfillment_job_line_id::text,p_actor)
   returning movement_number into movement_ref;
   n:=n+1;total:=total+l.fulfilled_quantity;
  end loop;
  update public.mme_warehouse_inventory_posting_queue set posting_status='posted',posted_movement_reference='fulfillment:'||p_job::text,updated_at=now(),error_code=null,error_detail=null where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='posted',fulfillment_status='inventory_posted',inventory_posted_at=now(),failure_code=null,failure_detail=null,updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'inventory_posted',format('Atomically posted %s inventory movement lines totaling %s units.',n,total),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','posted','movement_lines',n,'units_posted',total,'inventory_changed',true,'idempotent_replay',false);
 exception when others then
  update public.mme_warehouse_inventory_posting_queue set posting_status='failed',error_code=sqlstate,error_detail=left(sqlerrm,500),updated_at=now() where posting_id=q.posting_id;
  update public.mme_warehouse_fulfillment_jobs set inventory_posting_status='failed',fulfillment_status='blocked',failure_code=sqlstate,failure_detail=left(sqlerrm,500),updated_at=now() where fulfillment_job_id=p_job;
  insert into public.mme_warehouse_fulfillment_events(fulfillment_job_id,event_type,event_detail,actor_auth_user_id) values(p_job,'posting_failed',left(sqlerrm,500),p_actor);
  return jsonb_build_object('fulfillment_job_id',p_job,'status','failed','error_code',sqlstate,'error',left(sqlerrm,500),'inventory_changed',false);
 end;
end $$;
create or replace function public.mme_inventory_submit_count(p_session uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.mme_inventory_count_sessions%rowtype; n integer;
begin
 select * into s from public.mme_inventory_count_sessions where count_session_id=p_session for update;
 if not found then raise exception 'count_session_not_found'; end if;
 if s.count_status<>'draft' then raise exception 'count_session_not_draft'; end if;
 select count(*) into n from public.mme_inventory_count_lines where count_session_id=p_session;
 if n=0 then raise exception 'count_session_empty'; end if;
 update public.mme_inventory_count_lines cl set system_quantity_at_count=coalesce((select b.quantity_on_hand from public.mme_inventory_stock_balances b where b.location_id=s.location_id and b.inventory_item_id=cl.inventory_item_id),0),variance=cl.counted_quantity-coalesce((select b.quantity_on_hand from public.mme_inventory_stock_balances b where b.location_id=s.location_id and b.inventory_item_id=cl.inventory_item_id),0) where cl.count_session_id=p_session;
 update public.mme_inventory_count_sessions set count_status='submitted',submitted_by_auth_user_id=p_actor,submitted_at=now() where count_session_id=p_session;
 return jsonb_build_object('count_session_id',p_session,'status','submitted','lines',n);
end $$;
create or replace function public.mme_inventory_post_count(p_session uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.mme_inventory_count_sessions%rowtype; l record; b public.mme_inventory_stock_balances%rowtype; delta integer; n integer:=0;
begin
 select * into s from public.mme_inventory_count_sessions where count_session_id=p_session for update;
 if not found then raise exception 'count_session_not_found'; end if;
 if s.count_status='posted' then return jsonb_build_object('count_session_id',p_session,'status','posted','idempotent_replay',true); end if;
 if s.count_status<>'submitted' then raise exception 'count_session_not_submitted'; end if;
 for l in select * from public.mme_inventory_count_lines where count_session_id=p_session order by inventory_item_id loop
  select * into b from public.mme_inventory_stock_balances where inventory_item_id=l.inventory_item_id and location_id=s.location_id for update;
  if not found then
   insert into public.mme_inventory_stock_balances(inventory_item_id,location_id,quantity_on_hand,quantity_reserved) values(l.inventory_item_id,s.location_id,0,0) returning * into b;
  end if;
  delta:=l.counted_quantity-b.quantity_on_hand;
  if delta<0 and b.quantity_on_hand+delta<b.quantity_reserved then raise exception 'count_would_reduce_stock_below_reserved_quantity'; end if;
  if delta<>0 then
   update public.mme_inventory_stock_balances set quantity_on_hand=l.counted_quantity,version=version+1,updated_at=now() where stock_balance_id=b.stock_balance_id;
   insert into public.mme_inventory_movements(movement_number,inventory_item_id,location_id,movement_type,quantity_delta,quantity_before,quantity_after,source_type,source_reference,idempotency_key,actor_auth_user_id)
   values('CNT-'||replace(gen_random_uuid()::text,'-',''),l.inventory_item_id,s.location_id,'count_adjustment',delta,b.quantity_on_hand,l.counted_quantity,'cycle_count',s.count_number,'count:'||p_session::text||':'||l.inventory_item_id::text,p_actor);
  end if;
  insert into public.mme_inventory_reconciliation_events(count_session_id,inventory_item_id,location_id,system_quantity,counted_quantity,variance,actor_auth_user_id)
  values(p_session,l.inventory_item_id,s.location_id,b.quantity_on_hand,l.counted_quantity,delta,p_actor);
  n:=n+1;
 end loop;
 update public.mme_inventory_count_sessions set count_status='posted',posted_by_auth_user_id=p_actor,posted_at=now() where count_session_id=p_session;
 return jsonb_build_object('count_session_id',p_session,'status','posted','lines_reconciled',n,'idempotent_replay',false);
end $$;
revoke all on function public.mme_inventory_post_fulfillment(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_submit_count(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_inventory_post_count(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_inventory_post_fulfillment(uuid,uuid) to service_role;
grant execute on function public.mme_inventory_submit_count(uuid,uuid) to service_role;
grant execute on function public.mme_inventory_post_count(uuid,uuid) to service_role;
do $$declare t text;begin foreach t in array array['mme_inventory_stock_balances','mme_inventory_movements','mme_inventory_reservations','mme_inventory_count_sessions','mme_inventory_count_lines','mme_inventory_reconciliation_events'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
commit;