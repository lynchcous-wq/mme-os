-- Build 001: customer return authorization, received-item inspection gate, and verified refund ledger.
-- Refund execution is performed by a trusted payment adapter; this migration records approval/outcomes.

create table public.mme_return_cases (
 id uuid primary key default gen_random_uuid(),
 return_reference text not null unique,
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 status text not null default 'requested'
  check(status in ('requested','authorized','in_transit','received','inspection_pending','partially_resolved','resolved','rejected','cancelled')),
 return_reason text not null check(length(btrim(return_reason)) between 5 and 1000),
 opened_by_identity_id uuid not null,
 authorized_by_identity_id uuid,
 received_by_identity_id uuid,
 received_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_return_cases_order_idx on public.mme_return_cases(order_id,created_at desc);
create index mme_return_cases_status_idx on public.mme_return_cases(status,created_at);

create table public.mme_return_case_lines (
 id uuid primary key default gen_random_uuid(),
 return_case_id uuid not null references public.mme_return_cases(id) on delete restrict,
 order_line_id uuid not null references public.mme_order_lines(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 quantity integer not null check(quantity>0),
 serialized_unit_id uuid references public.mme_serialized_units(id) on delete restrict,
 serial_snapshot text,
 imei_snapshot text,
 line_total_snapshot_cents bigint not null check(line_total_snapshot_cents>=0),
 return_status text not null default 'requested'
  check(return_status in ('requested','authorized','received','inspection_pending','restocked','repair','quarantine','write_off','rejected')),
 inspection_id uuid references public.mme_inventory_inspections(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(return_case_id,order_line_id),
 check(serialized_unit_id is null or quantity=1)
);
create index mme_return_case_lines_order_line_idx on public.mme_return_case_lines(order_line_id);

create table public.mme_return_refund_approvals (
 id uuid primary key default gen_random_uuid(),
 return_case_id uuid not null unique references public.mme_return_cases(id) on delete restrict,
 approved_amount_cents bigint not null check(approved_amount_cents>0),
 currency text not null default 'USD' check(currency='USD'),
 decision text not null check(decision in ('approved','rejected','held')),
 reason text not null check(length(btrim(reason))>=5),
 requested_by_identity_id uuid not null,
 decided_by_identity_id uuid not null,
 decided_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 check(requested_by_identity_id<>decided_by_identity_id)
);
create table public.mme_return_refund_events (
 id uuid primary key default gen_random_uuid(),
 approval_id uuid not null references public.mme_return_refund_approvals(id) on delete restrict,
 provider text not null check(provider in ('stripe','manual','bank')),
 provider_event_id text not null,
 provider_refund_id text,
 event_type text not null check(event_type in ('refund_submitted','refund_succeeded','refund_failed','refund_reversed')),
 amount_cents bigint not null check(amount_cents>0),
 currency text not null default 'USD' check(currency='USD'),
 payload_sha256 text,
 actor_identity_id uuid not null,
 occurred_at timestamptz not null default now(),
 unique(provider,provider_event_id)
);
create index mme_return_refund_events_approval_idx on public.mme_return_refund_events(approval_id,occurred_at desc);

alter table public.mme_return_cases enable row level security;
alter table public.mme_return_case_lines enable row level security;
alter table public.mme_return_refund_approvals enable row level security;
alter table public.mme_return_refund_events enable row level security;
revoke all on public.mme_return_cases,public.mme_return_case_lines,
 public.mme_return_refund_approvals,public.mme_return_refund_events from public,anon,authenticated;
grant all on public.mme_return_cases,public.mme_return_case_lines,
 public.mme_return_refund_approvals,public.mme_return_refund_events to service_role;

create or replace function public.mme_open_return_case(
 p_reference text,p_order_id uuid,p_reason text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_order public.mme_orders%rowtype; v_id uuid;
begin
 if p_reference is null or length(btrim(p_reference)) not between 3 and 100
  or p_order_id is null or p_reason is null or length(btrim(p_reason)) not between 5 and 1000
  or p_actor_identity_id is null then raise exception 'Invalid return case' using errcode='22023'; end if;
 select * into v_order from public.mme_orders where id=p_order_id for update;
 if not found or v_order.status not in ('paid','fulfilled','partially_refunded') then
  raise exception 'Only completed paid orders can be returned' using errcode='23514';
 end if;
 insert into public.mme_return_cases(return_reference,order_id,return_reason,opened_by_identity_id)
 values(btrim(p_reference),p_order_id,btrim(p_reason),p_actor_identity_id) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_add_return_case_line(
 p_return_case_id uuid,p_order_line_id uuid,p_quantity integer,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_case public.mme_return_cases%rowtype; v_line public.mme_order_lines%rowtype;
 v_product public.mme_products%rowtype; v_returned bigint; v_id uuid; v_unit public.mme_serialized_units%rowtype;
begin
 if p_return_case_id is null or p_order_line_id is null or p_quantity is null or p_quantity<1
  or p_actor_identity_id is null then raise exception 'Invalid return line' using errcode='22023'; end if;
 select * into v_case from public.mme_return_cases where id=p_return_case_id for update;
 if not found or v_case.status not in ('requested','authorized') then
  raise exception 'Return case is not editable' using errcode='23514'; end if;
 select * into v_line from public.mme_order_lines where id=p_order_line_id and order_id=v_case.order_id for update;
 if not found then raise exception 'Order line does not belong to return order' using errcode='23503'; end if;
 select * into v_product from public.mme_products where id=v_line.product_id;
 select coalesce(sum(rl.quantity),0) into v_returned
 from public.mme_return_case_lines rl join public.mme_return_cases rc on rc.id=rl.return_case_id
 where rl.order_line_id=p_order_line_id and rc.status not in ('rejected','cancelled');
 if v_returned+p_quantity>v_line.quantity then
  raise exception 'Requested return exceeds purchased quantity' using errcode='23514'; end if;
 if v_line.serialized_unit_id is not null then
  if p_quantity<>1 then raise exception 'Serialized return quantity must be one' using errcode='23514'; end if;
  select * into v_unit from public.mme_serialized_units where id=v_line.serialized_unit_id for update;
  if not found or v_unit.unit_status not in ('sold','repair','quarantine') then
   raise exception 'Serialized unit is not eligible for return intake' using errcode='23514'; end if;
  if exists(select 1 from public.mme_return_case_lines where serialized_unit_id=v_unit.id
   and return_status not in ('rejected')) then raise exception 'Serialized unit already has a return record' using errcode='23505'; end if;
 end if;
 insert into public.mme_return_case_lines(return_case_id,order_line_id,product_id,location_id,
  quantity,serialized_unit_id,serial_snapshot,imei_snapshot,line_total_snapshot_cents)
 values(p_return_case_id,p_order_line_id,v_line.product_id,v_line.location_id,p_quantity,
  v_line.serialized_unit_id,v_line.serial_number_snapshot,v_line.imei_snapshot,
  (v_line.line_total_cents::numeric*p_quantity/v_line.quantity)::bigint)
 returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_receive_return_case(
 p_return_case_id uuid,p_receiver_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if p_return_case_id is null or p_receiver_identity_id is null then
  raise exception 'Invalid return receipt' using errcode='22023'; end if;
 perform 1 from public.mme_return_cases where id=p_return_case_id and status in ('authorized','in_transit') for update;
 if not found then raise exception 'Return must be authorized before receipt' using errcode='23514'; end if;
 if not exists(select 1 from public.mme_return_case_lines where return_case_id=p_return_case_id) then
  raise exception 'Return case has no lines' using errcode='23514'; end if;
 update public.mme_return_cases set status='inspection_pending',received_by_identity_id=p_receiver_identity_id,
  received_at=now(),updated_at=now() where id=p_return_case_id;
 update public.mme_return_case_lines set return_status='inspection_pending',updated_at=now()
  where return_case_id=p_return_case_id and return_status in ('requested','authorized');
 return true;
end; $$;

create or replace function public.mme_approve_return_refund(
 p_return_case_id uuid,p_amount_cents bigint,p_requested_by_identity_id uuid,
 p_decided_by_identity_id uuid,p_decision text,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_case public.mme_return_cases%rowtype; v_order public.mme_orders%rowtype; v_id uuid;
 v_cap numeric;
begin
 if p_return_case_id is null or p_amount_cents is null or p_amount_cents<=0
  or p_requested_by_identity_id is null or p_decided_by_identity_id is null
  or p_requested_by_identity_id=p_decided_by_identity_id
  or p_decision not in ('approved','rejected','held') or p_reason is null or length(btrim(p_reason))<5 then
  raise exception 'Invalid return refund approval' using errcode='22023'; end if;
 select * into v_case from public.mme_return_cases where id=p_return_case_id for update;
 if not found or v_case.status in ('rejected','cancelled') then
  raise exception 'Return case is not eligible for refund review' using errcode='23514'; end if;
 select * into v_order from public.mme_orders where id=v_case.order_id;
 select coalesce(sum(line_total_snapshot_cents),0) into v_cap
 from public.mme_return_case_lines where return_case_id=p_return_case_id
  and return_status not in ('rejected');
 if p_amount_cents>v_cap or p_amount_cents>v_order.total_cents then
  raise exception 'Refund exceeds returned line value or original order total' using errcode='23514'; end if;
 insert into public.mme_return_refund_approvals(return_case_id,approved_amount_cents,decision,
  reason,requested_by_identity_id,decided_by_identity_id)
 values(p_return_case_id,p_amount_cents,p_decision,btrim(p_reason),
  p_requested_by_identity_id,p_decided_by_identity_id) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_record_return_refund_event(
 p_approval_id uuid,p_provider text,p_provider_event_id text,p_provider_refund_id text,
 p_event_type text,p_amount_cents bigint,p_currency text,p_payload_sha256 text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_approval public.mme_return_refund_approvals%rowtype; v_event uuid;
begin
 if p_approval_id is null or p_provider not in ('stripe','manual','bank')
  or p_provider_event_id is null or length(btrim(p_provider_event_id)) not between 1 and 180
  or p_event_type not in ('refund_submitted','refund_succeeded','refund_failed','refund_reversed')
  or p_amount_cents is null or p_amount_cents<=0 or lower(coalesce(p_currency,''))<>'usd'
  or p_actor_identity_id is null or p_payload_sha256 is null
  or p_payload_sha256 !~ '^[0-9a-fA-F]{64}$' then
  raise exception 'Invalid verified refund event' using errcode='22023'; end if;
 select * into v_approval from public.mme_return_refund_approvals where id=p_approval_id for update;
 if not found or v_approval.decision<>'approved' or v_approval.currency<>'USD'
  or p_amount_cents<>v_approval.approved_amount_cents then
  raise exception 'Refund event does not match approved amount' using errcode='23514'; end if;
 insert into public.mme_return_refund_events(approval_id,provider,provider_event_id,provider_refund_id,
  event_type,amount_cents,currency,payload_sha256,actor_identity_id)
 values(p_approval_id,p_provider,btrim(p_provider_event_id),left(p_provider_refund_id,180),
  p_event_type,p_amount_cents,'USD',lower(p_payload_sha256),p_actor_identity_id)
 on conflict(provider,provider_event_id) do nothing returning id into v_event;
 if v_event is null then
  select id into v_event from public.mme_return_refund_events
   where provider=p_provider and provider_event_id=btrim(p_provider_event_id);
  return v_event;
 end if;
 return v_event;
end; $$;

revoke all on function public.mme_open_return_case(text,uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_add_return_case_line(uuid,uuid,integer,uuid) from public,anon,authenticated;
revoke all on function public.mme_receive_return_case(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_approve_return_refund(uuid,bigint,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_record_return_refund_event(uuid,text,text,text,text,bigint,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_open_return_case(text,uuid,text,uuid) to service_role;
grant execute on function public.mme_add_return_case_line(uuid,uuid,integer,uuid) to service_role;
grant execute on function public.mme_receive_return_case(uuid,uuid) to service_role;
grant execute on function public.mme_approve_return_refund(uuid,bigint,uuid,uuid,text,text) to service_role;
grant execute on function public.mme_record_return_refund_event(uuid,text,text,text,text,bigint,text,text,uuid) to service_role;

comment on table public.mme_return_cases is 'RMA lifecycle tied to completed MME orders; returned goods remain unavailable until inspection disposition.';
comment on table public.mme_return_refund_events is 'Idempotent verified refund-provider event ledger; does not itself initiate a refund.';
