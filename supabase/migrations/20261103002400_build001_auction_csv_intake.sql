-- Build 001: CEO-controlled auction lot and CSV intake staging.
-- Parsing/OCR/retail research are performed by a trusted ingestion worker; this schema
-- stores source provenance, review decisions and validated line data. It does not
-- pretend to parse files or scrape retailers inside PostgreSQL.

create table public.mme_auction_import_batches (
 id uuid primary key default gen_random_uuid(),
 batch_reference text not null unique,
 auction_name text not null check(length(btrim(auction_name)) between 2 and 160),
 auction_lot_reference text,
 source_document_paths jsonb not null default '[]'::jsonb
  check(jsonb_typeof(source_document_paths)='array' and jsonb_array_length(source_document_paths)<=30),
 source_filename text,
 source_file_sha256 text,
 acquisition_cost_cents bigint not null check(acquisition_cost_cents>=0),
 freight_cost_cents bigint not null default 0 check(freight_cost_cents>=0),
 auction_fee_cents bigint not null default 0 check(auction_fee_cents>=0),
 handling_cost_cents bigint not null default 0 check(handling_cost_cents>=0),
 other_cost_cents bigint not null default 0 check(other_cost_cents>=0),
 allocation_method text not null default 'extended_acquisition_value'
  check(allocation_method in ('extended_acquisition_value','equal_per_unit')),
 status text not null default 'draft'
  check(status in ('draft','staged','needs_review','approved','rejected','receiving','received','cancelled')),
 row_count integer not null default 0 check(row_count between 0 and 2000),
 source_row_count integer not null default 0 check(source_row_count between 0 and 2000),
 validation_summary jsonb not null default '{}'::jsonb check(jsonb_typeof(validation_summary)='object'),
 created_by_identity_id uuid not null,
 reviewed_by_identity_id uuid,
 reviewed_at timestamptz,
 approved_by_identity_id uuid,
 approved_at timestamptz,
 rejected_by_identity_id uuid,
 rejected_at timestamptz,
 rejection_reason text,
 received_receipt_id uuid references public.mme_inventory_receipts(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check ((status<>'approved' and status<>'receiving' and status<>'received') or (approved_by_identity_id is not null and approved_at is not null)),
 check ((status<>'rejected') or (rejected_by_identity_id is not null and rejected_at is not null and rejection_reason is not null))
);

create table public.mme_auction_import_lines (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_auction_import_batches(id) on delete restrict,
 source_row_reference text not null,
 source_row_number integer not null check(source_row_number>0),
 source_item_title text not null check(length(btrim(source_item_title)) between 2 and 500),
 source_description text,
 source_quantity integer not null check(source_quantity between 1 and 10000),
 inventory_type text not null default 'aggregate' check(inventory_type in ('aggregate','serialized')),
 product_id uuid references public.mme_products(id) on delete restrict,
 location_id uuid references public.mme_store_locations(id) on delete restrict,
 condition_grade text check(condition_grade in ('new','open_box','refurbished','used')),
 acquisition_line_cost_cents bigint not null check(acquisition_line_cost_cents>=0),
 retail_estimate_cents bigint check(retail_estimate_cents>=0),
 retail_source_url text,
 retail_source_name text,
 retail_checked_at timestamptz,
 retail_evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(retail_evidence)='object'),
 match_confidence numeric(5,2) check(match_confidence between 0 and 100),
 review_status text not null default 'unmatched'
  check(review_status in ('unmatched','matched','needs_review','approved','rejected')),
 validation_errors jsonb not null default '[]'::jsonb check(jsonb_typeof(validation_errors)='array'),
 linked_serialized_unit_ids uuid[] not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(batch_id,source_row_reference),
 unique(batch_id,source_row_number),
 check ((retail_source_url is null and retail_checked_at is null) or
        (retail_source_url ~ '^https?://' and retail_source_name is not null and retail_checked_at is not null)),
 check ((review_status not in ('matched','approved')) or product_id is not null)
);

create index mme_auction_batches_status_idx on public.mme_auction_import_batches(status,created_at desc);
create index mme_auction_lines_batch_review_idx on public.mme_auction_import_lines(batch_id,review_status,source_row_number);
create index mme_auction_lines_product_idx on public.mme_auction_import_lines(product_id) where product_id is not null;

create table public.mme_auction_import_events (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_auction_import_batches(id) on delete restrict,
 line_id uuid references public.mme_auction_import_lines(id) on delete restrict,
 event_type text not null check(event_type in ('batch_created','rows_staged','validation_completed','line_matched','line_reviewed','batch_approved','batch_rejected','batch_cancelled','document_attached','retail_research_updated')),
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 actor_identity_id uuid not null,
 created_at timestamptz not null default now()
);
create index mme_auction_import_events_history_idx on public.mme_auction_import_events(batch_id,created_at);

