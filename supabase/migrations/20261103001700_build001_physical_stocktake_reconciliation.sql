-- Build 001: blind cycle counts, physical inventory reconciliation and variance audit.
-- Aggregate inventory only; serialized units are counted by their individual unit workflow.

create table public.mme_inventory_count_sessions (
 id uuid primary key default gen_random_uuid(),
 count_reference text not null unique,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 status text not null default 'draft' check(status in ('draft','open','submitted','approved','rejected','applied','cancelled')),
 count_mode text not null default 'blind' check(count_mode in ('blind','guided')),
 scope jsonb not null default '{}'::jsonb check(jsonb_typeof(scope)='object'),
 started_by_identity_id uuid not null,
 submitted_by_identity_id uuid,
 approved_by_identity_id uuid,
 applied_by_identity_id uuid,
 started_at timestamptz,
 submitted_at timestamptz,
 approved_at timestamptz,
 applied_at timestamptz,
 decision_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.mme_inventory_count_lines (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.mme_inventory_count_sessions(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 expected_quantity integer not null check(expected_quantity>=0),
 counted_quantity integer check(counted_quantity is null or counted_quantity>=0),
 variance_quantity integer generated always as (case when counted_quantity is null then null else counted_quantity-expected_quantity end) stored,
 average_unit_cost_cents bigint not null check(average_unit_cost_cents>=0),
 counted_by_identity_id uuid,
 counted_at timestamptz,
 note text,
 unique(session_id,product_id)
);

create table public.mme_inventory_count_events (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.mme_inventory_count_sessions(id) on delete restrict,
 event_type text not null check(event_type in ('created','opened','counted','submitted','approved','rejected','applied','cancelled')),
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 actor_identity_id uuid not null,
 created_at timestamptz not null default now()
);

create index mme_inventory_count_sessions_status_idx on public.mme_inventory_count_sessions(status,created_at desc);
create index mme_inventory_count_lines_session_idx on public.mme_inventory_count_lines(session_id,counted_at);
create index mme_inventory_count_lines_variance_idx on public.mme_inventory_count_lines(session_id,variance_quantity) where variance_quantity is not null;

alter table public.mme_inventory_count_sessions enable row level security;
alter table public.mme_inventory_count_lines enable row level security;
alter table public.mme_inventory_count_events enable row level security;
revoke all on public.mme_inventory_count_sessions,public.mme_inventory_count_lines,public.mme_inventory_count_events from anon,authenticated;
grant all on public.mme_inventory_count_sessions,public.mme_inventory_count_lines,public.mme_inventory_count_events to service_role;

create or replace function public.mme_start_inventory_count(
 p_count_reference text,p_location_id uuid,p_count_mode text,p_scope jsonb,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_item record;
begin
 if p_count_reference is null or length(btrim(p_count_reference)) not between 3 and 80
  or p_location_id is null or p_count_mode not in ('blind','guided')
  or p_scope is null or jsonb_typeof(p_scope)<>'object' or p_actor_identity_id is null then
  raise exception 'Invalid stocktake request' using errcode='22023';
 end if;
 perform 1 from public.mme_store_locations where id=p_location_id and active=true;
 if not found then raise exception 'Active location required' using errcode='P0002'; end if;
 insert into public.mme_inventory_count_sessions(count_reference,location_id,count_mode,scope,started_by_identity_id,status,started_at)
 values(upper(btrim(p_count_reference)),p_location_id,p_count_mode,p_scope,p_actor_identity_id,'open',now())
 returning id into v_id;
 for v_item in
  select p.id,coalesce(b.on_hand_quantity,0) as qty,coalesce(b.average_unit_cost_cents,0) as unit_cost
  from public.mme_products p
  left join public.mme_inventory_balances b on b.product_id=p.id and b.location_id=p_location_id
  where p.active=true and p.serialized=false
   and (not (p_scope ? 'category_key') or p.category_key=p_scope->>'category_key')
  order by p.sku
 loop
  insert into public.mme_inventory_count_lines(session_id,product_id,expected_quantity,average_unit_cost_cents)
  values(v_id,v_item.id,v_item.qty,v_item.unit_cost);
 end loop;
 insert into public.mme_inventory_count_events(session_id,event_type,event_data,actor_identity_id)
 values(v_id,'opened',jsonb_build_object('count_mode',p_count_mode,'line_count',(select count(*) from public.mme_inventory_count_lines where session_id=v_id)),p_actor_identity_id);
 return v_id;
end; $$;

create or replace function public.mme_record_inventory_count(
 p_session_id uuid,p_product_id uuid,p_counted_quantity integer,p_note text,p_actor_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_status text;
begin
 if p_session_id is null or p_product_id is null or p_counted_quantity is null or p_counted_quantity<0 or p_actor_identity_id is null then
  raise exception 'Invalid physical count' using errcode='22023';
 end if;
 select status into v_status from public.mme_inventory_count_sessions where id=p_session_id for update;
 if not found or v_status<>'open' then return false; end if;
 update public.mme_inventory_count_lines set counted_quantity=p_counted_quantity,
  counted_by_identity_id=p_actor_identity_id,counted_at=now(),note=left(p_note,500)
 where session_id=p_session_id and product_id=p_product_id;
 if not found then return false; end if;
 insert into public.mme_inventory_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,'counted',jsonb_build_object('product_id',p_product_id,'counted_quantity',p_counted_quantity),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_submit_inventory_count(
 p_session_id uuid,p_actor_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if p_actor_identity_id is null then raise exception 'Actor required' using errcode='22023'; end if;
 update public.mme_inventory_count_sessions set status='submitted',submitted_by_identity_id=p_actor_identity_id,
  submitted_at=now(),updated_at=now()
 where id=p_session_id and status='open'
  and exists(select 1 from public.mme_inventory_count_lines where session_id=p_session_id)
  and not exists(select 1 from public.mme_inventory_count_lines where session_id=p_session_id and counted_quantity is null);
 if not found then return false; end if;
 insert into public.mme_inventory_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,'submitted',jsonb_build_object('variance_lines',(select count(*) from public.mme_inventory_count_lines where session_id=p_session_id and variance_quantity<>0)),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_decide_inventory_count(
 p_session_id uuid,p_decision text,p_actor_identity_id uuid,p_note text
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if p_decision not in ('approved','rejected') or p_actor_identity_id is null or p_note is null or length(btrim(p_note))<3 then
  raise exception 'Valid count decision and note required' using errcode='22023';
 end if;
 update public.mme_inventory_count_sessions set status=p_decision,approved_by_identity_id=p_actor_identity_id,
  approved_at=now(),decision_note=btrim(p_note),updated_at=now()
 where id=p_session_id and status='submitted';
 if not found then return false; end if;
 insert into public.mme_inventory_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,p_decision,jsonb_build_object('note',btrim(p_note)),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_apply_inventory_count(
 p_session_id uuid,p_actor_identity_id uuid,p_approved_by_identity_id uuid
) returns integer language plpgsql security definer set search_path=''
as $$
declare v_session record; v_line record; v_delta integer; v_applied integer:=0;
begin
 select * into v_session from public.mme_inventory_count_sessions where id=p_session_id for update;
 if not found or v_session.status<>'approved' then raise exception 'Count must be approved before applying' using errcode='P0001'; end if;
 if p_actor_identity_id is null or p_approved_by_identity_id is null
  or p_approved_by_identity_id<>v_session.approved_by_identity_id then
  raise exception 'Verified approver attribution required' using errcode='22023';
 end if;
 for v_line in
  select cl.*,b.on_hand_quantity as current_quantity
  from public.mme_inventory_count_lines cl
  left join public.mme_inventory_balances b on b.product_id=cl.product_id and b.location_id=v_session.location_id
  where cl.session_id=p_session_id and cl.counted_quantity is not null
    and cl.counted_quantity<>coalesce(b.on_hand_quantity,0)
  order by cl.product_id
  for update of cl
 loop
  v_delta:=v_line.counted_quantity-coalesce(v_line.current_quantity,0);
  if v_delta<>0 then
   perform public.mme_adjust_inventory(v_line.product_id,v_session.location_id,v_delta,
    'Approved physical stocktake variance: '||v_session.count_reference,
    v_session.count_reference,p_actor_identity_id,p_approved_by_identity_id,v_line.average_unit_cost_cents);
   v_applied:=v_applied+1;
  end if;
 end loop;
 update public.mme_inventory_count_sessions set status='applied',applied_by_identity_id=p_actor_identity_id,
  applied_at=now(),updated_at=now() where id=p_session_id and status='approved';
 insert into public.mme_inventory_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,'applied',jsonb_build_object('adjustment_lines',v_applied),p_actor_identity_id);
 return v_applied;
end; $$;

revoke all on function public.mme_start_inventory_count(text,uuid,text,jsonb,uuid) from public,anon,authenticated;
revoke all on function public.mme_record_inventory_count(uuid,uuid,integer,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_submit_inventory_count(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_decide_inventory_count(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_apply_inventory_count(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_start_inventory_count(text,uuid,text,jsonb,uuid) to service_role;
grant execute on function public.mme_record_inventory_count(uuid,uuid,integer,text,uuid) to service_role;
grant execute on function public.mme_submit_inventory_count(uuid,uuid) to service_role;
grant execute on function public.mme_decide_inventory_count(uuid,text,uuid,text) to service_role;
grant execute on function public.mme_apply_inventory_count(uuid,uuid,uuid) to service_role;

comment on table public.mme_inventory_count_sessions is 'Blind/guided aggregate physical stocktake sessions with explicit approval before ledger reconciliation.';
comment on table public.mme_inventory_count_lines is 'Expected and physically counted quantities with immutable count session context.';
