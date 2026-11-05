-- Build 009.14: associate-assigned cash drawer sessions, immutable cash ledger and closeout.
-- Additive only. Amounts are minor currency units; no hardware commands are issued here.
begin;

create table public.mme_pos_cash_drawer_sessions (
  id uuid primary key default gen_random_uuid(),
  register_reference text not null check(length(btrim(register_reference)) between 1 and 80),
  location_id uuid not null,
  assigned_person_id uuid not null,
  opened_by_person_id uuid not null,
  currency text not null check(currency ~ '^[A-Z]{3}$'),
  opening_float_minor bigint not null check(opening_float_minor >= 0),
  expected_cash_minor bigint not null default 0,
  counted_cash_minor bigint,
  variance_minor bigint,
  status text not null default 'open' check(status in ('open','closed','review_required')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_by_person_id uuid,
  closeout_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status='open' and closed_at is null and counted_cash_minor is null)
      or (status<>'open' and closed_at is not null and counted_cash_minor is not null))
);
create unique index mme_pos_one_open_drawer_per_register
  on public.mme_pos_cash_drawer_sessions(register_reference) where status='open';
create unique index mme_pos_one_open_drawer_per_associate
  on public.mme_pos_cash_drawer_sessions(assigned_person_id) where status='open';
create index mme_pos_drawer_location_status_idx
  on public.mme_pos_cash_drawer_sessions(location_id,status,opened_at desc);

create table public.mme_pos_cash_drawer_movements (
  id uuid primary key default gen_random_uuid(),
  drawer_session_id uuid not null references public.mme_pos_cash_drawer_sessions(id) on delete restrict,
  movement_type text not null check(movement_type in (
    'opening_float','cash_in','cash_out','cash_sale','cash_refund','adjustment_in','adjustment_out'
  )),
  amount_minor bigint not null check(amount_minor>0),
  currency text not null check(currency ~ '^[A-Z]{3}$'),
  reason_code text not null,
  reason_detail text,
  actor_person_id uuid not null,
  source_tender_attempt_id uuid references public.mme_pos_tender_attempts(id) on delete restrict,
  source_refund_request_id uuid references public.mme_pos_refund_requests(id) on delete restrict,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  unique(drawer_session_id,idempotency_key),
  check ((movement_type='cash_sale' and source_tender_attempt_id is not null and source_refund_request_id is null)
      or (movement_type='cash_refund' and source_refund_request_id is not null and source_tender_attempt_id is null)
      or (movement_type not in ('cash_sale','cash_refund') and source_tender_attempt_id is null and source_refund_request_id is null))
);
create unique index mme_pos_drawer_tender_sale_once
  on public.mme_pos_cash_drawer_movements(source_tender_attempt_id)
  where source_tender_attempt_id is not null;
create unique index mme_pos_drawer_refund_once
  on public.mme_pos_cash_drawer_movements(source_refund_request_id)
  where source_refund_request_id is not null;
create index mme_pos_drawer_movement_history_idx
  on public.mme_pos_cash_drawer_movements(drawer_session_id,created_at);

create table public.mme_pos_cash_adjustment_requests (
  id uuid primary key default gen_random_uuid(),
  drawer_session_id uuid not null references public.mme_pos_cash_drawer_sessions(id) on delete restrict,
  direction text not null check(direction in ('in','out')),
  amount_minor bigint not null check(amount_minor>0),
  currency text not null check(currency ~ '^[A-Z]{3}$'),
  reason_code text not null,
  reason_detail text,
  requested_by_person_id uuid not null,
  decided_by_person_id uuid,
  decision text check(decision in ('approved','rejected')),
  decision_reason text,
  status text not null default 'requested' check(status in ('requested','approved','rejected')),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  unique(drawer_session_id,idempotency_key),
  check(decided_by_person_id is null or decided_by_person_id<>requested_by_person_id),
  check ((status='requested' and decided_by_person_id is null and decided_at is null)
      or (status<>'requested' and decided_by_person_id is not null and decided_at is not null))
);

alter table public.mme_pos_cash_drawer_sessions enable row level security;
alter table public.mme_pos_cash_drawer_movements enable row level security;
alter table public.mme_pos_cash_adjustment_requests enable row level security;
revoke all on public.mme_pos_cash_drawer_sessions,public.mme_pos_cash_drawer_movements,
  public.mme_pos_cash_adjustment_requests from public,anon,authenticated;
