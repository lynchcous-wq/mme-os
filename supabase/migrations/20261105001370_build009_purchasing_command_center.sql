-- Build 009.57 — purchasing command center, vendor intelligence and budget-gated procurement.
begin;
create table public.mme_procurement_vendors (
 vendor_id uuid primary key default gen_random_uuid(), vendor_code text not null unique,
 legal_name text not null, display_name text not null,
 status text not null default 'pending' check(status in ('pending','approved','suspended','inactive')),
 payment_terms text, default_currency text not null check(default_currency ~ '^[A-Z]{3}$'),
 default_lead_time_days integer check(default_lead_time_days is null or default_lead_time_days between 0 and 730),
 minimum_order_value numeric(14,2) check(minimum_order_value is null or minimum_order_value>=0),
 reliability_score numeric(5,2) check(reliability_score is null or reliability_score between 0 and 100),
 created_by uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.mme_procurement_vendor_quotes (
 quote_id uuid primary key default gen_random_uuid(), vendor_id uuid not null references public.mme_procurement_vendors(vendor_id) on delete restrict,
 sku_reference text not null, manufacturer_model text, quoted_unit_price numeric(14,2) not null check(quoted_unit_price>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'), minimum_order_quantity integer not null default 1 check(minimum_order_quantity>=1),
 quoted_lead_time_days integer not null check(quoted_lead_time_days between 0 and 730), shipping_cost numeric(14,2) not null default 0 check(shipping_cost>=0),
 quote_valid_until timestamptz not null, quote_reference text, evidence_reference text, recorded_by uuid not null, created_at timestamptz not null default now()
);
create index mme_procurement_vendor_quotes_sku_idx on public.mme_procurement_vendor_quotes(sku_reference,currency_code,quote_valid_until);
create table public.mme_procurement_budgets (
 budget_id uuid primary key default gen_random_uuid(), budget_name text not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'), budget_amount numeric(14,2) not null check(budget_amount>=0),
 committed_amount numeric(14,2) not null default 0 check(committed_amount>=0),
 effective_from date not null, effective_to date not null, scope_location text,
 status text not null default 'active' check(status in ('draft','active','closed')),
 approved_by uuid, created_by uuid not null, created_at timestamptz not null default now(),
 check(effective_to>=effective_from), check(committed_amount<=budget_amount)
);
create index mme_procurement_budgets_active_idx on public.mme_procurement_budgets(status,effective_from,effective_to);
create table public.mme_procurement_purchase_requests (
 request_id uuid primary key default gen_random_uuid(), forecast_id uuid references public.mme_inventory_demand_forecasts(forecast_id) on delete restrict,
 sku_reference text not null, vendor_quote_id uuid references public.mme_procurement_vendor_quotes(quote_id) on delete restrict,
 vendor_id uuid not null references public.mme_procurement_vendors(vendor_id) on delete restrict,
 destination_location text not null, requested_quantity integer not null check(requested_quantity>=1),
 quoted_unit_price numeric(14,2) not null check(quoted_unit_price>=0), shipping_cost numeric(14,2) not null default 0 check(shipping_cost>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'), estimated_total numeric(14,2) not null check(estimated_total>=0),
 expected_lead_time_days integer not null check(expected_lead_time_days between 0 and 730),
 budget_id uuid references public.mme_procurement_budgets(budget_id) on delete restrict,
 request_status text not null default 'pending' check(request_status in ('pending','approved','rejected','cancelled','po_draft_created')),
 requested_by uuid not null, approved_by uuid, approved_at timestamptz, approval_note text, created_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>requested_by)
);
create index mme_procurement_purchase_requests_status_idx on public.mme_procurement_purchase_requests(request_status,created_at);
create table public.mme_procurement_location_allocations (
 allocation_id uuid primary key default gen_random_uuid(), request_id uuid not null references public.mme_procurement_purchase_requests(request_id) on delete restrict,
 destination_location text not null, allocated_quantity integer not null check(allocated_quantity>=1), created_at timestamptz not null default now(),
 unique(request_id,destination_location)
);
create table public.mme_procurement_purchase_order_drafts (
 po_draft_id uuid primary key default gen_random_uuid(), request_id uuid not null unique references public.mme_procurement_purchase_requests(request_id) on delete restrict,
 vendor_id uuid not null references public.mme_procurement_vendors(vendor_id) on delete restrict,
 po_reference text not null unique, currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 total_amount numeric(14,2) not null check(total_amount>=0), expected_delivery_date date,
 draft_status text not null default 'draft' check(draft_status in ('draft','exported_for_review','cancelled','submitted_confirmed')),
 external_po_reference text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.mme_procurement_vendor_performance (
 performance_id uuid primary key default gen_random_uuid(), vendor_id uuid not null references public.mme_procurement_vendors(vendor_id) on delete restrict,
 po_reference text not null, promised_delivery_date date, actual_delivery_date date,
 ordered_units integer not null check(ordered_units>=0), accepted_units integer not null check(accepted_units between 0 and ordered_units),
 recorded_by uuid not null, recorded_at timestamptz not null default now()
);
create index mme_procurement_vendor_performance_idx on public.mme_procurement_vendor_performance(vendor_id,recorded_at desc);
create table public.mme_procurement_audit (
 audit_id bigint generated always as identity primary key, actor_user_id uuid not null, entity_type text not null, entity_id uuid,
 action text not null, prior_state jsonb not null default '{}'::jsonb, new_state jsonb not null default '{}'::jsonb,
 reason text, created_at timestamptz not null default now()
);
alter table public.mme_procurement_vendors enable row level security;
alter table public.mme_procurement_vendor_quotes enable row level security;
alter table public.mme_procurement_budgets enable row level security;
alter table public.mme_procurement_purchase_requests enable row level security;
alter table public.mme_procurement_location_allocations enable row level security;
alter table public.mme_procurement_purchase_order_drafts enable row level security;
alter table public.mme_procurement_vendor_performance enable row level security;
alter table public.mme_procurement_audit enable row level security;
revoke all on public.mme_procurement_vendors,public.mme_procurement_vendor_quotes,public.mme_procurement_budgets,
 public.mme_procurement_purchase_requests,public.mme_procurement_location_allocations,
 public.mme_procurement_purchase_order_drafts,public.mme_procurement_vendor_performance,
 public.mme_procurement_audit from public,anon,authenticated;
grant select,insert,update on public.mme_procurement_vendors,public.mme_procurement_vendor_quotes,public.mme_procurement_budgets,
 public.mme_procurement_purchase_requests,public.mme_procurement_location_allocations,
 public.mme_procurement_purchase_order_drafts,public.mme_procurement_vendor_performance to service_role;
grant select,insert on public.mme_procurement_audit to service_role;
revoke update,delete,truncate on public.mme_procurement_audit from public,anon,authenticated,service_role;
create or replace function public.mme_procurement_create_purchase_request(p_forecast_id uuid,p_quote_id uuid,p_budget_id uuid,p_requester uuid,p_destination_location text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare f public.mme_inventory_demand_forecasts%rowtype; q public.mme_procurement_vendor_quotes%rowtype;
 v public.mme_procurement_vendors%rowtype; b public.mme_procurement_budgets%rowtype; v_id uuid; v_total numeric(14,2);
begin
 select * into f from public.mme_inventory_demand_forecasts where forecast_id=p_forecast_id;
 select * into q from public.mme_procurement_vendor_quotes where quote_id=p_quote_id;
 if f.forecast_id is null or q.quote_id is null then raise exception 'Forecast and vendor quote required' using errcode='22023'; end if;
 select * into v from public.mme_procurement_vendors where vendor_id=q.vendor_id and status='approved';
 if not found then raise exception 'Approved vendor required' using errcode='55000'; end if;
 if q.sku_reference<>f.sku_reference or q.quote_valid_until<=now() then raise exception 'Quote SKU mismatch or expired quote' using errcode='22023'; end if;
 if q.currency_code<>v.default_currency then raise exception 'Quote currency must match vendor currency profile' using errcode='22023'; end if;
 if f.suggested_reorder_quantity<1 then raise exception 'Forecast does not recommend replenishment' using errcode='55000'; end if;
 select * into b from public.mme_procurement_budgets where budget_id=p_budget_id and status='active'
 and current_date between effective_from and effective_to and currency_code=q.currency_code for update;
 if not found then raise exception 'Active budget in matching currency required' using errcode='55000'; end if;
 v_total:=f.suggested_reorder_quantity*q.quoted_unit_price+q.shipping_cost;
 if v_total+b.committed_amount>b.budget_amount then raise exception 'Purchase request exceeds available budget' using errcode='23514'; end if;
 insert into public.mme_procurement_purchase_requests(forecast_id,sku_reference,vendor_quote_id,vendor_id,destination_location,requested_quantity,quoted_unit_price,shipping_cost,currency_code,estimated_total,expected_lead_time_days,budget_id,requested_by)
 values(f.forecast_id,f.sku_reference,q.quote_id,q.vendor_id,p_destination_location,f.suggested_reorder_quantity,q.quoted_unit_price,q.shipping_cost,q.currency_code,v_total,q.quoted_lead_time_days,b.budget_id,p_requester) returning request_id into v_id;
 insert into public.mme_procurement_location_allocations(request_id,destination_location,allocated_quantity) values(v_id,p_destination_location,f.suggested_reorder_quantity);
 insert into public.mme_procurement_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_requester,'purchase_request',v_id,'purchase_request_created',jsonb_build_object('sku',f.sku_reference,'quantity',f.suggested_reorder_quantity,'total',v_total,'budget_id',b.budget_id));
 return v_id;
end; $$;
create or replace function public.mme_procurement_approve_purchase_request(p_request_id uuid,p_approver uuid,p_note text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_procurement_purchase_requests%rowtype; b public.mme_procurement_budgets%rowtype; po uuid; ref text;
begin
 select * into r from public.mme_procurement_purchase_requests where request_id=p_request_id for update;
 if not found or r.request_status<>'pending' or p_approver is null or p_approver=r.requested_by then raise exception 'Pending request requires independent approver' using errcode='55000'; end if;
 select * into b from public.mme_procurement_budgets where budget_id=r.budget_id and status='active' for update;
 if not found or b.currency_code<>r.currency_code or b.committed_amount+r.estimated_total>b.budget_amount then raise exception 'Budget unavailable or insufficient' using errcode='23514'; end if;
 update public.mme_procurement_budgets set committed_amount=committed_amount+r.estimated_total where budget_id=b.budget_id;
 update public.mme_procurement_purchase_requests set request_status='po_draft_created',approved_by=p_approver,approved_at=now(),approval_note=left(p_note,2000) where request_id=p_request_id;
 ref:='MME-PO-DRAFT-'||upper(substr(replace(p_request_id::text,'-',''),1,12));
 insert into public.mme_procurement_purchase_order_drafts(request_id,vendor_id,po_reference,currency_code,total_amount,expected_delivery_date)
 values(r.request_id,r.vendor_id,ref,r.currency_code,r.estimated_total,current_date+r.expected_lead_time_days) returning po_draft_id into po;
 insert into public.mme_procurement_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_approver,'purchase_request',p_request_id,'purchase_request_approved_po_draft_created',jsonb_build_object('po_draft_id',po,'po_reference',ref,'budget_commitment',r.estimated_total));
 return po;
end; $$;
create or replace function public.mme_procurement_record_vendor_performance(p_vendor_id uuid,p_po_reference text,p_promised date,p_actual date,p_ordered integer,p_accepted integer,p_actor uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid;
begin
 if p_ordered<0 or p_accepted<0 or p_accepted>p_ordered then raise exception 'Invalid ordered or accepted quantities' using errcode='22023'; end if;
 insert into public.mme_procurement_vendor_performance(vendor_id,po_reference,promised_delivery_date,actual_delivery_date,ordered_units,accepted_units,recorded_by)
 values(p_vendor_id,p_po_reference,p_promised,p_actual,p_ordered,p_accepted,p_actor) returning performance_id into v_id;
 insert into public.mme_procurement_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'vendor',p_vendor_id,'vendor_performance_recorded',jsonb_build_object('performance_id',v_id,'ordered',p_ordered,'accepted',p_accepted,'promised',p_promised,'actual',p_actual));
 return v_id;
end; $$;
create or replace view public.mme_procurement_vendor_scorecards as
select v.vendor_id,v.vendor_code,v.display_name,v.status,count(p.performance_id) as completed_orders,
 coalesce(round(avg(case when p.actual_delivery_date is not null and p.promised_delivery_date is not null then case when p.actual_delivery_date<=p.promised_delivery_date then 100.0 else 0.0 end end),2),0) as on_time_delivery_percent,
 coalesce(round(100.0*sum(p.accepted_units)::numeric/nullif(sum(p.ordered_units),0),2),0) as acceptance_rate_percent,
 v.default_lead_time_days
from public.mme_procurement_vendors v left join public.mme_procurement_vendor_performance p on p.vendor_id=v.vendor_id
group by v.vendor_id,v.vendor_code,v.display_name,v.status,v.default_lead_time_days;
revoke all on public.mme_procurement_vendor_scorecards from public,anon,authenticated;
grant select on public.mme_procurement_vendor_scorecards to service_role;
revoke all on function public.mme_procurement_create_purchase_request(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_procurement_approve_purchase_request(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_procurement_record_vendor_performance(uuid,text,date,date,integer,integer,uuid) from public,anon,authenticated;
grant execute on function public.mme_procurement_create_purchase_request(uuid,uuid,uuid,uuid,text) to service_role;
grant execute on function public.mme_procurement_approve_purchase_request(uuid,uuid,text) to service_role;
grant execute on function public.mme_procurement_record_vendor_performance(uuid,text,date,date,integer,integer,uuid) to service_role;
commit;