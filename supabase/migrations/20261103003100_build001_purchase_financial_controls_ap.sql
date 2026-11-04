-- Build 001: purchase budget gates, invoice approval holds, and AP reconciliation ledger.
-- Payment execution remains external; this migration records authorization and verified outcomes only.

create table public.mme_purchase_budget_policies (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 monthly_budget_cents bigint not null check(monthly_budget_cents>0),
 max_purchase_order_cents bigint not null check(max_purchase_order_cents>0),
 approval_threshold_cents bigint not null default 0 check(approval_threshold_cents>=0),
 currency text not null default 'USD' check(currency='USD'),
 effective_from date not null default current_date,
 effective_until date,
 active boolean not null default true,
 created_by_identity_id uuid not null,
 updated_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(effective_until is null or effective_until>=effective_from),
 unique(location_id,effective_from)
);
create index mme_purchase_budget_active_idx on public.mme_purchase_budget_policies(location_id,effective_from desc)
 where active=true;
alter table public.mme_purchase_budget_policies enable row level security;
revoke all on public.mme_purchase_budget_policies from public,anon,authenticated;
grant all on public.mme_purchase_budget_policies to service_role;

create table public.mme_supplier_invoice_approvals (
 id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.mme_supplier_invoices(id) on delete restrict,
 decision text not null check(decision in ('approved','rejected','held')),
 reason text,
 invoice_total_cents bigint not null check(invoice_total_cents>=0),
 matched_status_snapshot text not null check(matched_status_snapshot in ('matched','variance','disputed','pending')),
 requested_by_identity_id uuid not null,
 decided_by_identity_id uuid not null,
 decided_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 check(requested_by_identity_id<>decided_by_identity_id)
);
create unique index mme_invoice_single_approval_idx on public.mme_supplier_invoice_approvals(invoice_id)
 where decision='approved';
alter table public.mme_supplier_invoice_approvals enable row level security;
revoke all on public.mme_supplier_invoice_approvals from public,anon,authenticated;
grant all on public.mme_supplier_invoice_approvals to service_role;

create table public.mme_supplier_payment_schedules (
 id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null unique references public.mme_supplier_invoices(id) on delete restrict,
 scheduled_amount_cents bigint not null check(scheduled_amount_cents>0),
 currency text not null default 'USD' check(currency='USD'),
 due_date date not null,
 payment_status text not null default 'draft'
  check(payment_status in ('draft','approved','scheduled','processing','paid','failed','on_hold','void')),
 payment_method text check(payment_method in ('ach','wire','check','card','other')),
 external_payment_reference text,
 approved_by_identity_id uuid,
 approved_at timestamptz,
 created_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((payment_status not in ('approved','scheduled','processing','paid') or (approved_by_identity_id is not null and approved_at is not null)))
);
create index mme_ap_schedule_due_idx on public.mme_supplier_payment_schedules(payment_status,due_date);
alter table public.mme_supplier_payment_schedules enable row level security;
revoke all on public.mme_supplier_payment_schedules from public,anon,authenticated;
grant all on public.mme_supplier_payment_schedules to service_role;

create table public.mme_supplier_payment_events (
 id uuid primary key default gen_random_uuid(),
 schedule_id uuid not null references public.mme_supplier_payment_schedules(id) on delete restrict,
 provider text not null check(provider in ('manual','stripe','bank')),
 provider_event_id text not null,
 event_type text not null check(event_type in ('payment_submitted','payment_processing','payment_settled','payment_failed','payment_reversed','payment_reconciled')),
 amount_cents bigint not null check(amount_cents>=0),
 currency text not null default 'USD' check(currency='USD'),
 external_reference text,
 payload_sha256 text,
 actor_identity_id uuid not null,
 occurred_at timestamptz not null default now(),
 unique(provider,provider_event_id)
);
create index mme_supplier_payment_events_schedule_idx on public.mme_supplier_payment_events(schedule_id,occurred_at desc);
alter table public.mme_supplier_payment_events enable row level security;
revoke all on public.mme_supplier_payment_events from public,anon,authenticated;
grant all on public.mme_supplier_payment_events to service_role;

