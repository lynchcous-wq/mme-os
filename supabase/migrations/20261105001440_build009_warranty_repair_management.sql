-- Build 009.64 — warranty and repair operations layered onto serialized warranty records.
begin;
create table public.mme_warranty_repair_cases (
 repair_case_id uuid primary key default gen_random_uuid(),
 warranty_id uuid references public.mme_serialized_warranties(id) on delete restrict,
 serialized_unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 order_id uuid references public.mme_orders(id) on delete restrict,
 order_line_id uuid references public.mme_order_lines(id) on delete restrict,
 customer_identity_id uuid not null,
 case_number text not null unique,
 intake_channel text not null check(intake_channel in ('customer_portal','pos','phone','email','store')),
 issue_summary text not null check(length(btrim(issue_summary)) between 5 and 2000),
 issue_details text,
 status text not null default 'submitted' check(status in ('submitted','eligibility_review','awaiting_customer','approved','diagnosing','awaiting_parts','repair_in_progress','quality_check','ready_for_pickup','shipped','completed','denied','cancelled')),
 warranty_result text not null default 'pending' check(warranty_result in ('pending','covered','partially_covered','not_covered','expired','manual_review')),
 assigned_technician_identity_id uuid,
 assigned_location_id uuid references public.mme_store_locations(id) on delete restrict,
 received_at timestamptz,
 promised_at timestamptz,
 completed_at timestamptz,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_warranty_repair_customer_idx on public.mme_warranty_repair_cases(customer_identity_id,created_at desc);
create index mme_warranty_repair_queue_idx on public.mme_warranty_repair_cases(status,assigned_location_id,created_at);
create index mme_warranty_repair_serial_idx on public.mme_warranty_repair_cases(serialized_unit_id,created_at desc);

create table public.mme_warranty_repair_diagnostics (
 diagnostic_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 technician_identity_id uuid not null,
 diagnostic_code text,
 findings text not null,
 tests jsonb not null default '{}'::jsonb check(jsonb_typeof(tests)='object'),
 recommended_action text not null,
 estimated_parts_cost numeric(14,2) not null default 0 check(estimated_parts_cost>=0),
 estimated_labor_cost numeric(14,2) not null default 0 check(estimated_labor_cost>=0),
 created_at timestamptz not null default now()
);
create index mme_warranty_diagnostics_case_idx on public.mme_warranty_repair_diagnostics(repair_case_id,created_at desc);

create table public.mme_warranty_repair_parts (
 repair_part_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 sku_reference text not null,
 description text not null,
 quantity numeric(12,3) not null check(quantity>0),
 unit_cost numeric(14,4) not null check(unit_cost>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 reservation_reference text,
 status text not null default 'requested' check(status in ('requested','reserved','issued','returned','cancelled')),
 issued_by uuid,
 issued_at timestamptz,
 created_at timestamptz not null default now()
);
create index mme_warranty_parts_case_idx on public.mme_warranty_repair_parts(repair_case_id,status);

create table public.mme_warranty_repair_labor (
 labor_entry_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 technician_identity_id uuid not null,
 work_code text not null,
 description text not null,
 minutes integer not null check(minutes between 1 and 1440),
 labor_rate numeric(14,4) not null check(labor_rate>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 approved_by uuid,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>technician_identity_id)
);
create index mme_warranty_labor_case_idx on public.mme_warranty_repair_labor(repair_case_id,created_at);

create table public.mme_warranty_repair_loaners (
 loaner_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 serialized_unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 checked_out_by uuid not null,
 checked_out_at timestamptz not null default now(),
 due_at timestamptz not null,
 returned_at timestamptz,
 returned_condition text check(returned_condition in ('A','B','C','D','non_resellable')),
 status text not null default 'checked_out' check(status in ('checked_out','returned','overdue','lost','damaged')),
 unique(repair_case_id,serialized_unit_id),
 check(due_at>checked_out_at)
);
create index mme_warranty_loaner_due_idx on public.mme_warranty_repair_loaners(status,due_at);

create table public.mme_warranty_provider_claims (
 provider_claim_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 provider_name text not null,
 provider_claim_reference text,
 claim_amount numeric(14,2) not null check(claim_amount>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 status text not null default 'draft' check(status in ('draft','submitted','acknowledged','approved','partially_approved','denied','paid','reconciled','disputed')),
 submitted_at timestamptz,
 settled_amount numeric(14,2) check(settled_amount is null or settled_amount>=0),
 settled_at timestamptz,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_warranty_provider_claim_case_idx on public.mme_warranty_provider_claims(repair_case_id,status);

create table public.mme_warranty_repair_events (
 event_id bigint generated always as identity primary key,
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 actor_identity_id uuid not null,
 event_type text not null,
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 created_at timestamptz not null default now()
);
create index mme_warranty_repair_events_case_idx on public.mme_warranty_repair_events(repair_case_id,event_id);

alter table public.mme_warranty_repair_cases enable row level security;
alter table public.mme_warranty_repair_diagnostics enable row level security;
alter table public.mme_warranty_repair_parts enable row level security;
alter table public.mme_warranty_repair_labor enable row level security;
alter table public.mme_warranty_repair_loaners enable row level security;
alter table public.mme_warranty_provider_claims enable row level security;
alter table public.mme_warranty_repair_events enable row level security;
revoke all on public.mme_warranty_repair_cases,public.mme_warranty_repair_diagnostics,public.mme_warranty_repair_parts,public.mme_warranty_repair_labor,public.mme_warranty_repair_loaners,public.mme_warranty_provider_claims,public.mme_warranty_repair_events from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_repair_cases,public.mme_warranty_repair_diagnostics,public.mme_warranty_repair_parts,public.mme_warranty_repair_labor,public.mme_warranty_repair_loaners,public.mme_warranty_provider_claims to service_role;
grant select,insert on public.mme_warranty_repair_events to service_role;
revoke update,delete,truncate on public.mme_warranty_repair_events from public,anon,authenticated,service_role;

create or replace function public.mme_warranty_repair_open_case(
 p_warranty_id uuid,p_serialized_unit_id uuid,p_customer_identity_id uuid,p_order_id uuid,p_order_line_id uuid,
 p_case_number text,p_channel text,p_summary text,p_actor uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare w public.mme_serialized_warranties%rowtype; v uuid;
begin
 if p_actor is null or p_customer_identity_id is null or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Customer, actor and idempotency key required' using errcode='22023'; end if;
 select repair_case_id into v from public.mme_warranty_repair_cases where idempotency_key=p_idempotency_key;
 if found then return v; end if;
 select * into w from public.mme_serialized_warranties where id=p_warranty_id and serialized_unit_id=p_serialized_unit_id and customer_identity_id=p_customer_identity_id;
 if not found then raise exception 'Warranty/device/customer association not found' using errcode='P0002'; end if;
 if p_order_id is not null and w.order_id<>p_order_id then raise exception 'Order does not match warranty' using errcode='23514'; end if;
 if p_order_line_id is not null and w.order_line_id<>p_order_line_id then raise exception 'Order line does not match warranty' using errcode='23514'; end if;
 insert into public.mme_warranty_repair_cases(warranty_id,serialized_unit_id,order_id,order_line_id,customer_identity_id,case_number,intake_channel,issue_summary,idempotency_key)
 values(p_warranty_id,p_serialized_unit_id,p_order_id,p_order_line_id,p_customer_identity_id,p_case_number,p_channel,left(p_summary,2000),p_idempotency_key)
 returning repair_case_id into v;
 insert into public.mme_warranty_repair_events(repair_case_id,actor_identity_id,event_type,event_data)
 values(v,p_actor,'case_opened',jsonb_build_object('channel',p_channel));
 return v;
end; $$;

create or replace function public.mme_warranty_repair_set_coverage(p_case uuid,p_result text,p_actor uuid,p_reason text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_warranty_repair_cases%rowtype;
begin
 if p_result not in ('covered','partially_covered','not_covered','expired','manual_review') or p_actor is null then raise exception 'Invalid warranty decision' using errcode='22023'; end if;
 select * into r from public.mme_warranty_repair_cases where repair_case_id=p_case for update;
 if not found or r.status not in ('submitted','eligibility_review') then raise exception 'Case not eligible for coverage decision' using errcode='55000'; end if;
 update public.mme_warranty_repair_cases set warranty_result=p_result,status=case when p_result='manual_review' then 'eligibility_review' when p_result in ('not_covered','expired') then 'denied' else 'approved' end,updated_at=now() where repair_case_id=p_case;
 insert into public.mme_warranty_repair_events(repair_case_id,actor_identity_id,event_type,event_data)
 values(p_case,p_actor,'coverage_decided',jsonb_build_object('result',p_result,'reason',left(p_reason,1000)));
end; $$;

create or replace function public.mme_warranty_repair_transition(p_case uuid,p_next_status text,p_actor uuid,p_reason text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_warranty_repair_cases%rowtype;
begin
 select * into r from public.mme_warranty_repair_cases where repair_case_id=p_case for update;
 if not found or p_actor is null then raise exception 'Case and actor required' using errcode='P0002'; end if;
 if not ((r.status='approved' and p_next_status in ('diagnosing','awaiting_customer','awaiting_parts')) or
 (r.status='diagnosing' and p_next_status in ('awaiting_parts','repair_in_progress','awaiting_customer')) or
 (r.status='awaiting_parts' and p_next_status in ('repair_in_progress','cancelled')) or
 (r.status='repair_in_progress' and p_next_status in ('quality_check','awaiting_parts')) or
 (r.status='quality_check' and p_next_status in ('repair_in_progress','ready_for_pickup','shipped')) or
 (r.status='ready_for_pickup' and p_next_status in ('completed','shipped')) or
 (r.status='shipped' and p_next_status='completed') or
 (r.status='awaiting_customer' and p_next_status in ('approved','cancelled'))) then raise exception 'Invalid repair lifecycle transition' using errcode='23514'; end if;
 update public.mme_warranty_repair_cases set status=p_next_status,completed_at=case when p_next_status='completed' then now() else completed_at end,updated_at=now() where repair_case_id=p_case;
 insert into public.mme_warranty_repair_events(repair_case_id,actor_identity_id,event_type,event_data)
 values(p_case,p_actor,'status_changed',jsonb_build_object('from',r.status,'to',p_next_status,'reason',left(p_reason,1000)));
end; $$;

revoke all on function public.mme_warranty_repair_open_case(uuid,uuid,uuid,uuid,uuid,text,text,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_repair_set_coverage(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_repair_transition(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_repair_open_case(uuid,uuid,uuid,uuid,uuid,text,text,text,uuid,text) to service_role;
grant execute on function public.mme_warranty_repair_set_coverage(uuid,text,uuid,text) to service_role;
grant execute on function public.mme_warranty_repair_transition(uuid,text,uuid,text) to service_role;
commit;