alter table public.mme_auction_import_batches enable row level security;
alter table public.mme_auction_import_lines enable row level security;
alter table public.mme_auction_import_events enable row level security;
revoke all on public.mme_auction_import_batches,public.mme_auction_import_lines,public.mme_auction_import_events from public,anon,authenticated;
grant all on public.mme_auction_import_batches,public.mme_auction_import_lines,public.mme_auction_import_events to service_role;

create or replace function public.mme_stage_auction_import(
 p_batch_reference text,p_auction_name text,p_auction_lot_reference text,
 p_source_document_paths jsonb,p_source_filename text,p_source_file_sha256 text,
 p_acquisition_cost_cents bigint,p_freight_cost_cents bigint,p_auction_fee_cents bigint,
 p_handling_cost_cents bigint,p_other_cost_cents bigint,p_allocation_method text,
 p_actor_identity_id uuid,p_rows jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_batch_id uuid; v_count integer;
begin
 if p_batch_reference is null or length(btrim(p_batch_reference)) not between 3 and 80
  or p_auction_name is null or length(btrim(p_auction_name)) not between 2 and 160
  or p_acquisition_cost_cents is null or p_acquisition_cost_cents<0
  or p_freight_cost_cents is null or p_freight_cost_cents<0
  or p_auction_fee_cents is null or p_auction_fee_cents<0
  or p_handling_cost_cents is null or p_handling_cost_cents<0
  or p_other_cost_cents is null or p_other_cost_cents<0
  or p_allocation_method not in ('extended_acquisition_value','equal_per_unit')
  or p_actor_identity_id is null or p_rows is null or jsonb_typeof(p_rows)<>'array'
  or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>2000
  or p_source_document_paths is null or jsonb_typeof(p_source_document_paths)<>'array'
  or jsonb_array_length(p_source_document_paths)>30
  or p_source_file_sha256 is not null and p_source_file_sha256 !~ '^[a-fA-F0-9]{64}$' then
  raise exception 'Invalid auction import batch' using errcode='22023';
 end if;
 if exists(
  select 1 from jsonb_to_recordset(p_rows) as x(
   source_row_reference text,source_row_number integer,source_item_title text,source_description text,
   source_quantity integer,inventory_type text,product_id uuid,location_id uuid,condition_grade text,
   acquisition_line_cost_cents bigint,retail_estimate_cents bigint,retail_source_url text,
   retail_source_name text,retail_checked_at timestamptz,retail_evidence jsonb,match_confidence numeric)
  where x.source_row_reference is null or length(btrim(x.source_row_reference)) not between 1 and 100
   or x.source_row_number is null or x.source_row_number<1
   or x.source_item_title is null or length(btrim(x.source_item_title)) not between 2 and 500
   or x.source_quantity is null or x.source_quantity<1 or x.source_quantity>10000
   or x.inventory_type is null or x.inventory_type not in ('aggregate','serialized')
   or x.acquisition_line_cost_cents is null or x.acquisition_line_cost_cents<0
   or x.condition_grade is not null and x.condition_grade not in ('new','open_box','refurbished','used')
   or x.retail_estimate_cents is not null and x.retail_estimate_cents<0
   or x.match_confidence is not null and (x.match_confidence<0 or x.match_confidence>100)
   or x.retail_source_url is not null and (x.retail_source_url !~ '^https?://' or x.retail_source_name is null or x.retail_checked_at is null)
   or x.retail_evidence is not null and jsonb_typeof(x.retail_evidence)<>'object'
 ) or exists(
  select 1 from jsonb_to_recordset(p_rows) as x(source_row_reference text,source_row_number integer)
  group by x.source_row_reference having count(*)>1
 ) or exists(
  select 1 from jsonb_to_recordset(p_rows) as x(source_row_reference text,source_row_number integer)
  group by x.source_row_number having count(*)>1
 ) then raise exception 'Invalid or duplicate auction import row' using errcode='22023'; end if;
 select count(*) into v_count from jsonb_to_recordset(p_rows) as x(
  source_row_reference text,source_row_number integer,source_item_title text,source_description text,
  source_quantity integer,inventory_type text,product_id uuid,location_id uuid,condition_grade text,
  acquisition_line_cost_cents bigint,retail_estimate_cents bigint,retail_source_url text,
  retail_source_name text,retail_checked_at timestamptz,retail_evidence jsonb,match_confidence numeric);
 if (select coalesce(sum(x.acquisition_line_cost_cents::numeric),0)
   from jsonb_to_recordset(p_rows) as x(source_quantity integer,acquisition_line_cost_cents bigint))
   <> p_acquisition_cost_cents then
  raise exception 'Auction acquisition total must reconcile exactly to imported line costs' using errcode='22023';
 end if;
 insert into public.mme_auction_import_batches(
  batch_reference,auction_name,auction_lot_reference,source_document_paths,source_filename,source_file_sha256,
  acquisition_cost_cents,freight_cost_cents,auction_fee_cents,handling_cost_cents,other_cost_cents,
  allocation_method,status,row_count,source_row_count,created_by_identity_id,validation_summary
 ) values (
  upper(btrim(p_batch_reference)),btrim(p_auction_name),p_auction_lot_reference,p_source_document_paths,
  p_source_filename,p_source_file_sha256,p_acquisition_cost_cents,p_freight_cost_cents,p_auction_fee_cents,
  p_handling_cost_cents,p_other_cost_cents,p_allocation_method,'staged',v_count,v_count,p_actor_identity_id,
  jsonb_build_object('staged_rows',v_count,'acquisition_cost_reconciled',true,'review_required',true)
 ) returning id into v_batch_id;
 insert into public.mme_auction_import_lines(
  batch_id,source_row_reference,source_row_number,source_item_title,source_description,source_quantity,
  inventory_type,product_id,location_id,condition_grade,acquisition_line_cost_cents,retail_estimate_cents,
  retail_source_url,retail_source_name,retail_checked_at,retail_evidence,match_confidence,review_status
 )
 select v_batch_id,x.source_row_reference,x.source_row_number,btrim(x.source_item_title),x.source_description,
  x.source_quantity,x.inventory_type,x.product_id,x.location_id,x.condition_grade,x.acquisition_line_cost_cents,
  x.retail_estimate_cents,x.retail_source_url,x.retail_source_name,x.retail_checked_at,
  coalesce(x.retail_evidence,'{}'::jsonb),x.match_confidence,
  case when x.product_id is null then 'unmatched' else 'needs_review' end
 from jsonb_to_recordset(p_rows) as x(
  source_row_reference text,source_row_number integer,source_item_title text,source_description text,
  source_quantity integer,inventory_type text,product_id uuid,location_id uuid,condition_grade text,
  acquisition_line_cost_cents bigint,retail_estimate_cents bigint,retail_source_url text,
  retail_source_name text,retail_checked_at timestamptz,retail_evidence jsonb,match_confidence numeric);
 insert into public.mme_auction_import_events(batch_id,event_type,event_data,actor_identity_id)
 values(v_batch_id,'batch_created',jsonb_build_object('auction_name',btrim(p_auction_name),'row_count',v_count),p_actor_identity_id),
 (v_batch_id,'rows_staged',jsonb_build_object('row_count',v_count,'file_sha256',p_source_file_sha256),p_actor_identity_id);
 return v_batch_id;
end; $$;

create or replace function public.mme_review_auction_import_line(
 p_line_id uuid,p_product_id uuid,p_location_id uuid,p_review_status text,
 p_match_confidence numeric,p_actor_identity_id uuid,p_note text default null
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_batch_id uuid; v_batch_status text; v_serialized boolean;
begin
 if p_line_id is null or p_review_status not in ('matched','needs_review','rejected')
  or p_actor_identity_id is null or p_match_confidence is not null and (p_match_confidence<0 or p_match_confidence>100) then
  raise exception 'Invalid auction line review' using errcode='22023';
 end if;
 select l.batch_id,b.status into v_batch_id,v_batch_status
 from public.mme_auction_import_lines l join public.mme_auction_import_batches b on b.id=l.batch_id
 where l.id=p_line_id for update of l,b;
 if not found or v_batch_status not in ('staged','needs_review') then return false; end if;
 if p_review_status='matched' then
  if p_product_id is null or p_location_id is null then raise exception 'Matched line requires product and location' using errcode='22023'; end if;
  select serialized into v_serialized from public.mme_products where id=p_product_id and active=true;
  if not found then raise exception 'Active product not found' using errcode='P0002'; end if;
  if (select serialized from public.mme_products where id=p_product_id) is distinct from
     (select inventory_type='serialized' from public.mme_auction_import_lines where id=p_line_id) then
   raise exception 'Catalog product serialized type does not match import line' using errcode='23514';
  end if;
  if not exists(select 1 from public.mme_store_locations where id=p_location_id and active=true) then
   raise exception 'Active store location not found' using errcode='P0002';
  end if;
 end if;
 update public.mme_auction_import_lines set product_id=case when p_review_status='matched' then p_product_id else null end,
  location_id=case when p_review_status='matched' then p_location_id else null end,
  review_status=p_review_status,match_confidence=p_match_confidence,updated_at=now()
 where id=p_line_id;
 update public.mme_auction_import_batches set status='needs_review',reviewed_by_identity_id=p_actor_identity_id,
  reviewed_at=now(),updated_at=now() where id=v_batch_id;
 insert into public.mme_auction_import_events(batch_id,line_id,event_type,event_data,actor_identity_id)
 values(v_batch_id,p_line_id,'line_reviewed',jsonb_build_object('review_status',p_review_status,'product_id',p_product_id,
  'location_id',p_location_id,'confidence',p_match_confidence,'note',left(p_note,500)),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_decide_auction_import_batch(
 p_batch_id uuid,p_action text,p_actor_identity_id uuid,p_reason text default null
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_batch record; v_sum numeric; v_unreviewed integer; v_mismatch integer;
begin
 if p_batch_id is null or p_action not in ('approve','reject','cancel') or p_actor_identity_id is null then
  raise exception 'Invalid auction batch decision' using errcode='22023';
 end if;
 select * into v_batch from public.mme_auction_import_batches where id=p_batch_id for update;
 if not found then return false; end if;
 if p_action='reject' then
  if v_batch.status not in ('staged','needs_review') or p_reason is null or length(btrim(p_reason))<3 then return false; end if;
  update public.mme_auction_import_batches set status='rejected',rejected_by_identity_id=p_actor_identity_id,
   rejected_at=now(),rejection_reason=left(btrim(p_reason),1000),updated_at=now() where id=p_batch_id;
 elsif p_action='cancel' then
  if v_batch.status not in ('draft','staged','needs_review','approved') then return false; end if;
  update public.mme_auction_import_batches set status='cancelled',updated_at=now() where id=p_batch_id;
 else
  if v_batch.status not in ('staged','needs_review') then return false; end if;
  select coalesce(sum(acquisition_line_cost_cents::numeric),0),
   count(*) filter(where review_status not in ('matched','approved') or product_id is null or location_id is null),
   count(*) filter(where inventory_type='aggregate' and exists(select 1 from public.mme_products p where p.id=product_id and p.serialized=true)
    or inventory_type='serialized' and exists(select 1 from public.mme_products p where p.id=product_id and p.serialized=false))
  into v_sum,v_unreviewed,v_mismatch from public.mme_auction_import_lines where batch_id=p_batch_id;
  if v_sum<>v_batch.acquisition_cost_cents or v_unreviewed>0 or v_mismatch>0 then
   raise exception 'Auction batch has cost mismatch, unmatched rows, or product type mismatch' using errcode='23514';
  end if;
  update public.mme_auction_import_lines set review_status='approved',updated_at=now()
   where batch_id=p_batch_id and review_status='matched';
  update public.mme_auction_import_batches set status='approved',approved_by_identity_id=p_actor_identity_id,
   approved_at=now(),updated_at=now(),validation_summary=validation_summary||
   jsonb_build_object('approved_rows',v_batch.row_count,'cost_reconciled',true) where id=p_batch_id;
 end if;
 insert into public.mme_auction_import_events(batch_id,event_type,event_data,actor_identity_id)
 values(p_batch_id,case p_action when 'approve' then 'batch_approved' when 'reject' then 'batch_rejected' else 'batch_cancelled' end,
  jsonb_build_object('reason',p_reason),p_actor_identity_id);
 return true;
end; $$;

revoke all on function public.mme_stage_auction_import(text,text,text,jsonb,text,text,bigint,bigint,bigint,bigint,bigint,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.mme_review_auction_import_line(uuid,uuid,uuid,text,numeric,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_decide_auction_import_batch(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_stage_auction_import(text,text,text,jsonb,text,text,bigint,bigint,bigint,bigint,bigint,text,uuid,jsonb) to service_role;
grant execute on function public.mme_review_auction_import_line(uuid,uuid,uuid,text,numeric,uuid,text) to service_role;
grant execute on function public.mme_decide_auction_import_batch(uuid,text,uuid,text) to service_role;

comment on table public.mme_auction_import_batches is
 'CEO-controlled auction CSV/document intake batches with exact acquisition-cost reconciliation.';
comment on table public.mme_auction_import_lines is
 'Staged source rows with product matching, condition, quantity, per-line cost and retail research provenance.';
