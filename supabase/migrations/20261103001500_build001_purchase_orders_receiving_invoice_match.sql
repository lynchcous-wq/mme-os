-- Build 001: formal purchase orders and controlled partial receiving.
create table public.mme_purchase_orders (
 id uuid primary key default gen_random_uuid(),
 po_number text not null unique,
 proposal_id uuid not null references public.mme_purchase_proposals(id) on delete restrict,
 supplier_id uuid not null references public.mme_suppliers(id) on delete restrict,
 status text not null default 'draft' check(status in ('draft','submitted','approved','rejected','issued','acknowledged','partially_received','received','cancelled')),
 currency text not null default 'USD' check(currency='USD'),
 subtotal_cents bigint not null default 0 check(subtotal_cents>=0),
 shipping_cents bigint not null default 0 check(shipping_cents>=0),
 tax_cents bigint not null default 0 check(tax_cents>=0),
 total_cents bigint not null default 0 check(total_cents>=0),
 supplier_order_reference text, expected_delivery_at timestamptz,
 created_by_identity_id uuid not null, approved_by_identity_id uuid, approved_at timestamptz,
 issued_by_identity_id uuid, issued_at timestamptz, acknowledged_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 decision_note text
);
create table public.mme_purchase_order_lines (
 id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.mme_purchase_orders(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 description_snapshot text not null, supplier_sku text,
 ordered_quantity integer not null check(ordered_quantity>0),
 received_quantity integer not null default 0 check(received_quantity>=0 and received_quantity<=ordered_quantity),
 unit_cost_cents bigint not null check(unit_cost_cents>=0),
 line_total_cents bigint generated always as (ordered_quantity::bigint*unit_cost_cents) stored,
 unique(purchase_order_id,product_id,location_id)
);
create table public.mme_purchase_order_events (
 id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.mme_purchase_orders(id) on delete restrict,
 event_type text not null,event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 actor_identity_id uuid not null,created_at timestamptz not null default now()
);
create table public.mme_purchase_order_shipments (
 id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.mme_purchase_orders(id) on delete restrict,
 carrier text,tracking_number text,
 shipment_status text not null check(shipment_status in ('pending','label_created','in_transit','delayed','delivered','exception','cancelled')),
 estimated_delivery_at timestamptz,delivered_at timestamptz,notes text,
 recorded_by_identity_id uuid not null,created_at timestamptz not null default now()
);
create table public.mme_supplier_invoices (
 id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.mme_purchase_orders(id) on delete restrict,
 invoice_number text not null,invoice_date date,due_date date,
 subtotal_cents bigint not null check(subtotal_cents>=0),
 shipping_cents bigint not null default 0 check(shipping_cents>=0),
 tax_cents bigint not null default 0 check(tax_cents>=0),
 total_cents bigint not null check(total_cents=subtotal_cents+shipping_cents+tax_cents),
 match_status text not null default 'pending' check(match_status in ('pending','matched','variance','disputed')),
 document_storage_path text,recorded_by_identity_id uuid not null,
 matched_by_identity_id uuid,matched_at timestamptz,created_at timestamptz not null default now(),
 unique(purchase_order_id,invoice_number)
);
create table public.mme_supplier_invoice_lines (
 id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.mme_supplier_invoices(id) on delete restrict,
 purchase_order_line_id uuid not null references public.mme_purchase_order_lines(id) on delete restrict,
 invoiced_quantity integer not null check(invoiced_quantity>0),
 invoiced_unit_cost_cents bigint not null check(invoiced_unit_cost_cents>=0),
 unique(invoice_id,purchase_order_line_id)
);
create index mme_po_supplier_status_idx on public.mme_purchase_orders(supplier_id,status,created_at desc);
create index mme_po_events_idx on public.mme_purchase_order_events(purchase_order_id,created_at);
create index mme_po_shipments_tracking_idx on public.mme_purchase_order_shipments(tracking_number);
alter table public.mme_purchase_orders enable row level security;
alter table public.mme_purchase_order_lines enable row level security;
alter table public.mme_purchase_order_events enable row level security;
alter table public.mme_purchase_order_shipments enable row level security;
alter table public.mme_supplier_invoices enable row level security;
alter table public.mme_supplier_invoice_lines enable row level security;
revoke all on public.mme_purchase_orders,public.mme_purchase_order_lines,public.mme_purchase_order_events,public.mme_purchase_order_shipments,public.mme_supplier_invoices,public.mme_supplier_invoice_lines from anon,authenticated;
grant all on public.mme_purchase_orders,public.mme_purchase_order_lines,public.mme_purchase_order_events,public.mme_purchase_order_shipments,public.mme_supplier_invoices,public.mme_supplier_invoice_lines to service_role;

create or replace function public.mme_create_purchase_order(p_po_number text,p_proposal_id uuid,p_supplier_id uuid,p_shipping_cents bigint,p_tax_cents bigint,p_actor_identity_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_p record; v_total numeric;
begin
 if p_po_number is null or length(btrim(p_po_number)) not between 3 and 80 or p_actor_identity_id is null or p_shipping_cents<0 or p_tax_cents<0 then raise exception 'Invalid PO request' using errcode='22023'; end if;
 select * into v_p from public.mme_purchase_proposals where id=p_proposal_id for update;
 if not found or v_p.status<>'approved' then raise exception 'Proposal must be approved before PO creation' using errcode='P0001'; end if;
 perform 1 from public.mme_suppliers where id=p_supplier_id and status='active' for update;
 if not found then raise exception 'Active supplier required' using errcode='P0002'; end if;
 insert into public.mme_purchase_orders(po_number,proposal_id,supplier_id,shipping_cents,tax_cents,created_by_identity_id)
 values(upper(btrim(p_po_number)),p_proposal_id,p_supplier_id,p_shipping_cents,p_tax_cents,p_actor_identity_id) returning id into v_id;
 insert into public.mme_purchase_order_lines(purchase_order_id,product_id,location_id,description_snapshot,ordered_quantity,unit_cost_cents,supplier_sku)
 select v_id,pl.product_id,pl.location_id,p.title,pl.suggested_quantity,
  coalesce((select h.unit_cost_cents from public.mme_supplier_price_history h where h.supplier_id=p_supplier_id and h.product_id=pl.product_id and (h.valid_until is null or h.valid_until>=now()) order by h.recorded_at desc limit 1),pl.estimated_unit_cost_cents),
  sp.supplier_sku
 from public.mme_purchase_proposal_lines pl join public.mme_products p on p.id=pl.product_id
 left join public.mme_supplier_products sp on sp.supplier_id=p_supplier_id and sp.product_id=pl.product_id
 where pl.proposal_id=p_proposal_id;
 select coalesce(sum(line_total_cents),0) into v_total from public.mme_purchase_order_lines where purchase_order_id=v_id;
 if v_total+p_shipping_cents+p_tax_cents>9000000000000000 then raise exception 'PO total exceeds supported amount' using errcode='22003'; end if;
 update public.mme_purchase_orders set subtotal_cents=v_total,total_cents=v_total+p_shipping_cents+p_tax_cents where id=v_id;
 insert into public.mme_purchase_order_events(purchase_order_id,event_type,event_data,actor_identity_id) values(v_id,'created',jsonb_build_object('proposal_id',p_proposal_id),p_actor_identity_id);
 return v_id;
end; $$;

create or replace function public.mme_set_purchase_order_status(p_po_id uuid,p_action text,p_actor_identity_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_old text; v_new text;
begin
 if p_po_id is null or p_actor_identity_id is null or p_action not in ('submit','approve','reject','issue','acknowledge','cancel') then raise exception 'Invalid PO transition' using errcode='22023'; end if;
 select status into v_old from public.mme_purchase_orders where id=p_po_id for update;
 if not found then return false; end if;
 v_new:=case p_action when 'submit' then 'submitted' when 'approve' then 'approved' when 'reject' then 'rejected' when 'issue' then 'issued' when 'acknowledge' then 'acknowledged' when 'cancel' then 'cancelled' end;
 if not ((v_old='draft' and p_action='submit') or (v_old='submitted' and p_action in ('approve','reject')) or (v_old='approved' and p_action='issue') or (v_old='issued' and p_action='acknowledge') or (v_old in ('draft','submitted','approved','issued','acknowledged','partially_received') and p_action='cancel')) then return false; end if;
 update public.mme_purchase_orders set status=v_new,
  approved_by_identity_id=case when p_action='approve' then p_actor_identity_id else approved_by_identity_id end,
  approved_at=case when p_action='approve' then now() else approved_at end,
  issued_by_identity_id=case when p_action='issue' then p_actor_identity_id else issued_by_identity_id end,
  issued_at=case when p_action='issue' then now() else issued_at end,
  acknowledged_at=case when p_action='acknowledge' then now() else acknowledged_at end,
  decision_note=coalesce(p_note,decision_note),updated_at=now() where id=p_po_id;
 insert into public.mme_purchase_order_events(purchase_order_id,event_type,event_data,actor_identity_id)
 values(p_po_id,p_action,jsonb_build_object('note',p_note,'from',v_old,'to',v_new),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_receive_purchase_order_lines(p_po_id uuid,p_receipt_reference text,p_actor_identity_id uuid,p_approved_by_identity_id uuid,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_po record; v_line record; v_receipt uuid; v_items jsonb:='[]'::jsonb; v_count integer:=0; v_total integer;
begin
 select * into v_po from public.mme_purchase_orders where id=p_po_id for update;
 if not found or v_po.status not in ('issued','acknowledged','partially_received') then raise exception 'PO not open for receiving' using errcode='P0001'; end if;
 if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 or p_actor_identity_id is null then raise exception 'Invalid receipt lines' using errcode='22023'; end if;
 for v_line in select l.*,x.quantity as qty from jsonb_to_recordset(p_lines) x(line_id uuid,quantity integer) join public.mme_purchase_order_lines l on l.id=x.line_id where l.purchase_order_id=p_po_id order by l.product_id,l.location_id
 loop
  if v_line.qty is null or v_line.qty<1 or v_line.received_quantity+v_line.qty>v_line.ordered_quantity then raise exception 'Receipt exceeds remaining PO quantity' using errcode='23514'; end if;
  v_items:=v_items||jsonb_build_array(jsonb_build_object('product_id',v_line.product_id,'location_id',v_line.location_id,'quantity',v_line.qty,'unit_cost_cents',v_line.unit_cost_cents));
  update public.mme_purchase_order_lines set received_quantity=received_quantity+v_line.qty where id=v_line.id;
  v_count:=v_count+1;
 end loop;
 select count(*) into v_total from jsonb_to_recordset(p_lines) x(line_id uuid,quantity integer);
 if v_count=0 or v_count<>v_total then raise exception 'PO line not found or duplicated' using errcode='22023'; end if;
 v_receipt:=public.mme_receive_inventory(p_receipt_reference,v_po.supplier_order_reference,'supplier',
  (select coalesce(sum((x->>'quantity')::bigint*(x->>'unit_cost_cents')::bigint),0) from jsonb_array_elements(v_items) x),
  p_actor_identity_id,p_approved_by_identity_id,'PO '||v_po.po_number,v_items);
 if not exists(select 1 from public.mme_purchase_order_lines where purchase_order_id=p_po_id and received_quantity<ordered_quantity) then
  update public.mme_purchase_orders set status='received',updated_at=now() where id=p_po_id;
 else update public.mme_purchase_orders set status='partially_received',updated_at=now() where id=p_po_id; end if;
 insert into public.mme_purchase_order_events(purchase_order_id,event_type,event_data,actor_identity_id)
 values(p_po_id,'receipt',jsonb_build_object('receipt_id',v_receipt,'reference',p_receipt_reference),p_actor_identity_id);
 return v_receipt;
end; $$;

create or replace function public.mme_record_supplier_invoice(p_po_id uuid,p_invoice_number text,p_subtotal bigint,p_shipping bigint,p_tax bigint,p_total bigint,p_actor_identity_id uuid,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_line record;
begin
 if p_invoice_number is null or p_actor_identity_id is null or p_subtotal<0 or p_shipping<0 or p_tax<0 or p_total<>p_subtotal+p_shipping+p_tax or jsonb_typeof(p_lines)<>'array' then raise exception 'Invalid invoice' using errcode='22023'; end if;
 if not exists(select 1 from public.mme_purchase_orders where id=p_po_id and status in ('issued','acknowledged','partially_received','received')) then raise exception 'PO unavailable' using errcode='P0001'; end if;
 insert into public.mme_supplier_invoices(purchase_order_id,invoice_number,subtotal_cents,shipping_cents,tax_cents,total_cents,recorded_by_identity_id)
 values(p_po_id,btrim(p_invoice_number),p_subtotal,p_shipping,p_tax,p_total,p_actor_identity_id) returning id into v_id;
 for v_line in select x.line_id,x.quantity,x.unit_cost from jsonb_to_recordset(p_lines) x(line_id uuid,quantity integer,unit_cost bigint) join public.mme_purchase_order_lines l on l.id=x.line_id where l.purchase_order_id=p_po_id and x.quantity>0 and x.unit_cost>=0 and x.quantity<=l.received_quantity
 loop
  insert into public.mme_supplier_invoice_lines(invoice_id,purchase_order_line_id,invoiced_quantity,invoiced_unit_cost_cents)
  values(v_id,v_line.line_id,v_line.quantity,v_line.unit_cost);
 end loop;
 if (select count(*) from public.mme_supplier_invoice_lines where invoice_id=v_id)<>jsonb_array_length(p_lines) then raise exception 'Invalid invoice line or quantity exceeds received units' using errcode='23514'; end if;
 return v_id;
end; $$;

create or replace function public.mme_match_supplier_invoice(p_invoice_id uuid,p_actor_identity_id uuid,p_unit_tolerance bigint default 0,p_total_tolerance bigint default 0)
returns text language plpgsql security definer set search_path=''
as $$
declare v_inv record; v_line record; v_sum numeric:=0; v_bad boolean:=false;
begin
 if p_actor_identity_id is null or p_unit_tolerance<0 or p_total_tolerance<0 then raise exception 'Invalid invoice match' using errcode='22023'; end if;
 select * into v_inv from public.mme_supplier_invoices where id=p_invoice_id for update;
 if not found or v_inv.match_status<>'pending' then return 'not_matchable'; end if;
 for v_line in select il.invoiced_quantity,il.invoiced_unit_cost_cents,pl.unit_cost_cents,pl.received_quantity
  from public.mme_supplier_invoice_lines il join public.mme_purchase_order_lines pl on pl.id=il.purchase_order_line_id where il.invoice_id=p_invoice_id
 loop
  v_sum:=v_sum+v_line.invoiced_quantity::numeric*v_line.invoiced_unit_cost_cents;
  if v_line.invoiced_quantity>v_line.received_quantity or abs(v_line.invoiced_unit_cost_cents-v_line.unit_cost_cents)>p_unit_tolerance then v_bad:=true; end if;
 end loop;
 if abs(v_sum-v_inv.subtotal_cents)>p_total_tolerance then v_bad:=true; end if;
 update public.mme_supplier_invoices set match_status=case when v_bad then 'variance' else 'matched' end,matched_by_identity_id=p_actor_identity_id,matched_at=now() where id=p_invoice_id;
 insert into public.mme_purchase_order_events(purchase_order_id,event_type,event_data,actor_identity_id)
 values(v_inv.purchase_order_id,'invoice_match',jsonb_build_object('invoice_id',p_invoice_id,'status',case when v_bad then 'variance' else 'matched' end),p_actor_identity_id);
 return case when v_bad then 'variance' else 'matched' end;
end; $$;

revoke all on function public.mme_create_purchase_order(text,uuid,uuid,bigint,bigint,uuid) from public,anon,authenticated;
revoke all on function public.mme_set_purchase_order_status(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_receive_purchase_order_lines(uuid,text,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.mme_record_supplier_invoice(uuid,text,bigint,bigint,bigint,bigint,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.mme_match_supplier_invoice(uuid,uuid,bigint,bigint) from public,anon,authenticated;
grant execute on function public.mme_create_purchase_order(text,uuid,uuid,bigint,bigint,uuid) to service_role;
grant execute on function public.mme_set_purchase_order_status(uuid,text,uuid,text) to service_role;
grant execute on function public.mme_receive_purchase_order_lines(uuid,text,uuid,uuid,jsonb) to service_role;
grant execute on function public.mme_record_supplier_invoice(uuid,text,bigint,bigint,bigint,bigint,uuid,jsonb) to service_role;
grant execute on function public.mme_match_supplier_invoice(uuid,uuid,bigint,bigint) to service_role;
