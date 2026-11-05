-- Build 009.37 — Native MME POS financial source adapter.
-- Exports only finalized POS transactions with a complete trusted captured-tender ledger.
begin;
create extension if not exists pgcrypto;

alter table public.mme_store_locations
 add column if not exists business_timezone text not null default 'America/New_York';
create or replace function public.mme_validate_store_business_timezone()
returns trigger language plpgsql set search_path=pg_catalog,public
as $
begin
 if not exists(select 1 from pg_timezone_names where name=new.business_timezone) then
  raise exception 'Store business timezone must be a valid IANA timezone' using errcode='22023';
 end if;
 return new;
end;
$;
drop trigger if exists mme_store_business_timezone_validate on public.mme_store_locations;
create trigger mme_store_business_timezone_validate before insert or update of business_timezone
 on public.mme_store_locations for each row execute function public.mme_validate_store_business_timezone();

alter table public.mme_pos_transactions
 add column if not exists location_id uuid references public.mme_store_locations(id) on delete restrict,
 add column if not exists register_reference text,
 add column if not exists source_channel text not null default 'in_store_pos'
  check(source_channel in ('in_store_pos','assisted_pos'));

update public.mme_pos_transactions t
 set location_id=src.location_id
 from (
  select r.order_id,(array_agg(distinct rl.location_id))[1] as location_id
  from public.mme_inventory_reservations r
  join public.mme_inventory_reservation_lines rl on rl.reservation_id=r.id
  group by r.order_id having count(distinct rl.location_id)=1
 ) src
 where t.order_id=src.order_id and t.location_id is null;

create index if not exists mme_pos_transactions_native_finance_idx
 on public.mme_pos_transactions(status,finalized_at,location_id);

create or replace function public.mme_pos_set_transaction_location()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_location_count integer; v_location_id uuid;
begin
 select count(distinct rl.location_id),(array_agg(distinct rl.location_id))[1] into v_location_count,v_location_id
 from public.mme_inventory_reservations r
 join public.mme_inventory_reservation_lines rl on rl.reservation_id=r.id
 where r.order_id=new.order_id and r.status='active' and r.expires_at>now();
 if v_location_count<>1 then
  raise exception 'A POS transaction requires one active store reservation' using errcode='23514';
 end if;
 new.location_id:=v_location_id;
 return new;
end;
$$;
drop trigger if exists mme_pos_transaction_location_before_insert on public.mme_pos_transactions;
create trigger mme_pos_transaction_location_before_insert
 before insert on public.mme_pos_transactions
 for each row execute function public.mme_pos_set_transaction_location();

