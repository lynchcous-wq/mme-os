-- Build 009.58 — receiving, reconciliation and controlled inventory intake staging.
begin;
create table public.mme_receiving_sessions (
 receiving_session_id uuid primary key default gen_random_uuid(),
 po_draft_id uuid not null references public.mme_procurement_purchase_order_drafts(po_draft_id) on delete restrict,
 request_id uuid not null references public.mme_procurement_purchase_requests(request_id) on delete restrict,
 location_code text not null,
 carrier text, tracking_reference text, supplier_packing_slip text,
 received_by uuid not null, received_at timestamptz not null default now(),
 session_status text not null default 'in_progress' check(session_status in ('in_progress','reconciled','exception','closed')),
 notes text, created_at timestamptz not null default now()
);
create index mme_receiving_sessions_po_idx on public.mme_receiving_sessions(po_draft_id,received_at desc);
create table public.mme_receiving_lines (
 receiving_line_id uuid primary key default gen_random_uuid(),
 receiving_session_id uuid not null references public.mme_receiving_sessions(receiving_session_id) on delete restrict,
 sku_reference text not null, expected_quantity integer not null check(expected_quantity>=1),
 physically_received_quantity integer not null check(physically_received_quantity>=0),
 accepted_quantity integer not null check(accepted_quantity>=0),
 damaged_quantity integer not null default 0 check(damaged_quantity>=0),
 missing_quantity integer not null default 0 check(missing_quantity>=0),
 unit_cost numeric(14,2) not null check(unit_cost>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 condition_grade text check(condition_grade is null or condition_grade in ('new','open_box','refurbished','used','damaged','unknown')),
 line_status text not null default 'pending' check(line_status in ('pending','matched','short','over','damaged','quarantined','accepted')),
 created_at timestamptz not null default now(),
 check(accepted_quantity+damaged_quantity<=physically_received_quantity),
 check(physically_received_quantity+missing_quantity>=expected_quantity or physically_received_quantity+missing_quantity<expected_quantity)
);
create index mme_receiving_lines_session_idx on public.mme_receiving_lines(receiving_session_id);
create table public.mme_receiving_serials (
 receiving_serial_id uuid primary key default gen_random_uuid(),
 receiving_line_id uuid not null references public.mme_receiving_lines(receiving_line_id) on delete restrict,
 serial_number text, imei text, barcode text,
 serial_status text not null default 'received' check(serial_status in ('received','accepted','quarantined','rejected')),
 activation_lock_status text check(activation_lock_status is null or activation_lock_status in ('clear','locked','unknown','not_applicable')),
 device_test_status text not null default 'not_tested' check(device_test_status in ('not_tested','passed','failed','quarantined')),
 captured_by uuid not null, captured_at timestamptz not null default now(),
 check(serial_number is not null or imei is not null or barcode is not null),
 unique(imei), unique(serial_number), unique(barcode)
);
create table public.mme_receiving_discrepancies (
 discrepancy_id uuid primary key default gen_random_uuid(),
 receiving_session_id uuid not null references public.mme_receiving_sessions(receiving_session_id) on delete restrict,
 receiving_line_id uuid references public.mme_receiving_lines(receiving_line_id) on delete restrict,
 discrepancy_type text not null check(discrepancy_type in ('short_shipment','over_shipment','damaged','wrong_sku','serial_mismatch','price_mismatch','missing_document','other')),
 severity text not null default 'medium' check(severity in ('low','medium','high','critical')),
 description text not null, evidence_reference text,
 resolution_status text not null default 'open' check(resolution_status in ('open','under_review','supplier_credit_pending','resolved','waived')),
 resolution_note text, resolved_by uuid, resolved_at timestamptz,
 created_by uuid not null, created_at timestamptz not null default now()
);
create index mme_receiving_discrepancies_open_idx on public.mme_receiving_discrepancies(resolution_status,severity,created_at);
create table public.mme_receiving_landed_costs (
 landed_cost_id uuid primary key default gen_random_uuid(),
 receiving_session_id uuid not null references public.mme_receiving_sessions(receiving_session_id) on delete restrict,
 cost_type text not null check(cost_type in ('freight','insurance','duties','tax','handling','brokerage','other')),
 amount numeric(14,2) not null check(amount>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 evidence_reference text, entered_by uuid not null, created_at timestamptz not null default now()
);
create table public.mme_receiving_intake_staging (
 intake_id uuid primary key default gen_random_uuid(),
 receiving_line_id uuid not null unique references public.mme_receiving_lines(receiving_line_id) on delete restrict,
 sku_reference text not null, location_code text not null, accepted_quantity integer not null check(accepted_quantity>=1),
 unit_cost numeric(14,2) not null check(unit_cost>=0), allocated_landed_cost numeric(14,2) not null default 0 check(allocated_landed_cost>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 intake_status text not null default 'pending_inventory_post' check(intake_status in ('pending_inventory_post','posted','blocked','reversed')),
 posted_inventory_reference text, created_at timestamptz not null default now(), posted_at timestamptz
);
create table public.mme_receiving_ap_matches (
 ap_match_id uuid primary key default gen_random_uuid(),
 receiving_session_id uuid not null references public.mme_receiving_sessions(receiving_session_id) on delete restrict,
 supplier_invoice_reference text not null, invoice_amount numeric(14,2) not null check(invoice_amount>=0),
 invoice_currency text not null check(invoice_currency ~ '^[A-Z]{3}$'),
 po_amount numeric(14,2) not null check(po_amount>=0), received_goods_amount numeric(14,2) not null check(received_goods_amount>=0),
 match_status text not null default 'pending' check(match_status in ('pending','matched','variance','blocked')),
 variance_amount numeric(14,2) generated always as (invoice_amount-received_goods_amount) stored,
 tolerance_amount numeric(14,2) not null default 0 check(tolerance_amount>=0),
 reviewed_by uuid, reviewed_at timestamptz, review_note text, created_by uuid not null, created_at timestamptz not null default now()
);
create table public.mme_receiving_audit (
 audit_id bigint generated always as identity primary key, actor_user_id uuid not null,
 entity_type text not null, entity_id uuid, action text not null,
 prior_state jsonb not null default '{}'::jsonb, new_state jsonb not null default '{}'::jsonb,
 reason text, created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['mme_receiving_sessions','mme_receiving_lines','mme_receiving_serials','mme_receiving_discrepancies','mme_receiving_landed_costs','mme_receiving_intake_staging','mme_receiving_ap_matches','mme_receiving_audit']
 loop execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t); end loop;
end $$;
grant select,insert,update on public.mme_receiving_sessions,public.mme_receiving_lines,public.mme_receiving_serials,
 public.mme_receiving_discrepancies,public.mme_receiving_landed_costs,public.mme_receiving_intake_staging,
 public.mme_receiving_ap_matches to service_role;
grant select,insert on public.mme_receiving_audit to service_role;
revoke update,delete,truncate on public.mme_receiving_audit from public,anon,authenticated,service_role;

create or replace function public.mme_receiving_open_session(p_po_draft_id uuid,p_location text,p_actor uuid,p_carrier text default null,p_tracking text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare po public.mme_procurement_purchase_order_drafts%rowtype; req public.mme_procurement_purchase_requests%rowtype; sid uuid;
begin
 select * into po from public.mme_procurement_purchase_order_drafts where po_draft_id=p_po_draft_id;
 if not found or po.draft_status not in ('draft','exported_for_review','submitted_confirmed') then raise exception 'Eligible purchase order draft required' using errcode='55000'; end if;
 select * into req from public.mme_procurement_purchase_requests where request_id=po.request_id;
 insert into public.mme_receiving_sessions(po_draft_id,request_id,location_code,carrier,tracking_reference,received_by)
 values(po.po_draft_id,req.request_id,p_location,p_carrier,p_tracking,p_actor) returning receiving_session_id into sid;
 insert into public.mme_receiving_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'receiving_session',sid,'receiving_session_opened',jsonb_build_object('po_draft_id',po.po_draft_id,'location',p_location));
 return sid;
end; $$;

create or replace function public.mme_receiving_add_line(p_session uuid,p_actor uuid,p_sku text,p_physically_received integer,p_accepted integer,p_damaged integer,p_unit_cost numeric,p_currency text,p_grade text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare s public.mme_receiving_sessions%rowtype; r public.mme_procurement_purchase_requests%rowtype; qty integer; lid uuid; missing integer;
begin
 select * into s from public.mme_receiving_sessions where receiving_session_id=p_session for update;
 if not found or s.session_status<>'in_progress' then raise exception 'Open receiving session required' using errcode='55000'; end if;
 select * into r from public.mme_procurement_purchase_requests where request_id=s.request_id for update;
 if r.sku_reference<>p_sku then raise exception 'Received SKU does not match purchase request' using errcode='22023'; end if;
 select coalesce(sum(physically_received_quantity),0) into qty from public.mme_receiving_lines l join public.mme_receiving_sessions ss using(receiving_session_id) where ss.request_id=r.request_id;
 if p_physically_received+qty>r.requested_quantity then raise exception 'Over-receipt blocked; record an exception for review' using errcode='23514'; end if;
 if p_accepted<0 or p_damaged<0 or p_accepted+p_damaged>p_physically_received then raise exception 'Invalid accepted/damaged quantities' using errcode='22023'; end if;
 missing:=greatest(0,r.requested_quantity-qty-p_physically_received);
 insert into public.mme_receiving_lines(receiving_session_id,sku_reference,expected_quantity,physically_received_quantity,accepted_quantity,damaged_quantity,missing_quantity,unit_cost,currency_code,condition_grade,line_status)
 values(p_session,p_sku,r.requested_quantity,p_physically_received,p_accepted,p_damaged,missing,p_unit_cost,p_currency,p_grade,
 case when p_damaged>0 then 'damaged' when missing>0 then 'short' else 'matched' end) returning receiving_line_id into lid;
 if p_damaged>0 or missing>0 then
 insert into public.mme_receiving_discrepancies(receiving_session_id,receiving_line_id,discrepancy_type,severity,description,created_by)
 values(p_session,lid,case when p_damaged>0 then 'damaged' else 'short_shipment' end,case when p_damaged>0 then 'high' else 'medium' end,
 'Receiving discrepancy: physically received '||p_physically_received||', accepted '||p_accepted||', damaged '||p_damaged||', outstanding '||missing,p_actor); end if;
 if p_accepted>0 then
 insert into public.mme_receiving_intake_staging(receiving_line_id,sku_reference,location_code,accepted_quantity,unit_cost,currency_code)
 values(lid,p_sku,s.location_code,p_accepted,p_unit_cost,p_currency);
 end if;
 insert into public.mme_receiving_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'receiving_line',lid,'receiving_line_recorded',jsonb_build_object('sku',p_sku,'received',p_physically_received,'accepted',p_accepted,'damaged',p_damaged,'missing',missing));
 return lid;
end; $$;

create or replace function public.mme_receiving_capture_serial(p_line uuid,p_actor uuid,p_serial text,p_imei text,p_barcode text,p_activation text,p_test text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid;
begin
 if coalesce(nullif(trim(p_serial),''),nullif(trim(p_imei),''),nullif(trim(p_barcode),'')) is null then raise exception 'Serial, IMEI or barcode required' using errcode='22023'; end if;
 insert into public.mme_receiving_serials(receiving_line_id,serial_number,imei,barcode,activation_lock_status,device_test_status,captured_by)
 values(p_line,nullif(trim(p_serial),''),nullif(trim(p_imei),''),nullif(trim(p_barcode),''),p_activation,p_test) returning receiving_serial_id into v_id;
 insert into public.mme_receiving_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'receiving_serial',v_id,'serial_captured',jsonb_build_object('line',p_line,'imei_present',p_imei is not null,'test_status',p_test));
 return v_id;
end; $$;

create or replace function public.mme_receiving_add_landed_cost(p_session uuid,p_actor uuid,p_type text,p_amount numeric,p_currency text,p_evidence text default null)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid;
begin
 insert into public.mme_receiving_landed_costs(receiving_session_id,cost_type,amount,currency_code,evidence_reference,entered_by)
 values(p_session,p_type,p_amount,p_currency,p_evidence,p_actor) returning landed_cost_id into v_id;
 insert into public.mme_receiving_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'landed_cost',v_id,'landed_cost_recorded',jsonb_build_object('session',p_session,'type',p_type,'amount',p_amount,'currency',p_currency));
 return v_id;
end; $$;

create or replace function public.mme_receiving_finalize_session(p_session uuid,p_actor uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare s public.mme_receiving_sessions%rowtype; r public.mme_procurement_purchase_requests%rowtype; total_received integer; open_exceptions integer;
begin
 select * into s from public.mme_receiving_sessions where receiving_session_id=p_session for update;
 if not found or s.session_status<>'in_progress' then raise exception 'Open receiving session required' using errcode='55000'; end if;
 select * into r from public.mme_procurement_purchase_requests where request_id=s.request_id for update;
 select coalesce(sum(physically_received_quantity),0) into total_received from public.mme_receiving_lines where receiving_session_id=p_session;
 select count(*) into open_exceptions from public.mme_receiving_discrepancies where receiving_session_id=p_session and resolution_status not in ('resolved','waived');
 update public.mme_receiving_sessions set session_status=case when open_exceptions>0 or total_received<r.requested_quantity then 'exception' else 'reconciled' end where receiving_session_id=p_session;
 insert into public.mme_receiving_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'receiving_session',p_session,'receiving_session_finalized',jsonb_build_object('received',total_received,'expected',r.requested_quantity,'open_exceptions',open_exceptions));
end; $$;

create or replace function public.mme_receiving_match_supplier_invoice(p_session uuid,p_actor uuid,p_invoice_ref text,p_invoice_amount numeric,p_currency text,p_tolerance numeric default 0)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare s public.mme_receiving_sessions%rowtype; po public.mme_procurement_purchase_order_drafts%rowtype; received numeric(14,2); mid uuid; stat text;
begin
 select * into s from public.mme_receiving_sessions where receiving_session_id=p_session;
 if not found then raise exception 'Receiving session required' using errcode='22023'; end if;
 select * into po from public.mme_procurement_purchase_order_drafts where po_draft_id=s.po_draft_id;
 select coalesce(sum(accepted_quantity*unit_cost),0) into received from public.mme_receiving_lines where receiving_session_id=p_session;
 stat:=case when p_currency<>po.currency_code then 'blocked' when abs(p_invoice_amount-received)<=p_tolerance then 'matched' else 'variance' end;
 insert into public.mme_receiving_ap_matches(receiving_session_id,supplier_invoice_reference,invoice_amount,invoice_currency,po_amount,received_goods_amount,match_status,tolerance_amount,created_by)
 values(p_session,p_invoice_ref,p_invoice_amount,p_currency,po.total_amount,received,stat,p_tolerance,p_actor) returning ap_match_id into mid;
 insert into public.mme_receiving_audit(actor_user_id,entity_type,entity_id,action,new_state)
 values(p_actor,'ap_match',mid,'supplier_invoice_matched',jsonb_build_object('status',stat,'invoice_amount',p_invoice_amount,'received_value',received,'currency',p_currency));
 return mid;
end; $$;
create or replace view public.mme_receiving_landed_cost_summary as
select l.receiving_line_id,l.sku_reference,l.accepted_quantity,l.unit_cost,l.currency_code,
 coalesce(sum(c.amount) filter(where c.currency_code=l.currency_code),0) as session_landed_cost_same_currency
from public.mme_receiving_lines l join public.mme_receiving_sessions s using(receiving_session_id)
left join public.mme_receiving_landed_costs c using(receiving_session_id)
group by l.receiving_line_id,l.sku_reference,l.accepted_quantity,l.unit_cost,l.currency_code;
revoke all on public.mme_receiving_landed_cost_summary from public,anon,authenticated;
grant select on public.mme_receiving_landed_cost_summary to service_role;
revoke all on function public.mme_receiving_open_session(uuid,text,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_receiving_add_line(uuid,uuid,text,integer,integer,integer,numeric,text,text) from public,anon,authenticated;
revoke all on function public.mme_receiving_capture_serial(uuid,uuid,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_receiving_add_landed_cost(uuid,uuid,text,numeric,text,text) from public,anon,authenticated;
revoke all on function public.mme_receiving_finalize_session(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_receiving_match_supplier_invoice(uuid,uuid,text,numeric,text,numeric) from public,anon,authenticated;
grant execute on function public.mme_receiving_open_session(uuid,text,uuid,text,text) to service_role;
grant execute on function public.mme_receiving_add_line(uuid,uuid,text,integer,integer,integer,numeric,text,text) to service_role;
grant execute on function public.mme_receiving_capture_serial(uuid,uuid,text,text,text,text,text) to service_role;
grant execute on function public.mme_receiving_add_landed_cost(uuid,uuid,text,numeric,text,text) to service_role;
grant execute on function public.mme_receiving_finalize_session(uuid,uuid) to service_role;
grant execute on function public.mme_receiving_match_supplier_invoice(uuid,uuid,text,numeric,text,numeric) to service_role;
commit;