grant all on public.mme_pos_cash_drawer_sessions,public.mme_pos_cash_drawer_movements,
  public.mme_pos_cash_adjustment_requests to service_role;

create or replace function public.mme_pos_authorize_drawer_action(
  p_actor_person_id uuid,p_permission_key text,p_location_id uuid
) returns boolean
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_person_status text; v_ceo_person_id uuid; v_frozen boolean; v_employment_status text;
begin
  if p_actor_person_id is null or p_location_id is null or p_permission_key not in (
    'pos.drawer.open','pos.drawer.close','pos.drawer.cash_in','pos.drawer.cash_out',
    'pos.drawer.adjust.request','pos.drawer.adjust.approve','pos.drawer.view'
  ) then return false; end if;
  select lifecycle_status into v_person_status from public.mme_person_identities where person_id=p_actor_person_id;
  if not found or v_person_status is distinct from 'active' then return false; end if;
  select ceo_person_id,employee_access_frozen into v_ceo_person_id,v_frozen
    from public.employee_security_settings where singleton=true;
  if not found or v_frozen is distinct from false or v_ceo_person_id is null then return false; end if;
  select employment_status into v_employment_status from public.employee_relationships where person_id=p_actor_person_id;
  if v_employment_status is distinct from 'active' then return false; end if;
  if p_actor_person_id=v_ceo_person_id then return true; end if;
  return exists(select 1 from public.employee_permission_grants g
    where g.person_id=p_actor_person_id and g.permission_key=p_permission_key
      and g.revoked_at is null and (g.expires_at is null or g.expires_at>now())
      and (g.scope='{}'::jsonb or g.scope->>'location_id'=p_location_id::text));
