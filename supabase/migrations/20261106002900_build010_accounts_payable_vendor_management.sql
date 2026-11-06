begin;
create table if not exists public.mme_ap_vendors(
 vendor_id uuid primary key default gen_random_uuid(),
 vendor_code text not null unique,
 legal_name text not null,
 display_name text not null,
 tax_id_last4 text,
 remit_email text,
 remit_phone text,
 payment_terms_days integer not null default 30 check(payment_terms_days between 0 and 365),
 currency char(3) not null default 'USD',
 vendor_status text not null default 'pending_review' check(vendor_status in ('pending_review','active','on_hold','inactive')),
 default_gl_account text,
 created_by_auth_user_id uuid not null,
 reviewed_by_auth_user_id uuid,
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 check(reviewed_by_auth_user_id is null or reviewed_by_auth_user_id<>created_by_auth_user_id)
);
create table if not exists public.mme_ap_vendor_remittance(
 remittance_id uuid primary key default gen_random_uuid(),
 vendor_id uuid not null references public.mme_ap_vendors(vendor_id),
 method text not null check(method in ('check','ach','wire','card','other')),
 account_holder text,
 bank_name text,
 routing_last4 text,
 account_last4 text,
 encrypted_secret_reference text,
 verification_status text not null default 'unverified' check(verification_status in ('unverified','pending','verified','rejected')),
 verified_by_auth_user_id uuid,
 verified_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_ap_purchase_orders(
 purchase_order_id uuid primary key default gen_random_uuid(),
 po_number text not null unique,
 vendor_id uuid not null references public.mme_ap_vendors(vendor_id),
 issue_date date not null,
 expected_date date,
 currency char(3) not null default 'USD',
 po_status text not null default 'draft' check(po_status in ('draft','approved','partially_received','received','closed','cancelled')),
 subtotal numeric(16,2) not null default 0 check(subtotal>=0),
 tax_amount numeric(16,2) not null default 0 check(tax_amount>=0),
 total_amount numeric(16,2) not null default 0 check(total_amount>=0),
 created_by_auth_user_id uuid not null,
 approved_by_auth_user_id uuid,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_ap_purchase_order_lines(
 po_line_id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.mme_ap_purchase_orders(purchase_order_id) on delete cascade,
 item_code text,
 description text not null,
 quantity numeric(16,4) not null check(quantity>0),
 unit_price numeric(16,4) not null check(unit_price>=0),
 received_quantity numeric(16,4) not null default 0 check(received_quantity>=0 and received_quantity<=quantity),
 line_total numeric(16,2) not null check(line_total>=0)
);
create table if not exists public.mme_ap_invoices(
 invoice_id uuid primary key default gen_random_uuid(),
 vendor_id uuid not null references public.mme_ap_vendors(vendor_id),
 purchase_order_id uuid references public.mme_ap_purchase_orders(purchase_order_id),
 vendor_invoice_number text not null,
 invoice_date date not null,
 received_date date not null default current_date,
 due_date date not null,
 currency char(3) not null default 'USD',
 subtotal numeric(16,2) not null check(subtotal>=0),
 tax_amount numeric(16,2) not null default 0 check(tax_amount>=0),
 total_amount numeric(16,2) not null check(total_amount>0),
 invoice_status text not null default 'received' check(invoice_status in ('received','under_review','matched','approval_pending','approved','scheduled','partially_paid','paid','disputed','rejected','void')),
 document_storage_path text,
 duplicate_check_key text not null,
 created_by_auth_user_id uuid not null,
 approved_by_auth_user_id uuid,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 unique(vendor_id,vendor_invoice_number),
 unique(duplicate_check_key),
 check(due_date>=invoice_date)
);
create table if not exists public.mme_ap_invoice_lines(
 invoice_line_id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.mme_ap_invoices(invoice_id) on delete cascade,
 po_line_id uuid references public.mme_ap_purchase_order_lines(po_line_id),
 description text not null,
 quantity numeric(16,4) not null default 1 check(quantity>0),
 unit_price numeric(16,4) not null check(unit_price>=0),
 line_total numeric(16,2) not null check(line_total>=0),
 gl_account text,
 received_quantity numeric(16,4) not null default 0 check(received_quantity>=0)
);
create table if not exists public.mme_ap_receipts(
 receipt_id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.mme_ap_purchase_orders(purchase_order_id),
 po_line_id uuid not null references public.mme_ap_purchase_order_lines(po_line_id),
 received_quantity numeric(16,4) not null check(received_quantity>0),
 received_date date not null default current_date,
 condition_status text not null default 'accepted' check(condition_status in ('accepted','damaged','rejected','quarantined')),
 recorded_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_ap_match_results(
 match_id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.mme_ap_invoices(invoice_id),
 purchase_order_id uuid references public.mme_ap_purchase_orders(purchase_order_id),
 match_type text not null check(match_type in ('two_way','three_way')),
 po_total numeric(16,2) not null,
 invoice_total numeric(16,2) not null,
 receipt_quantity_variance numeric(16,4) not null default 0,
 amount_variance numeric(16,2) not null,
 match_status text not null check(match_status in ('matched','variance','blocked')),
 variance_details jsonb not null default '{}',
 evaluated_by_auth_user_id uuid not null,
 evaluated_at timestamptz not null default now()
);
create table if not exists public.mme_ap_approvals(
 approval_id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.mme_ap_invoices(invoice_id),
 approval_step integer not null check(approval_step>0),
 approver_auth_user_id uuid,
 approval_status text not null default 'pending' check(approval_status in ('pending','approved','rejected')),
 decision_note text,
 decided_at timestamptz,
 created_at timestamptz not null default now(),
 unique(invoice_id,approval_step)
);
create table if not exists public.mme_ap_payment_schedules(
 schedule_id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.mme_ap_invoices(invoice_id),
 scheduled_date date not null,
 amount numeric(16,2) not null check(amount>0),
 currency char(3) not null default 'USD',
 payment_method text not null check(payment_method in ('check','ach','wire','card','other')),
 schedule_status text not null default 'pending_approval' check(schedule_status in ('pending_approval','approved','queued','sent_to_provider','settled','failed','cancelled')),
 approved_by_auth_user_id uuid,
 provider_reference text,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_ap_payment_events(
 event_id uuid primary key default gen_random_uuid(),
 schedule_id uuid not null references public.mme_ap_payment_schedules(schedule_id),
 event_type text not null,
 event_reference text,
 details jsonb not null default '{}',
 actor_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_ap_audit(
 audit_id uuid primary key default gen_random_uuid(),
 actor_auth_user_id uuid not null,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index if not exists mme_ap_invoices_due_status_idx on public.mme_ap_invoices(invoice_status,due_date);
create index if not exists mme_ap_payment_schedule_status_date_idx on public.mme_ap_payment_schedules(schedule_status,scheduled_date);
create or replace function public.mme_ap_review_invoice(p_invoice uuid,p_decision text,p_note text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare i public.mme_ap_invoices%rowtype;
begin
 if p_decision not in ('approved','rejected') then raise exception 'invalid_invoice_decision';end if;
 select * into i from public.mme_ap_invoices where invoice_id=p_invoice for update;
 if not found or i.invoice_status not in ('received','under_review','matched','approval_pending','disputed') then raise exception 'invoice_not_reviewable';end if;
 if i.created_by_auth_user_id=p_actor then raise exception 'invoice_submitter_cannot_approve';end if;
 if p_decision='approved' and i.invoice_status<>'matched' then raise exception 'invoice_must_be_matched_before_approval';end if;
 update public.mme_ap_invoices set invoice_status=p_decision,approved_by_auth_user_id=case when p_decision='approved' then p_actor else null end,approved_at=case when p_decision='approved' then now() else null end where invoice_id=p_invoice;
 insert into public.mme_ap_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'invoice_'||p_decision,'invoice',p_invoice,jsonb_build_object('note',left(coalesce(p_note,''),1000)));
 return p_invoice;
end $$;
create or replace function public.mme_ap_schedule_payment(p_invoice uuid,p_date date,p_amount numeric,p_method text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare i public.mme_ap_invoices%rowtype;v uuid;v_paid numeric(16,2);
begin
 select * into i from public.mme_ap_invoices where invoice_id=p_invoice for update;
 if not found or i.invoice_status not in ('approved','partially_paid') then raise exception 'invoice_not_approved_for_scheduling';end if;
 if p_date is null or p_amount<=0 or p_method not in ('check','ach','wire','card','other') then raise exception 'invalid_payment_schedule';end if;
 select coalesce(sum(amount),0) into v_paid from public.mme_ap_payment_schedules where invoice_id=p_invoice and schedule_status not in ('failed','cancelled');
 if v_paid+p_amount>i.total_amount then raise exception 'scheduled_payments_exceed_invoice_total';end if;
 insert into public.mme_ap_payment_schedules(invoice_id,scheduled_date,amount,currency,payment_method,created_by_auth_user_id) values(p_invoice,p_date,p_amount,i.currency,p_method,p_actor) returning schedule_id into v;
 insert into public.mme_ap_payment_events(schedule_id,event_type,details,actor_auth_user_id) values(v,'payment_scheduled',jsonb_build_object('invoice_id',p_invoice,'amount',p_amount,'note','Scheduling only; no funds transferred'),p_actor);
 insert into public.mme_ap_audit(actor_auth_user_id,action,entity_type,entity_id,details) values(p_actor,'payment_scheduled','payment_schedule',v,jsonb_build_object('invoice_id',p_invoice,'amount',p_amount));
 return v;
end $$;
alter table public.mme_ap_vendors enable row level security;
alter table public.mme_ap_vendor_remittance enable row level security;
alter table public.mme_ap_purchase_orders enable row level security;
alter table public.mme_ap_purchase_order_lines enable row level security;
alter table public.mme_ap_invoices enable row level security;
alter table public.mme_ap_invoice_lines enable row level security;
alter table public.mme_ap_receipts enable row level security;
alter table public.mme_ap_match_results enable row level security;
alter table public.mme_ap_approvals enable row level security;
alter table public.mme_ap_payment_schedules enable row level security;
alter table public.mme_ap_payment_events enable row level security;
alter table public.mme_ap_audit enable row level security;
revoke all on public.mme_ap_vendors,public.mme_ap_vendor_remittance,public.mme_ap_purchase_orders,public.mme_ap_purchase_order_lines,public.mme_ap_invoices,public.mme_ap_invoice_lines,public.mme_ap_receipts,public.mme_ap_match_results,public.mme_ap_approvals,public.mme_ap_payment_schedules,public.mme_ap_payment_events,public.mme_ap_audit from public,anon,authenticated;
grant all on public.mme_ap_vendors,public.mme_ap_vendor_remittance,public.mme_ap_purchase_orders,public.mme_ap_purchase_order_lines,public.mme_ap_invoices,public.mme_ap_invoice_lines,public.mme_ap_receipts,public.mme_ap_match_results,public.mme_ap_approvals,public.mme_ap_payment_schedules,public.mme_ap_payment_events,public.mme_ap_audit to service_role;
revoke all on function public.mme_ap_review_invoice(uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_ap_schedule_payment(uuid,date,numeric,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_ap_review_invoice(uuid,text,text,uuid) to service_role;
grant execute on function public.mme_ap_schedule_payment(uuid,date,numeric,text,uuid) to service_role;
commit;