create or replace function public.mme_pos_set_transaction_register(
 p_transaction_id uuid,p_actor_person_id uuid,p_register_reference text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_tx public.mme_pos_transactions%rowtype;
begin
 if p_transaction_id is null or p_actor_person_id is null
  or p_register_reference is null or length(btrim(p_register_reference))<2
  or length(p_register_reference)>120
  or p_register_reference !~ '^[A-Za-z0-9][A-Za-z0-9._-]{1,119}$' then
  raise exception 'Invalid POS register reference' using errcode='22023';
 end if;
 select * into v_tx from public.mme_pos_transactions where id=p_transaction_id for update;
 if not found then raise exception 'POS transaction not found' using errcode='P0002'; end if;
 if not public.mme_person_authorize_pos_action(p_actor_person_id,'pos.transaction.create',v_tx.order_id) then
  raise exception 'POS transaction register assignment permission denied' using errcode='42501';
 end if;
 if v_tx.status<>'inventory_reserved' then
  raise exception 'Register attribution must be set before pricing or tendering' using errcode='55000';
 end if;
 if v_tx.register_reference is not null and v_tx.register_reference<>p_register_reference then
  raise exception 'POS register reference is already bound' using errcode='23505';
 end if;
 update public.mme_pos_transactions set register_reference=p_register_reference,updated_at=now()
 where id=p_transaction_id and register_reference is null;
 return true;
end;
$$;

-- Provider payment movements are evidence, not revenue. This prevents Stripe
-- charges/refunds from being counted again alongside the native POS sale/refund facts.
alter table public.mme_pos_financial_reporting_facts
 drop constraint if exists mme_pos_financial_reporting_facts_fact_type_check;
alter table public.mme_pos_financial_reporting_facts
 add constraint mme_pos_financial_reporting_facts_fact_type_check
 check(fact_type in ('gross_sale','discount','refund','subscription_revenue','sales_tax',
  'cost_of_goods_sold','processor_fee','chargeback','chargeback_reversal','cash_over_short','inventory_adjustment',
  'payment_capture','payment_refund'));
alter table public.mme_pos_financial_reporting_facts
 drop constraint if exists mme_pos_financial_reporting_facts_check;
alter table public.mme_pos_financial_reporting_facts
 add constraint mme_pos_financial_reporting_facts_amount_sign_check
 check((fact_type in ('gross_sale','subscription_revenue','sales_tax','payment_capture') and amount_minor>=0)
  or (fact_type in ('discount','refund','cost_of_goods_sold','processor_fee','chargeback','payment_refund') and amount_minor<=0)
  or (fact_type='chargeback_reversal' and amount_minor>=0)
  or fact_type in ('cash_over_short','inventory_adjustment'));

-- Keep closed-period idempotency safe: an exact already-imported fact may be replayed,
-- but a new fact cannot be inserted into a closed period.
create or replace function public.mme_pos_import_financial_fact(
 p_location_id uuid,p_actor_person_id uuid,p_source_system text,p_source_line_reference text,
 p_fact_type text,p_business_date date,p_occurred_at timestamptz,p_business_timezone text,
 p_currency text,p_amount_minor bigint,p_quantity_milli bigint default null,
 p_product_category text default null,p_sku_reference text default null,p_register_reference text default null,
 p_employee_person_id uuid default null,p_source_transaction_reference text default null,p_source_digest_sha256 text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_existing_fact public.mme_pos_financial_reporting_facts%rowtype;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',p_location_id) then
  raise exception 'Financial fact import permission denied' using errcode='42501';
 end if;
 if p_source_line_reference is null or p_business_date is null or p_occurred_at is null
  or p_business_timezone is null or not exists(select 1 from pg_timezone_names where name=p_business_timezone)
  or p_currency !~ '^[A-Z]{3}$' or (p_occurred_at at time zone p_business_timezone)::date<>p_business_date
  or p_amount_minor is null then
  raise exception 'Invalid financial fact source, currency, timezone or date' using errcode='22023';
 end if;
 select * into v_existing_fact from public.mme_pos_financial_reporting_facts
 where location_id=p_location_id and source_system=p_source_system
  and source_line_reference=p_source_line_reference and fact_type=p_fact_type;
 if found then
  if v_existing_fact.business_date<>p_business_date or v_existing_fact.currency<>p_currency
   or v_existing_fact.amount_minor<>p_amount_minor or v_existing_fact.occurred_at<>p_occurred_at
   or v_existing_fact.quantity_milli is distinct from p_quantity_milli
   or v_existing_fact.product_category is distinct from p_product_category
   or v_existing_fact.sku_reference is distinct from p_sku_reference
   or v_existing_fact.register_reference is distinct from p_register_reference
   or v_existing_fact.employee_person_id is distinct from p_employee_person_id
   or v_existing_fact.source_transaction_reference is distinct from p_source_transaction_reference
   or v_existing_fact.source_digest_sha256 is distinct from p_source_digest_sha256 then
   raise exception 'Source reference already exists with conflicting financial content; quarantine for review' using errcode='23505';
  end if;
  return v_existing_fact.id;
 end if;
 if exists(select 1 from public.mme_pos_financial_closes c where c.location_id=p_location_id
  and c.currency=p_currency and p_occurred_at>=c.business_period_start and p_occurred_at<c.business_period_end
  and c.status='closed') then
  raise exception 'Financial facts cannot be added to a closed period; use the authorized reopen and adjustment workflow' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_reporting_facts(location_id,source_system,source_line_reference,fact_type,
  business_date,occurred_at,business_timezone,currency,amount_minor,quantity_milli,product_category,sku_reference,
  register_reference,employee_person_id,source_transaction_reference,source_digest_sha256,imported_by_person_id)
 values(p_location_id,p_source_system,p_source_line_reference,p_fact_type,p_business_date,p_occurred_at,
  p_business_timezone,p_currency,p_amount_minor,p_quantity_milli,p_product_category,p_sku_reference,
  p_register_reference,p_employee_person_id,p_source_transaction_reference,p_source_digest_sha256,p_actor_person_id)
 returning id into v_id;
 return v_id;
end;
$$;

-- Extend normalized import allowlist with payment movements that must never be
-- aggregated as sales. Replaces the existing function without changing its contract.
create or replace function public.mme_pos_stage_financial_import_batch(
 p_connector_id uuid,p_actor_person_id uuid,p_source_batch_reference text,p_idempotency_key text,
 p_records jsonb,p_source_digest_sha256 text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch uuid; v_existing uuid;
 v_record jsonb; v_row integer:=0; v_line text; v_type text; v_digest text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Financial import permission denied' using errcode='42501';
 end if;
 if v_connector.status<>'active' then raise exception 'Financial connector is not active' using errcode='55000'; end if;
 if jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)<1 or jsonb_array_length(p_records)>250
  or length(btrim(coalesce(p_source_batch_reference,'')))<1 or length(btrim(coalesce(p_idempotency_key,'')))<8 then
  raise exception 'Import batch must contain 1 to 250 normalized records and valid source identifiers' using errcode='22023';
 end if;
 select id into v_existing from public.mme_pos_financial_import_batches
 where connector_id=p_connector_id and idempotency_key=p_idempotency_key;
 if v_existing is not null then return v_existing; end if;
 insert into public.mme_pos_financial_import_batches(connector_id,location_id,source_system,source_batch_reference,
  idempotency_key,record_count,staged_by_person_id,source_digest_sha256)
 values(p_connector_id,v_connector.location_id,v_connector.source_system,p_source_batch_reference,
  p_idempotency_key,jsonb_array_length(p_records),p_actor_person_id,p_source_digest_sha256)
 returning id into v_batch;
 for v_record in select value from jsonb_array_elements(p_records) loop
  v_row:=v_row+1;
  if jsonb_typeof(v_record)<>'object' or (v_record - array[
   'source_line_reference','fact_type','business_date','occurred_at','business_timezone','currency',
   'amount_minor','quantity_milli','product_category','sku_reference','register_reference',
   'employee_person_id','source_transaction_reference','source_digest_sha256'
  ])<>'{}'::jsonb then
   raise exception 'Import row % has an invalid shape or unsupported fields',v_row using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key)
   where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold',
    'processor_fee','chargeback','chargeback_reversal','cash_over_short','inventory_adjustment','payment_capture','payment_refund') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=md5(v_record::text);
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_fingerprint_md5)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create table public.mme_pos_financial_pos_exports (
 id uuid primary key default gen_random_uuid(),
 transaction_id uuid not null unique references public.mme_pos_transactions(id) on delete restrict,
 location_id uuid references public.mme_store_locations(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','processing','exported','failed','blocked')),
 attempt_count integer not null default 0 check(attempt_count>=0),
 lease_token uuid,
 lease_expires_at timestamptz,
 next_attempt_at timestamptz not null default now(),
 last_exported_at timestamptz,
 facts_processed integer not null default 0 check(facts_processed>=0),
 safe_error_code text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_pos_financial_pos_exports_queue_idx
 on public.mme_pos_financial_pos_exports(status,next_attempt_at,lease_expires_at);
create index mme_pos_financial_pos_exports_location_idx
 on public.mme_pos_financial_pos_exports(location_id,last_exported_at desc);
create table public.mme_pos_financial_pos_export_events (
 id uuid primary key default gen_random_uuid(),
 export_id uuid not null references public.mme_pos_financial_pos_exports(id) on delete restrict,
 transaction_id uuid not null references public.mme_pos_transactions(id) on delete restrict,
 location_id uuid,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('claimed','exported','failed','blocked')),
 safe_error_code text,
 facts_processed integer not null default 0 check(facts_processed>=0),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_pos_export_events_idx
 on public.mme_pos_financial_pos_export_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_pos_exports enable row level security;
alter table public.mme_pos_financial_pos_export_events enable row level security;
revoke all on public.mme_pos_financial_pos_exports,public.mme_pos_financial_pos_export_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_pos_exports to service_role;
grant select,insert on public.mme_pos_financial_pos_export_events to service_role;
revoke delete,truncate on public.mme_pos_financial_pos_exports,public.mme_pos_financial_pos_export_events from service_role;

create or replace function public.mme_pos_claim_native_financial_exports(
 p_worker_person_id uuid,p_limit integer default 25,p_lease_seconds integer default 120
) returns table(transaction_id uuid,location_id uuid,business_timezone text,lease_token uuid)
language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_worker_person_id is null or p_limit<1 or p_limit>100 or p_lease_seconds<30 or p_lease_seconds>600 then
  raise exception 'Invalid native POS financial export claim request' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_pos_exports(transaction_id,location_id,status,safe_error_code)
 select t.id,t.location_id,case when t.location_id is null then 'blocked' else 'pending' end,
  case when t.location_id is null then 'STORE_ATTRIBUTION_MISSING' else null end
 from public.mme_pos_transactions t where t.status='finalized'
 on conflict(transaction_id) do nothing;
 return query
 with candidates as (
  select e.id from public.mme_pos_financial_pos_exports e
  join public.mme_pos_transactions t on t.id=e.transaction_id
  where t.status='finalized' and e.location_id is not null
   and ((e.status in ('pending','failed','exported') and e.next_attempt_at<=now())
    or (e.status='processing' and e.lease_expires_at<now()))
   and public.mme_pos_authorize_hardware_action(p_worker_person_id,'pos.finance.report.import',e.location_id)
  order by t.finalized_at,e.created_at
  for update of e skip locked limit p_limit
 ), claimed as (
  update public.mme_pos_financial_pos_exports e set status='processing',attempt_count=e.attempt_count+1,
   lease_token=gen_random_uuid(),lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
   updated_at=now()
  from candidates c where e.id=c.id
  returning e.*
 )
 select c.transaction_id,c.location_id,l.business_timezone,c.lease_token from claimed c
 join public.mme_store_locations l on l.id=c.location_id;
end;
$$;

create or replace function public.mme_pos_export_finalized_transaction_financial_facts(
 p_transaction_id uuid,p_lease_token uuid,p_worker_person_id uuid,p_business_timezone text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
 v_export public.mme_pos_financial_pos_exports%rowtype;
 v_tx public.mme_pos_transactions%rowtype;
 v_order public.mme_orders%rowtype;
 v_line record; v_refund record;
 v_line_count integer; v_distinct_locations integer; v_line_total bigint;
 v_captured_total bigint; v_bad_tenders integer; v_refund_count integer;
 v_digest text; v_reference text; v_fact_count integer:=0; v_safe_code text:='NATIVE_POS_EXPORT_FAILED';
 v_sqlstate text;
begin
 select * into v_export from public.mme_pos_financial_pos_exports
 where transaction_id=p_transaction_id for update;
 if not found or v_export.status<>'processing' or v_export.lease_token is distinct from p_lease_token
  or v_export.lease_expires_at is null or v_export.lease_expires_at<now() then
  raise exception 'Native POS financial export lease is invalid' using errcode='40001';
 end if;
 if not public.mme_pos_authorize_hardware_action(p_worker_person_id,'pos.finance.report.import',v_export.location_id) then
  raise exception 'Native POS financial export permission denied' using errcode='42501';
 end if;
 select * into v_tx from public.mme_pos_transactions where id=p_transaction_id for update;
 if not found or v_tx.status<>'finalized' or v_tx.finalized_at is null then
  raise exception 'Only finalized POS transactions can be exported' using errcode='55000';
 end if;
 if v_tx.location_id is null or v_tx.location_id<>v_export.location_id then
  raise exception 'POS transaction store attribution is missing or inconsistent' using errcode='23514';
 end if;
 if not exists(select 1 from pg_timezone_names where name=p_business_timezone) then
  raise exception 'Invalid store business timezone' using errcode='22023';
 end if;
 select * into v_order from public.mme_orders where id=v_tx.order_id;
 if not found or v_order.currency<>v_tx.currency or v_order.total_cents<>v_tx.total_cents then
  raise exception 'POS order and transaction totals do not match' using errcode='23514';
 end if;
 select count(*),count(distinct location_id),coalesce(sum(line_total_cents),0)
 into v_line_count,v_distinct_locations,v_line_total
 from public.mme_order_lines where order_id=v_order.id;
 if v_line_count<1 or v_distinct_locations<>1 or v_line_total<>v_order.subtotal_cents
  or exists(select 1 from public.mme_order_lines where order_id=v_order.id and location_id<>v_tx.location_id) then
  raise exception 'POS order lines are incomplete or cross-store' using errcode='23514';
 end if;
 select coalesce(sum(captured_amount_minor),0),
  count(*) filter(where status not in ('captured','partially_refunded','refunded'))
 into v_captured_total,v_bad_tenders
 from public.mme_pos_tender_attempts where transaction_id=p_transaction_id;
 if v_captured_total<>v_order.total_cents or v_bad_tenders<>0
  or not exists(select 1 from public.mme_pos_tender_attempts where transaction_id=p_transaction_id) then
  raise exception 'POS transaction does not have a fully captured and resolved tender ledger' using errcode='23514';
 end if;

 for v_line in
  select l.id,l.sku_snapshot,l.quantity,l.unit_price_cents,l.line_total_cents,l.condition_snapshot,
   coalesce(p.category_key,'uncategorized') as product_category
  from public.mme_order_lines l join public.mme_products p on p.id=l.product_id
  where l.order_id=v_order.id order by l.id
 loop
  v_reference:='pos:'||p_transaction_id::text||':line:'||v_line.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'line_id',v_line.id,
   'sku',v_line.sku_snapshot,'quantity',v_line.quantity,'unit_price_cents',v_line.unit_price_cents,
   'line_total_cents',v_line.line_total_cents,'condition',v_line.condition_snapshot,
   'product_category',v_line.product_category,'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'gross_sale',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,v_line.line_total_cents,v_line.quantity::bigint*1000,
   left(v_line.product_category,120),left(v_line.sku_snapshot,160),v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end loop;

 if v_order.fulfillment_cents>0 then
  v_reference:='pos:'||p_transaction_id::text||':fulfillment';
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'fulfillment_cents',v_order.fulfillment_cents,
   'fulfillment_method',v_order.fulfillment_method,'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'gross_sale',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,v_order.fulfillment_cents,null,'fulfillment',null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end if;
 if v_order.discount_cents>0 then
  v_reference:='pos:'||p_transaction_id::text||':discount';
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'discount_cents',v_order.discount_cents,
   'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'discount',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,-v_order.discount_cents,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end if;
 if v_order.tax_cents>0 then
  v_reference:='pos:'||p_transaction_id::text||':tax';
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'tax_cents',v_order.tax_cents,
   'finalized_at',v_tx.finalized_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'sales_tax',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_order.currency,v_order.tax_cents,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end if;

 for v_line in
  select id,method,operation,captured_amount_minor,currency,provider_operation_reference,provider_payment_reference,updated_at
  from public.mme_pos_tender_attempts where transaction_id=p_transaction_id
   and captured_amount_minor>0 and status in ('captured','partially_refunded','refunded')
  order by id
 loop
  v_reference:='pos:'||p_transaction_id::text||':tender-capture:'||v_line.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'tender_id',v_line.id,
   'method',v_line.method,'operation',v_line.operation,'captured_amount_minor',v_line.captured_amount_minor,
   'currency',v_line.currency,'provider_operation_reference',v_line.provider_operation_reference,
   'provider_payment_reference',v_line.provider_payment_reference)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'payment_capture',(v_tx.finalized_at at time zone p_business_timezone)::date,v_tx.finalized_at,p_business_timezone,
   v_line.currency,v_line.captured_amount_minor,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end loop;

 for v_refund in
  select id,amount_minor,currency,updated_at from public.mme_pos_refund_requests
  where transaction_id=p_transaction_id and request_type='refund' and status='completed'
  order by updated_at,id
 loop
  v_reference:='pos:'||p_transaction_id::text||':refund:'||v_refund.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'refund_id',v_refund.id,
   'amount_minor',v_refund.amount_minor,'currency',v_refund.currency,'completed_at',v_refund.updated_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'refund',(v_refund.updated_at at time zone p_business_timezone)::date,v_refund.updated_at,p_business_timezone,
   v_refund.currency,-v_refund.amount_minor,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
  v_reference:='pos:'||p_transaction_id::text||':payment-refund:'||v_refund.id::text;
  v_digest:=encode(digest(jsonb_build_object('transaction_id',p_transaction_id,'refund_id',v_refund.id,
   'payment_amount_minor',v_refund.amount_minor,'currency',v_refund.currency,'completed_at',v_refund.updated_at)::text,'sha256'),'hex');
  perform public.mme_pos_import_financial_fact(v_tx.location_id,p_worker_person_id,'pos',v_reference,
   'payment_refund',(v_refund.updated_at at time zone p_business_timezone)::date,v_refund.updated_at,p_business_timezone,
   v_refund.currency,-v_refund.amount_minor,null,null,null,v_tx.register_reference,
   v_tx.created_by_person_id,p_transaction_id::text,v_digest);
  v_fact_count:=v_fact_count+1;
 end loop;

 update public.mme_pos_financial_pos_exports set status='exported',lease_token=null,lease_expires_at=null,
  next_attempt_at=now()+interval '15 minutes',last_exported_at=now(),facts_processed=v_fact_count,
  safe_error_code=null,updated_at=now() where id=v_export.id;
 insert into public.mme_pos_financial_pos_export_events(export_id,transaction_id,location_id,actor_person_id,event_type,facts_processed)
 values(v_export.id,p_transaction_id,v_tx.location_id,p_worker_person_id,'exported',v_fact_count);
 return true;
exception when others then
 get stacked diagnostics v_sqlstate=returned_sqlstate;
 v_safe_code:=case when v_sqlstate='55000' then 'CLOSED_PERIOD_OR_STATE_BLOCK'
  when v_sqlstate='42501' then 'WORKER_PERMISSION_DENIED'
  when v_sqlstate in ('23514','22023') then 'SOURCE_VALIDATION_FAILED'
  else 'NATIVE_POS_EXPORT_FAILED' end;
 update public.mme_pos_financial_pos_exports set status='failed',lease_token=null,lease_expires_at=null,
  next_attempt_at=now()+interval '5 minutes',safe_error_code=v_safe_code,updated_at=now()
 where transaction_id=p_transaction_id;
 insert into public.mme_pos_financial_pos_export_events(export_id,transaction_id,location_id,actor_person_id,event_type,safe_error_code)
 select id,p_transaction_id,location_id,p_worker_person_id,'failed',v_safe_code
 from public.mme_pos_financial_pos_exports where transaction_id=p_transaction_id;
 return false;
end;
$$;

revoke all on function public.mme_pos_set_transaction_register(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_claim_native_financial_exports(uuid,integer,integer) from public,anon,authenticated;
revoke all on function public.mme_pos_export_finalized_transaction_financial_facts(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_transaction_register(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_claim_native_financial_exports(uuid,integer,integer) to service_role;
grant execute on function public.mme_pos_export_finalized_transaction_financial_facts(uuid,uuid,uuid,text) to service_role;

comment on table public.mme_pos_financial_pos_exports is
 'Leased, idempotent export state for finalized native MME POS transactions. Re-scans completed transactions for later completed refunds.';
comment on table public.mme_pos_financial_pos_export_events is
 'Append-only audit history for native POS financial export claims, results and failures.';
comment on column public.mme_pos_financial_reporting_facts.fact_type is
 'Payment capture/refund facts are provider movement evidence only and are excluded from sales revenue aggregates.';

commit;
