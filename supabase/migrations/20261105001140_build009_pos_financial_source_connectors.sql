-- Build 009.34 — POS Financial Data Source Connector & Import Orchestration
-- Additive connector registry, normalized staging, idempotent imports and quarantine.
begin;

create or replace function public.mme_pos_authorize_hardware_action(
 p_actor_person_id uuid,p_permission_key text,p_location_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_person_status text; v_ceo_person_id uuid; v_frozen boolean; v_employment_status text;
begin
 if p_actor_person_id is null or p_location_id is null or p_permission_key not in (
  'pos.hardware.register','pos.hardware.command','pos.hardware.incident.view',
  'pos.hardware.incident.acknowledge','pos.hardware.incident.resolve','pos.hardware.admin',
  'pos.hardware.assign','pos.hardware.configure','pos.hardware.approve','pos.hardware.retire',
  'pos.network.view','pos.network.manage','pos.network.certificates','pos.network.incidents',
  'pos.security.view','pos.security.manage','pos.security.investigate','pos.security.contain','pos.security.rules.manage',
  'pos.fraud.view','pos.fraud.review','pos.fraud.rules.manage','pos.fraud.case.manage','pos.fraud.override',
  'pos.disputes.view','pos.disputes.manage','pos.disputes.evidence','pos.disputes.approve','pos.disputes.submit',
  'pos.settlement.view','pos.settlement.reconcile','pos.settlement.exception.manage','pos.settlement.approve',
  'pos.settlement.bank.match','pos.settlement.cash.manage','pos.settlement.close.prepare','pos.settlement.close.approve',
  'pos.settlement.adjustment.request','pos.finance.report.view','pos.finance.report.build','pos.finance.report.import',
  'pos.finance.connector.view','pos.finance.connector.manage'
 ) then return false; end if;
 select lifecycle_status into v_person_status from public.mme_person_identities where person_id=p_actor_person_id;
 if not found or v_person_status is distinct from 'active' then return false; end if;
 select ceo_person_id,employee_access_frozen into v_ceo_person_id,v_frozen from public.employee_security_settings where singleton=true;
 if not found or v_frozen is distinct from false or v_ceo_person_id is null then return false; end if;
 select employment_status into v_employment_status from public.employee_relationships where person_id=p_actor_person_id;
 if v_employment_status is distinct from 'active' then return false; end if;
 if p_actor_person_id=v_ceo_person_id then return true; end if;
 return exists(select 1 from public.employee_permission_grants g where g.person_id=p_actor_person_id
  and g.permission_key=p_permission_key and g.revoked_at is null and (g.expires_at is null or g.expires_at>now())
  and (g.scope='{}'::jsonb or g.scope->>'location_id'=p_location_id::text));
end;
$$;

create table public.mme_pos_financial_connectors (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 provider_key text not null check(provider_key in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')),
 source_system text not null check(source_system in ('pos','payments','inventory','subscriptions','manual_import')),
 display_name text not null check(length(btrim(display_name)) between 2 and 120),
 status text not null default 'pending_configuration' check(status in ('pending_configuration','active','paused','revoked','error')),
 external_account_reference text check(external_account_reference is null or length(external_account_reference)<=200),
 credential_reference text check(credential_reference is null or (length(credential_reference)<=240 and credential_reference !~* '(sk_live_|sk_test_|secret=|password=|bearer )')),
 adapter_version text not null default 'normalized-v1',
 last_success_at timestamptz,
 last_attempt_at timestamptz,
 last_error_code text,
 created_by_person_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(location_id,provider_key,external_account_reference)
);
create index mme_pos_financial_connectors_location_idx on public.mme_pos_financial_connectors(location_id,status,provider_key);

create table public.mme_pos_financial_import_batches (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 source_system text not null check(source_system in ('pos','payments','inventory','subscriptions','manual_import')),
 source_batch_reference text not null check(length(btrim(source_batch_reference)) between 1 and 200),
 idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 200),
 status text not null default 'staged' check(status in ('staged','processing','completed','completed_with_quarantine','failed','cancelled')),
 record_count integer not null check(record_count between 1 and 250),
 imported_count integer not null default 0 check(imported_count>=0),
 duplicate_count integer not null default 0 check(duplicate_count>=0),
 quarantined_count integer not null default 0 check(quarantined_count>=0),
 staged_by_person_id uuid not null,
 staged_at timestamptz not null default now(),
 started_at timestamptz,
 completed_at timestamptz,
 source_digest_sha256 text check(source_digest_sha256 is null or source_digest_sha256 ~ '^[a-f0-9]{64}$'),
 unique(connector_id,idempotency_key),
 unique(connector_id,source_batch_reference)
);
create index mme_pos_financial_import_batches_queue_idx on public.mme_pos_financial_import_batches(status,staged_at);

create table public.mme_pos_financial_import_rows (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 row_number integer not null check(row_number>0),
 source_line_reference text not null,
 fact_type text not null,
 normalized_record jsonb not null check(jsonb_typeof(normalized_record)='object'),
 row_fingerprint_md5 text not null check(row_fingerprint_md5 ~ '^[a-f0-9]{32} text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type is null or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
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

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
),
 status text not null default 'staged' check(status in ('staged','imported','duplicate','quarantined')),
 financial_fact_id uuid references public.mme_pos_financial_reporting_facts(id) on delete restrict,
 error_code text,
 processed_at timestamptz,
 unique(batch_id,row_number),
 unique(batch_id,source_line_reference,fact_type)
);
create index mme_pos_financial_import_rows_queue_idx on public.mme_pos_financial_import_rows(batch_id,status,row_number);

create table public.mme_pos_financial_import_quarantine (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 import_row_id uuid not null references public.mme_pos_financial_import_rows(id) on delete restrict,
 location_id uuid not null,
 error_code text not null,
 safe_message text not null check(length(safe_message)<=500),
 resolution_status text not null default 'open' check(resolution_status in ('open','reviewed','replayed','dismissed')),
 reviewed_by_person_id uuid,
 reviewed_at timestamptz,
 resolution_reason text,
 created_at timestamptz not null default now(),
 unique(import_row_id)
);
create index mme_pos_financial_import_quarantine_queue_idx on public.mme_pos_financial_import_quarantine(location_id,resolution_status,created_at);

create table public.mme_pos_financial_import_cursors (
 connector_id uuid primary key references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 cursor_value text,
 cursor_updated_at timestamptz,
 last_batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table public.mme_pos_financial_connector_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid not null,
 event_type text not null check(event_type in ('connector_registered','connector_activated','connector_paused','connector_revoked','batch_staged','batch_processing_started','batch_completed','batch_failed','cursor_advanced','quarantine_created')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_connector_events_idx on public.mme_pos_financial_connector_events(location_id,occurred_at desc);

alter table public.mme_pos_financial_connectors enable row level security;
alter table public.mme_pos_financial_import_batches enable row level security;
alter table public.mme_pos_financial_import_rows enable row level security;
alter table public.mme_pos_financial_import_quarantine enable row level security;
alter table public.mme_pos_financial_import_cursors enable row level security;
alter table public.mme_pos_financial_connector_events enable row level security;
revoke all on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_connectors to service_role;
grant select,insert,update on public.mme_pos_financial_import_batches,public.mme_pos_financial_import_cursors to service_role;
grant select,insert,update on public.mme_pos_financial_import_rows to service_role;
grant select,insert,update on public.mme_pos_financial_import_quarantine to service_role;
grant select,insert on public.mme_pos_financial_connector_events to service_role;
revoke delete,truncate on public.mme_pos_financial_connectors,public.mme_pos_financial_import_batches,
 public.mme_pos_financial_import_rows,public.mme_pos_financial_import_quarantine,
 public.mme_pos_financial_import_cursors,public.mme_pos_financial_connector_events from service_role;

create or replace function public.mme_pos_register_financial_connector(
 p_location_id uuid,p_actor_person_id uuid,p_provider_key text,p_display_name text,
 p_external_account_reference text default null,p_credential_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_source text; v_id uuid;
begin
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',p_location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 v_source:=case when p_provider_key='stripe' then 'payments'
  when p_provider_key='inventory' then 'inventory' when p_provider_key='subscriptions' then 'subscriptions'
  when p_provider_key='pos' then 'pos' else 'manual_import' end;
 if p_provider_key not in ('pos','stripe','inventory','subscriptions','bank_feed','manual_import')
  or length(btrim(coalesce(p_display_name,'')))<2
  or coalesce(p_credential_reference,'') ~* '(sk_live_|sk_test_|secret=|password=|bearer )' then
  raise exception 'Invalid connector metadata; credentials must remain in an external secret vault' using errcode='22023';
 end if;
 insert into public.mme_pos_financial_connectors(location_id,provider_key,source_system,display_name,
  external_account_reference,credential_reference,created_by_person_id)
 values(p_location_id,p_provider_key,v_source,p_display_name,p_external_account_reference,p_credential_reference,p_actor_person_id)
 returning id into v_id;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(v_id,p_location_id,p_actor_person_id,'connector_registered','Connector metadata registered; provider credentials are managed externally.');
 return v_id;
end;
$$;

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
  if exists(select 1 from jsonb_object_keys(v_record) as keys(key) where key ~* '(card_number|pan|cvv|cvc|pin|track_data|magstripe|password|access_token|refresh_token|email|phone|address)') then
   raise exception 'Import row % contains prohibited sensitive fields',v_row using errcode='22023';
  end if;
  v_line:=v_record->>'source_line_reference'; v_type:=v_record->>'fact_type';
  if length(btrim(coalesce(v_line,'')))<1 or v_type not in
   ('gross_sale','discount','refund','subscription_revenue','sales_tax','cost_of_goods_sold','processor_fee','chargeback','cash_over_short','inventory_adjustment') then
   raise exception 'Import row % is missing a valid source reference or financial fact type',v_row using errcode='22023';
  end if;
  v_digest:=encode(digest(v_record::text,'sha256'),'hex');
  insert into public.mme_pos_financial_import_rows(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_digest_sha256)
  values(v_batch,v_row,v_line,v_type,v_record,v_digest);
 end loop;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(p_connector_id,v_batch,v_connector.location_id,p_actor_person_id,'batch_staged',
  'Normalized financial source batch staged for controlled processing.',jsonb_build_object('record_count',v_row));
 return v_batch;
end;
$$;

create or replace function public.mme_pos_process_financial_import_batch(
 p_batch_id uuid,p_actor_person_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_batch public.mme_pos_financial_import_batches%rowtype;
 v_connector public.mme_pos_financial_connectors%rowtype; v_row public.mme_pos_financial_import_rows%rowtype;
 v_data jsonb; v_fact uuid; v_imported integer:=0; v_duplicates integer:=0; v_quarantined integer:=0;
 v_error text; v_error_code text; v_started timestamptz:=clock_timestamp();
begin
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Financial import batch not found' using errcode='P0002'; end if;
 select * into v_connector from public.mme_pos_financial_connectors where id=v_batch.connector_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_batch.location_id) then
  raise exception 'Financial import processing permission denied' using errcode='42501';
 end if;
 if v_batch.status in ('completed','completed_with_quarantine') then
  return jsonb_build_object('batch_id',p_batch_id,'status',v_batch.status,'imported',v_batch.imported_count,
   'duplicates',v_batch.duplicate_count,'quarantined',v_batch.quarantined_count);
 end if;
 if v_batch.status not in ('staged','failed') or v_connector.status<>'active' then
  raise exception 'Batch or connector is not eligible for processing' using errcode='55000';
 end if;
 update public.mme_pos_financial_import_batches set status='processing',started_at=v_started where id=p_batch_id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,'batch_processing_started','Controlled financial import processing started.');
 for v_row in select * from public.mme_pos_financial_import_rows where batch_id=p_batch_id and status='staged' order by row_number for update loop
  v_data:=v_row.normalized_record;
  begin
   v_fact:=public.mme_pos_import_financial_fact(
    v_batch.location_id,p_actor_person_id,v_batch.source_system,
    v_data->>'source_line_reference',v_data->>'fact_type',(v_data->>'business_date')::date,
    (v_data->>'occurred_at')::timestamptz,v_data->>'business_timezone',v_data->>'currency',
    (v_data->>'amount_minor')::bigint,nullif(v_data->>'quantity_milli','')::bigint,
    v_data->>'product_category',v_data->>'sku_reference',v_data->>'register_reference',
    nullif(v_data->>'employee_person_id','')::uuid,v_data->>'source_transaction_reference',
    v_data->>'source_digest_sha256');
   if exists(select 1 from public.mme_pos_financial_reporting_facts f where f.id=v_fact
    and f.imported_at<v_started) then
    update public.mme_pos_financial_import_rows set status='duplicate',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_duplicates:=v_duplicates+1;
   else
    update public.mme_pos_financial_import_rows set status='imported',financial_fact_id=v_fact,processed_at=now() where id=v_row.id;
    v_imported:=v_imported+1;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text,v_error_code=returned_sqlstate;
   update public.mme_pos_financial_import_rows set status='quarantined',error_code=v_error_code,processed_at=now() where id=v_row.id;
   insert into public.mme_pos_financial_import_quarantine(batch_id,import_row_id,location_id,error_code,safe_message)
   values(p_batch_id,v_row.id,v_batch.location_id,v_error_code,left(v_error,500)) on conflict(import_row_id) do nothing;
   v_quarantined:=v_quarantined+1;
  end;
 end loop;
 update public.mme_pos_financial_import_batches set status=case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  imported_count=imported_count+v_imported,duplicate_count=duplicate_count+v_duplicates,
  quarantined_count=quarantined_count+v_quarantined,completed_at=now()
 where id=p_batch_id;
 update public.mme_pos_financial_connectors set last_attempt_at=v_started,
  last_success_at=case when v_quarantined=0 then now() else last_success_at end,
  last_error_code=case when v_quarantined>0 then 'ROWS_QUARANTINED' else null end,updated_at=now()
 where id=v_connector.id;
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason,metadata)
 values(v_connector.id,p_batch_id,v_batch.location_id,p_actor_person_id,
  case when v_quarantined>0 then 'batch_failed' else 'batch_completed' end,
  'Financial import batch processing completed with per-row outcomes.',
  jsonb_build_object('imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined));
 return jsonb_build_object('batch_id',p_batch_id,'status',case when v_quarantined>0 then 'completed_with_quarantine' else 'completed' end,
  'imported',v_imported,'duplicates',v_duplicates,'quarantined',v_quarantined);
end;
$$;

create or replace function public.mme_pos_advance_financial_import_cursor(
 p_connector_id uuid,p_actor_person_id uuid,p_cursor_value text,p_batch_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_batch public.mme_pos_financial_import_batches%rowtype;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Cursor advancement permission denied' using errcode='42501';
 end if;
 select * into v_batch from public.mme_pos_financial_import_batches where id=p_batch_id;
 if not found or v_batch.connector_id<>p_connector_id or v_batch.status not in ('completed','completed_with_quarantine') then
  raise exception 'Only a completed batch for this connector may advance the cursor' using errcode='55000';
 end if;
 insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,last_batch_id,updated_at)
 values(p_connector_id,v_connector.location_id,p_cursor_value,now(),p_batch_id,now())
 on conflict(connector_id) do update set cursor_value=excluded.cursor_value,cursor_updated_at=now(),
  last_batch_id=excluded.last_batch_id,updated_at=now();
 insert into public.mme_pos_financial_connector_events(connector_id,batch_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,p_batch_id,v_connector.location_id,p_actor_person_id,'cursor_advanced','Source cursor advanced after batch completion.');
 return true;
end;
$$;


create or replace function public.mme_pos_set_financial_connector_status(
 p_connector_id uuid,p_actor_person_id uuid,p_next_status text,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_connector public.mme_pos_financial_connectors%rowtype; v_event text;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.connector.manage',v_connector.location_id) then
  raise exception 'Financial connector management permission denied' using errcode='42501';
 end if;
 if p_next_status not in ('active','paused','revoked') or length(btrim(coalesce(p_reason,'')))<8
  or v_connector.status in ('revoked','error') then
  raise exception 'Valid connector status transition and reason required' using errcode='22023';
 end if;
 if p_next_status='active' and v_connector.credential_reference is null then
  raise exception 'Connector cannot be activated without an externally managed credential reference' using errcode='55000';
 end if;
 update public.mme_pos_financial_connectors set status=p_next_status,updated_at=now() where id=p_connector_id;
 v_event:=case when p_next_status='active' then 'connector_activated'
  when p_next_status='paused' then 'connector_paused' else 'connector_revoked' end;
 insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason)
 values(p_connector_id,v_connector.location_id,p_actor_person_id,v_event,p_reason);
 return true;
end;
$;

revoke all on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_set_financial_connector_status(uuid,uuid,text,text) to service_role;

revoke all on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_process_financial_import_batch(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_register_financial_connector(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.mme_pos_stage_financial_import_batch(uuid,uuid,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_process_financial_import_batch(uuid,uuid) to service_role;
grant execute on function public.mme_pos_advance_financial_import_cursor(uuid,uuid,text,uuid) to service_role;

comment on table public.mme_pos_financial_connectors is 'Store-scoped provider connector metadata; credentials are references to an external secret manager and are never stored here.';
comment on table public.mme_pos_financial_import_batches is 'Idempotent staged import batches from normalized source adapters.';
comment on table public.mme_pos_financial_import_rows is 'Allowlisted normalized financial facts staged for controlled ingestion; no raw provider payloads or cardholder data.';
comment on table public.mme_pos_financial_import_quarantine is 'Per-row rejected financial records with safe diagnostic codes and review state.';
comment on table public.mme_pos_financial_import_cursors is 'Source pagination checkpoints advanced only after a batch has a terminal completed status.';

commit;