-- Approval gate: each active location must have an effective budget policy.
create or replace function public.mme_guard_purchase_order_approval()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_policy public.mme_purchase_budget_policies%rowtype;
 v_location uuid; v_month_committed numeric; v_approval_required boolean:=false;
begin
 if new.status='approved' and old.status is distinct from 'approved' then
  select distinct location_id into v_location from public.mme_purchase_order_lines
   where purchase_order_id=new.id;
  if v_location is null or exists(select 1 from public.mme_purchase_order_lines
    where purchase_order_id=new.id and location_id<>v_location) then
   raise exception 'Purchase order must target one location for budget approval' using errcode='23514';
  end if;
  select * into v_policy from public.mme_purchase_budget_policies
   where location_id=v_location and active=true and effective_from<=current_date
    and (effective_until is null or effective_until>=current_date)
   order by effective_from desc limit 1 for update;
  if not found then raise exception 'Active purchase budget policy required before approval' using errcode='23514'; end if;
  if new.total_cents>v_policy.max_purchase_order_cents then
   raise exception 'Purchase order exceeds location maximum' using errcode='23514';
  end if;
  select coalesce(sum(po.total_cents),0) into v_month_committed
   from public.mme_purchase_orders po
   join public.mme_purchase_order_lines pol on pol.purchase_order_id=po.id
   where pol.location_id=v_location and po.id<>new.id
    and po.status in ('approved','issued','acknowledged','partially_received','received')
    and po.created_at>=date_trunc('month',now());
  if v_month_committed+new.total_cents>v_policy.monthly_budget_cents then
   raise exception 'Purchase order exceeds remaining monthly budget' using errcode='23514';
  end if;
  v_approval_required:=new.total_cents>=v_policy.approval_threshold_cents;
  if v_approval_required and new.approved_by_identity_id is null then
   raise exception 'Approval identity required at configured spending threshold' using errcode='23514';
  end if;
 end if;
 return new;
end; $$;
create trigger mme_purchase_order_budget_guard
 before update of status on public.mme_purchase_orders
 for each row execute function public.mme_guard_purchase_order_approval();