end;
$$;
revoke all on function public.mme_pos_authorize_drawer_action(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_drawer_action(uuid,text,uuid) to service_role;

create or replace function public.mme_pos_open_cash_drawer(
  p_register_reference text,p_location_id uuid,p_assigned_person_id uuid,
  p_actor_person_id uuid,p_currency text,p_opening_float_minor bigint,p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
  if p_register_reference is null or length(btrim(p_register_reference)) not between 1 and 80
    or p_location_id is null or p_assigned_person_id is null or p_actor_person_id is null
    or p_currency is null or p_currency !~ '^[A-Z]{3}$'
    or p_opening_float_minor is null or p_opening_float_minor<0
    or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 then
    raise exception 'Invalid cash drawer opening request' using errcode='22023';
  end if;
  if p_actor_person_id<>p_assigned_person_id then
    raise exception 'Assigned associate must open their own drawer' using errcode='42501';
  end if;
  if not public.mme_pos_authorize_drawer_action(p_actor_person_id,'pos.drawer.open',p_location_id) then
    raise exception 'Cash drawer open permission denied' using errcode='42501';
  end if;
  insert into public.mme_pos_cash_drawer_sessions(
    register_reference,location_id,assigned_person_id,opened_by_person_id,currency,opening_float_minor,expected_cash_minor
  ) values(p_register_reference,p_location_id,p_assigned_person_id,p_actor_person_id,p_currency,p_opening_float_minor,p_opening_float_minor)
  returning id into v_id;
  if p_opening_float_minor>0 then
    insert into public.mme_pos_cash_drawer_movements(
      drawer_session_id,movement_type,amount_minor,currency,reason_code,actor_person_id,idempotency_key
    ) values(v_id,'opening_float',p_opening_float_minor,p_currency,'opening_float',p_actor_person_id,p_idempotency_key);
  end if;
  return v_id;
end;
$$;

create or replace function public.mme_pos_record_drawer_cash_movement(
  p_drawer_session_id uuid,p_actor_person_id uuid,p_movement_type text,
  p_amount_minor bigint,p_reason_code text,p_reason_detail text,p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_session public.mme_pos_cash_drawer_sessions%rowtype; v_id uuid; v_permission text;
begin
  if p_drawer_session_id is null or p_actor_person_id is null
    or p_movement_type not in ('cash_in','cash_out')
    or p_amount_minor is null or p_amount_minor<=0
    or p_reason_code is null or length(btrim(p_reason_code))=0
    or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 then
    raise exception 'Invalid drawer cash movement' using errcode='22023';
  end if;
  select * into v_session from public.mme_pos_cash_drawer_sessions where id=p_drawer_session_id for update;
  if not found or v_session.status<>'open' then raise exception 'Open drawer session not found' using errcode='P0002'; end if;
  if v_session.assigned_person_id<>p_actor_person_id then raise exception 'Only assigned associate can move till cash' using errcode='42501'; end if;
  v_permission:=case when p_movement_type='cash_in' then 'pos.drawer.cash_in' else 'pos.drawer.cash_out' end;
  if not public.mme_pos_authorize_drawer_action(p_actor_person_id,v_permission,v_session.location_id) then
    raise exception 'Drawer movement permission denied' using errcode='42501';
  end if;
  if p_movement_type='cash_out' and p_amount_minor>v_session.expected_cash_minor then
    raise exception 'Cash out exceeds expected drawer balance' using errcode='23514';
  end if;
  insert into public.mme_pos_cash_drawer_movements(
    drawer_session_id,movement_type,amount_minor,currency,reason_code,reason_detail,actor_person_id,idempotency_key
  ) values(p_drawer_session_id,p_movement_type,p_amount_minor,v_session.currency,p_reason_code,left(p_reason_detail,500),p_actor_person_id,p_idempotency_key)
  returning id into v_id;
  update public.mme_pos_cash_drawer_sessions
    set expected_cash_minor=expected_cash_minor+case when p_movement_type='cash_in' then p_amount_minor else -p_amount_minor end,
        updated_at=now()
    where id=p_drawer_session_id;
  return v_id;
end;
$$;

create or replace function public.mme_pos_request_cash_adjustment(
  p_drawer_session_id uuid,p_actor_person_id uuid,p_direction text,p_amount_minor bigint,
  p_reason_code text,p_reason_detail text,p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_session public.mme_pos_cash_drawer_sessions%rowtype; v_id uuid;
begin
  if p_drawer_session_id is null or p_actor_person_id is null
    or p_direction not in ('in','out') or p_amount_minor is null or p_amount_minor<=0
    or p_reason_code is null or length(btrim(p_reason_code))=0
    or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 then
    raise exception 'Invalid cash adjustment request' using errcode='22023';
  end if;
  select * into v_session from public.mme_pos_cash_drawer_sessions where id=p_drawer_session_id for update;
  if not found or v_session.status<>'open' then raise exception 'Open drawer session not found' using errcode='P0002'; end if;
  if not public.mme_pos_authorize_drawer_action(p_actor_person_id,'pos.drawer.adjust.request',v_session.location_id) then
    raise exception 'Cash adjustment request permission denied' using errcode='42501';
  end if;
  insert into public.mme_pos_cash_adjustment_requests(
    drawer_session_id,direction,amount_minor,currency,reason_code,reason_detail,requested_by_person_id,idempotency_key
  ) values(p_drawer_session_id,p_direction,p_amount_minor,v_session.currency,p_reason_code,left(p_reason_detail,500),p_actor_person_id,p_idempotency_key)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.mme_pos_decide_cash_adjustment(
  p_adjustment_request_id uuid,p_approver_person_id uuid,p_decision text,p_decision_reason text default null
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_request public.mme_pos_cash_adjustment_requests%rowtype; v_session public.mme_pos_cash_drawer_sessions%rowtype;
begin
  if p_adjustment_request_id is null or p_approver_person_id is null or p_decision not in ('approve','reject') then
    raise exception 'Invalid cash adjustment decision' using errcode='22023';
  end if;
  select * into v_request from public.mme_pos_cash_adjustment_requests where id=p_adjustment_request_id for update;
  if not found or v_request.status<>'requested' then raise exception 'Adjustment request is not awaiting decision' using errcode='P0002'; end if;
  if v_request.requested_by_person_id=p_approver_person_id then raise exception 'Requester cannot approve own cash adjustment' using errcode='42501'; end if;
  select * into v_session from public.mme_pos_cash_drawer_sessions where id=v_request.drawer_session_id for update;
  if v_session.status<>'open' then raise exception 'Drawer must remain open for adjustment approval' using errcode='23514'; end if;
  if not public.mme_pos_authorize_drawer_action(p_approver_person_id,'pos.drawer.adjust.approve',v_session.location_id) then
    raise exception 'Cash adjustment approval permission denied' using errcode='42501';
  end if;
  if p_decision='approve' and v_request.direction='out' and v_request.amount_minor>v_session.expected_cash_minor then
    raise exception 'Approved cash adjustment exceeds expected drawer balance' using errcode='23514';
  end if;
  update public.mme_pos_cash_adjustment_requests set
    status=case when p_decision='approve' then 'approved' else 'rejected' end,
    decision=case when p_decision='approve' then 'approved' else 'rejected' end,
    decided_by_person_id=p_approver_person_id,decision_reason=left(p_decision_reason,500),decided_at=now()
    where id=v_request.id;
  if p_decision='approve' then
    insert into public.mme_pos_cash_drawer_movements(
      drawer_session_id,movement_type,amount_minor,currency,reason_code,reason_detail,actor_person_id,idempotency_key
    ) values(v_session.id,case when v_request.direction='in' then 'adjustment_in' else 'adjustment_out' end,
      v_request.amount_minor,v_request.currency,v_request.reason_code,v_request.reason_detail,p_approver_person_id,
      'adjustment:'||v_request.id::text);
    update public.mme_pos_cash_drawer_sessions set
      expected_cash_minor=expected_cash_minor+case when v_request.direction='in' then v_request.amount_minor else -v_request.amount_minor end,
      updated_at=now() where id=v_session.id;
  end if;
  return case when p_decision='approve' then 'approved' else 'rejected' end;
end;
$$;

create or replace function public.mme_pos_close_cash_drawer(
  p_drawer_session_id uuid,p_actor_person_id uuid,p_counted_cash_minor bigint,p_closeout_note text default null
) returns table(expected_cash_minor bigint,counted_cash_minor bigint,variance_minor bigint,close_status text)
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_session public.mme_pos_cash_drawer_sessions%rowtype; v_variance bigint; v_pending integer;
begin
  if p_drawer_session_id is null or p_actor_person_id is null or p_counted_cash_minor is null or p_counted_cash_minor<0 then
    raise exception 'Invalid drawer closeout' using errcode='22023';
  end if;
  select * into v_session from public.mme_pos_cash_drawer_sessions where id=p_drawer_session_id for update;
  if not found or v_session.status<>'open' then raise exception 'Open drawer session not found' using errcode='P0002'; end if;
  if v_session.assigned_person_id<>p_actor_person_id then raise exception 'Only assigned associate or authorized manager may close this till' using errcode='42501'; end if;
  if not public.mme_pos_authorize_drawer_action(p_actor_person_id,'pos.drawer.close',v_session.location_id) then
    raise exception 'Cash drawer close permission denied' using errcode='42501';
  end if;
  select count(*) into v_pending from public.mme_pos_cash_adjustment_requests
   where drawer_session_id=v_session.id and status='requested';
  if v_pending>0 then raise exception 'Pending cash adjustment decisions must be resolved before closeout' using errcode='23514'; end if;
  v_variance:=p_counted_cash_minor-v_session.expected_cash_minor;
  update public.mme_pos_cash_drawer_sessions set
    counted_cash_minor=p_counted_cash_minor,variance_minor=v_variance,
    status=case when v_variance=0 then 'closed' else 'review_required' end,
    closed_at=now(),closed_by_person_id=p_actor_person_id,closeout_note=left(p_closeout_note,500),updated_at=now()
    where id=v_session.id;
  return query select v_session.expected_cash_minor,p_counted_cash_minor,v_variance,
    case when v_variance=0 then 'closed' else 'review_required' end;
end;
$$;

revoke all on function public.mme_pos_open_cash_drawer(text,uuid,uuid,uuid,text,bigint,text) from public,anon,authenticated;
revoke all on function public.mme_pos_record_drawer_cash_movement(uuid,uuid,text,bigint,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_request_cash_adjustment(uuid,uuid,text,bigint,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_decide_cash_adjustment(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_close_cash_drawer(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.mme_pos_open_cash_drawer(text,uuid,uuid,uuid,text,bigint,text) to service_role;
grant execute on function public.mme_pos_record_drawer_cash_movement(uuid,uuid,text,bigint,text,text,text) to service_role;
grant execute on function public.mme_pos_request_cash_adjustment(uuid,uuid,text,bigint,text,text,text) to service_role;
grant execute on function public.mme_pos_decide_cash_adjustment(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_pos_close_cash_drawer(uuid,uuid,bigint,text) to service_role;

comment on table public.mme_pos_cash_drawer_sessions is
  'Associate-assigned POS cash drawer shifts, counted closeout and variance tracking.';
comment on table public.mme_pos_cash_drawer_movements is
  'Cash drawer movement ledger; records are immutable by API contract and tied to session/idempotency.';
comment on table public.mme_pos_cash_adjustment_requests is
  'Dual-control cash adjustment requests; requester cannot approve their own adjustment.';

commit;