create or replace function public.mme_approve_supplier_invoice(
 p_invoice_id uuid,p_requested_by_identity_id uuid,p_decided_by_identity_id uuid,
 p_decision text,p_reason text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_invoice public.mme_supplier_invoices%rowtype; v_approval uuid;
begin
 if p_invoice_id is null or p_requested_by_identity_id is null or p_decided_by_identity_id is null
  or p_decision not in ('approved','rejected','held') then
  raise exception 'Invalid invoice approval request' using errcode='22023';
 end if;
 if p_requested_by_identity_id=p_decided_by_identity_id then
  raise exception 'Invoice requester cannot approve their own invoice' using errcode='23514';
 end if;
 select * into v_invoice from public.mme_supplier_invoices where id=p_invoice_id for update;
 if not found then raise exception 'Supplier invoice not found' using errcode='P0002'; end if;
 if v_invoice.match_status<>'matched' and p_decision='approved' then
  raise exception 'Invoice must pass PO match before approval' using errcode='23514';
 end if;
 if exists(select 1 from public.mme_supplier_invoice_approvals where invoice_id=p_invoice_id and decision='approved') then
  raise exception 'Invoice already approved' using errcode='23505';
 end if;
 insert into public.mme_supplier_invoice_approvals(invoice_id,decision,reason,invoice_total_cents,
  matched_status_snapshot,requested_by_identity_id,decided_by_identity_id)
 values(p_invoice_id,p_decision,left(p_reason,1000),v_invoice.total_cents,
  v_invoice.match_status,p_requested_by_identity_id,p_decided_by_identity_id)
 returning id into v_approval;
 return v_approval;
end; $$;

create or replace function public.mme_create_supplier_payment_schedule(
 p_invoice_id uuid,p_due_date date,p_method text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_invoice public.mme_supplier_invoices%rowtype; v_schedule uuid;
begin
 if p_invoice_id is null or p_due_date is null or p_actor_identity_id is null
  or p_method not in ('ach','wire','check','card','other') then
  raise exception 'Invalid supplier payment schedule' using errcode='22023';
 end if;
 select * into v_invoice from public.mme_supplier_invoices where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found' using errcode='P0002'; end if;
 if v_invoice.match_status<>'matched' or not exists(
  select 1 from public.mme_supplier_invoice_approvals a
  where a.invoice_id=p_invoice_id and a.decision='approved'
 ) then raise exception 'Only approved, matched invoices can be scheduled' using errcode='23514'; end if;
 insert into public.mme_supplier_payment_schedules(invoice_id,scheduled_amount_cents,due_date,
  payment_method,created_by_identity_id)
 values(p_invoice_id,v_invoice.total_cents,p_due_date,p_method,p_actor_identity_id)
 returning id into v_schedule;
 return v_schedule;
end; $$;

create or replace function public.mme_record_supplier_payment_event(
 p_schedule_id uuid,p_provider text,p_provider_event_id text,p_event_type text,
 p_amount_cents bigint,p_external_reference text,p_actor_identity_id uuid,p_payload_sha256 text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_schedule public.mme_supplier_payment_schedules%rowtype; v_event uuid;
 v_next_status text;
begin
 if p_schedule_id is null or p_provider not in ('manual','stripe','bank')
  or p_provider_event_id is null or length(btrim(p_provider_event_id)) not between 1 and 180
  or p_event_type not in ('payment_submitted','payment_processing','payment_settled','payment_failed','payment_reversed','payment_reconciled')
  or p_amount_cents is null or p_amount_cents<0 or p_actor_identity_id is null then
  raise exception 'Invalid supplier payment event' using errcode='22023';
 end if;
 select * into v_schedule from public.mme_supplier_payment_schedules where id=p_schedule_id for update;
 if not found then raise exception 'Payment schedule not found' using errcode='P0002'; end if;
 if p_event_type in ('payment_settled','payment_reconciled') and p_amount_cents<>v_schedule.scheduled_amount_cents then
  raise exception 'Settled payment amount must equal approved scheduled amount' using errcode='23514';
 end if;
 if p_event_type in ('payment_submitted','payment_processing','payment_settled','payment_reconciled')
  and v_schedule.payment_status not in ('approved','scheduled','processing') then
  raise exception 'Payment schedule is not eligible for this event' using errcode='23514';
 end if;
 insert into public.mme_supplier_payment_events(schedule_id,provider,provider_event_id,event_type,
  amount_cents,external_reference,payload_sha256,actor_identity_id)
 values(p_schedule_id,p_provider,btrim(p_provider_event_id),p_event_type,p_amount_cents,
  left(p_external_reference,180),p_payload_sha256,p_actor_identity_id)
 on conflict(provider,provider_event_id) do nothing returning id into v_event;
 if v_event is null then
  select id into v_event from public.mme_supplier_payment_events
   where provider=p_provider and provider_event_id=btrim(p_provider_event_id);
  return v_event;
 end if;
 v_next_status:=case p_event_type when 'payment_submitted' then 'processing'
  when 'payment_processing' then 'processing' when 'payment_settled' then 'paid'
  when 'payment_reconciled' then 'paid' when 'payment_failed' then 'failed'
  when 'payment_reversed' then 'on_hold' end;
 update public.mme_supplier_payment_schedules set payment_status=v_next_status,
  external_payment_reference=coalesce(left(p_external_reference,180),external_payment_reference),
  updated_at=now() where id=p_schedule_id;
 return v_event;
end; $$;

revoke all on function public.mme_guard_purchase_order_approval() from public,anon,authenticated;
revoke all on function public.mme_approve_supplier_invoice(uuid,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_create_supplier_payment_schedule(uuid,date,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_record_supplier_payment_event(uuid,text,text,text,bigint,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_approve_supplier_invoice(uuid,uuid,uuid,text,text) to service_role;
grant execute on function public.mme_create_supplier_payment_schedule(uuid,date,text,uuid) to service_role;
grant execute on function public.mme_record_supplier_payment_event(uuid,text,text,text,bigint,text,uuid,text) to service_role;

comment on table public.mme_purchase_budget_policies is 'Location-level purchase limits and monthly budget controls.';
comment on table public.mme_supplier_payment_schedules is 'Approved supplier invoice payables; records schedules but does not initiate bank transfers.';
comment on table public.mme_supplier_payment_events is 'Idempotent supplier payment and bank reconciliation event ledger.';
