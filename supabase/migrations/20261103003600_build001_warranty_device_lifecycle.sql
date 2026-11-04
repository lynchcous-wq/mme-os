-- Build 001: warranty registration, claim lifecycle, repair authorization and device service history.
-- Warranty claims never change inventory availability without the inspection/disposition workflow.

create table public.mme_warranty_policies (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.mme_products(id) on delete restrict,
 warranty_provider text not null check(length(btrim(warranty_provider)) between 2 and 160),
 coverage_type text not null check(coverage_type in ('manufacturer','supplier','mme_limited','extended')),
 coverage_days integer not null check(coverage_days between 1 and 3650),
 coverage_terms text not null check(length(btrim(coverage_terms)) between 5 and 5000),
 exclusions jsonb not null default '[]'::jsonb check(jsonb_typeof(exclusions)='array'),
 parts_covered boolean not null default true,
 labor_covered boolean not null default true,
 active boolean not null default true,
 created_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_warranty_policies_product_active_idx on public.mme_warranty_policies(product_id,active);

create table public.mme_device_warranties (
 id uuid primary key default gen_random_uuid(),
 warranty_reference text not null unique,
 serialized_unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 policy_id uuid references public.mme_warranty_policies(id) on delete restrict,
 coverage_type text not null check(coverage_type in ('manufacturer','supplier','mme_limited','extended')),
 warranty_provider text not null check(length(btrim(warranty_provider)) between 2 and 160),
 provider_contract_reference text,
 start_date date not null,
 end_date date not null,
 coverage_terms_snapshot text not null,
 exclusions_snapshot jsonb not null default '[]'::jsonb check(jsonb_typeof(exclusions_snapshot)='array'),
 warranty_status text not null default 'active' check(warranty_status in ('active','expired','void','claimed','fulfilled')),
 registered_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(end_date>=start_date)
);
create index mme_device_warranties_unit_idx on public.mme_device_warranties(serialized_unit_id,end_date desc);
create index mme_device_warranties_expiry_idx on public.mme_device_warranties(warranty_status,end_date);

create table public.mme_warranty_claims (
 id uuid primary key default gen_random_uuid(),
 claim_reference text not null unique,
 warranty_id uuid not null references public.mme_device_warranties(id) on delete restrict,
 serialized_unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 order_id uuid references public.mme_orders(id) on delete restrict,
 return_case_id uuid references public.mme_return_cases(id) on delete restrict,
 claim_type text not null check(claim_type in ('repair','replacement','refund_review','diagnostic')),
 issue_description text not null check(length(btrim(issue_description)) between 10 and 3000),
 evidence jsonb not null default '[]'::jsonb check(jsonb_typeof(evidence)='array'),
 claim_status text not null default 'submitted'
  check(claim_status in ('submitted','under_review','approved','denied','repair_authorized','awaiting_parts','in_service','completed','replacement_authorized','closed')),
 requested_by_identity_id uuid not null,
 reviewed_by_identity_id uuid,
 review_reason text,
 authorized_cost_cents bigint check(authorized_cost_cents is null or authorized_cost_cents>=0),
 currency text not null default 'USD' check(currency='USD'),
 submitted_at timestamptz not null default now(),
 reviewed_at timestamptz,
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_warranty_claims_unit_idx on public.mme_warranty_claims(serialized_unit_id,created_at desc);
create index mme_warranty_claims_status_idx on public.mme_warranty_claims(claim_status,submitted_at);

create table public.mme_device_service_history (
 id uuid primary key default gen_random_uuid(),
 serialized_unit_id uuid not null references public.mme_serialized_units(id) on delete restrict,
 warranty_claim_id uuid references public.mme_warranty_claims(id) on delete restrict,
 inspection_id uuid references public.mme_inventory_inspections(id) on delete restrict,
 service_type text not null check(service_type in ('diagnostic','repair','parts_replacement','firmware','cleaning','quality_check','replacement','other')),
 service_provider text not null,
 description text not null check(length(btrim(description)) between 5 and 3000),
 parts_used jsonb not null default '[]'::jsonb check(jsonb_typeof(parts_used)='array'),
 labor_minutes integer check(labor_minutes is null or labor_minutes>=0),
 cost_cents bigint not null default 0 check(cost_cents>=0),
 outcome text not null check(outcome in ('pending','successful','unsuccessful','referred','unit_replaced')),
 performed_by_identity_id uuid not null,
 performed_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create index mme_device_service_history_unit_idx on public.mme_device_service_history(serialized_unit_id,performed_at desc);

alter table public.mme_warranty_policies enable row level security;
alter table public.mme_device_warranties enable row level security;
alter table public.mme_warranty_claims enable row level security;
alter table public.mme_device_service_history enable row level security;
revoke all on public.mme_warranty_policies,public.mme_device_warranties,public.mme_warranty_claims,
 public.mme_device_service_history from public,anon,authenticated;
grant all on public.mme_warranty_policies,public.mme_device_warranties,public.mme_warranty_claims,
 public.mme_device_service_history to service_role;

create or replace function public.mme_register_device_warranty(
 p_reference text,p_unit_id uuid,p_policy_id uuid,p_provider text,p_provider_reference text,
 p_start_date date,p_end_date date,p_terms text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_unit public.mme_serialized_units%rowtype; v_policy public.mme_warranty_policies%rowtype; v_id uuid;
begin
 if p_reference is null or length(btrim(p_reference)) not between 3 and 100
  or p_unit_id is null or p_provider is null or length(btrim(p_provider)) not between 2 and 160
  or p_start_date is null or p_end_date is null or p_end_date<p_start_date
  or p_terms is null or length(btrim(p_terms))<5 or p_actor_identity_id is null then
  raise exception 'Invalid device warranty registration' using errcode='22023'; end if;
 select * into v_unit from public.mme_serialized_units where id=p_unit_id for update;
 if not found then raise exception 'Serialized device not found' using errcode='P0002'; end if;
 if p_policy_id is not null then
  select * into v_policy from public.mme_warranty_policies
   where id=p_policy_id and product_id=v_unit.product_id and active=true;
  if not found then raise exception 'Active warranty policy does not match device product' using errcode='23514'; end if;
  if p_end_date>p_start_date+v_policy.coverage_days then
   raise exception 'Warranty end date exceeds policy coverage duration' using errcode='23514'; end if;
  insert into public.mme_device_warranties(warranty_reference,serialized_unit_id,product_id,policy_id,
   coverage_type,warranty_provider,provider_contract_reference,start_date,end_date,
   coverage_terms_snapshot,exclusions_snapshot,registered_by_identity_id)
  values(btrim(p_reference),p_unit_id,v_unit.product_id,p_policy_id,v_policy.coverage_type,
   v_policy.warranty_provider,left(p_provider_reference,180),p_start_date,p_end_date,
   v_policy.coverage_terms,v_policy.exclusions,p_actor_identity_id) returning id into v_id;
 else
  insert into public.mme_device_warranties(warranty_reference,serialized_unit_id,product_id,
   coverage_type,warranty_provider,provider_contract_reference,start_date,end_date,
   coverage_terms_snapshot,registered_by_identity_id)
  values(btrim(p_reference),p_unit_id,v_unit.product_id,'manufacturer',btrim(p_provider),
   left(p_provider_reference,180),p_start_date,p_end_date,btrim(p_terms),p_actor_identity_id)
  returning id into v_id;
 end if;
 return v_id;
end; $$;

create or replace function public.mme_open_warranty_claim(
 p_reference text,p_warranty_id uuid,p_claim_type text,p_issue text,p_evidence jsonb,
 p_requested_by_identity_id uuid,p_order_id uuid default null,p_return_case_id uuid default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_warranty public.mme_device_warranties%rowtype; v_id uuid;
begin
 if p_reference is null or length(btrim(p_reference)) not between 3 and 100
  or p_warranty_id is null or p_claim_type not in ('repair','replacement','refund_review','diagnostic')
  or p_issue is null or length(btrim(p_issue)) not between 10 and 3000
  or p_evidence is null or jsonb_typeof(p_evidence)<>'array' or jsonb_array_length(p_evidence)>30
  or p_requested_by_identity_id is null then raise exception 'Invalid warranty claim' using errcode='22023'; end if;
 select * into v_warranty from public.mme_device_warranties where id=p_warranty_id for update;
 if not found or v_warranty.warranty_status not in ('active','claimed') or current_date not between v_warranty.start_date and v_warranty.end_date then
  raise exception 'Warranty is not currently eligible for a claim' using errcode='23514'; end if;
 if p_order_id is not null and not exists(select 1 from public.mme_order_lines
   where order_id=p_order_id and serialized_unit_id=v_warranty.serialized_unit_id) then
  raise exception 'Order does not contain the warranted device' using errcode='23514'; end if;
 insert into public.mme_warranty_claims(claim_reference,warranty_id,serialized_unit_id,order_id,
  return_case_id,claim_type,issue_description,evidence,requested_by_identity_id)
 values(btrim(p_reference),p_warranty_id,v_warranty.serialized_unit_id,p_order_id,
  p_return_case_id,p_claim_type,btrim(p_issue),p_evidence,p_requested_by_identity_id)
 returning id into v_id;
 update public.mme_device_warranties set warranty_status='claimed',updated_at=now() where id=p_warranty_id;
 return v_id;
end; $$;

create or replace function public.mme_review_warranty_claim(
 p_claim_id uuid,p_decision text,p_reason text,p_reviewer_identity_id uuid,
 p_authorized_cost_cents bigint default null
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_claim public.mme_warranty_claims%rowtype;
begin
 if p_claim_id is null or p_decision not in ('approved','denied','repair_authorized','replacement_authorized')
  or p_reason is null or length(btrim(p_reason))<5 or p_reviewer_identity_id is null
  or p_authorized_cost_cents is not null and p_authorized_cost_cents<0 then
  raise exception 'Invalid warranty claim decision' using errcode='22023'; end if;
 select * into v_claim from public.mme_warranty_claims where id=p_claim_id for update;
 if not found or v_claim.claim_status not in ('submitted','under_review') then return false; end if;
 if p_reviewer_identity_id=v_claim.requested_by_identity_id then
  raise exception 'Claim requester cannot review own claim' using errcode='23514'; end if;
 update public.mme_warranty_claims set claim_status=p_decision,reviewed_by_identity_id=p_reviewer_identity_id,
  review_reason=btrim(p_reason),authorized_cost_cents=p_authorized_cost_cents,
  reviewed_at=now(),updated_at=now() where id=p_claim_id;
 return true;
end; $$;

create or replace function public.mme_record_device_service(
 p_unit_id uuid,p_claim_id uuid,p_inspection_id uuid,p_service_type text,
 p_provider text,p_description text,p_parts_used jsonb,p_labor_minutes integer,
 p_cost_cents bigint,p_outcome text,p_actor_identity_id uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_claim public.mme_warranty_claims%rowtype; v_id uuid;
begin
 if p_unit_id is null or p_service_type not in ('diagnostic','repair','parts_replacement','firmware','cleaning','quality_check','replacement','other')
  or p_provider is null or length(btrim(p_provider))<2
  or p_description is null or length(btrim(p_description))<5
  or p_parts_used is null or jsonb_typeof(p_parts_used)<>'array' or jsonb_array_length(p_parts_used)>50
  or p_labor_minutes is not null and p_labor_minutes<0 or p_cost_cents is null or p_cost_cents<0
  or p_outcome not in ('pending','successful','unsuccessful','referred','unit_replaced')
  or p_actor_identity_id is null then raise exception 'Invalid device service record' using errcode='22023'; end if;
 perform 1 from public.mme_serialized_units where id=p_unit_id for update;
 if not found then raise exception 'Serialized device not found' using errcode='P0002'; end if;
 if p_claim_id is not null then
  select * into v_claim from public.mme_warranty_claims where id=p_claim_id and serialized_unit_id=p_unit_id for update;
  if not found or v_claim.claim_status not in ('repair_authorized','in_service','awaiting_parts','replacement_authorized') then
   raise exception 'Service record requires an authorized claim for this device' using errcode='23514'; end if;
  update public.mme_warranty_claims set claim_status='in_service',updated_at=now() where id=p_claim_id;
 end if;
 insert into public.mme_device_service_history(serialized_unit_id,warranty_claim_id,inspection_id,
  service_type,service_provider,description,parts_used,labor_minutes,cost_cents,outcome,performed_by_identity_id)
 values(p_unit_id,p_claim_id,p_inspection_id,p_service_type,btrim(p_provider),btrim(p_description),
  p_parts_used,p_labor_minutes,p_cost_cents,p_outcome,p_actor_identity_id)
 returning id into v_id;
 if p_claim_id is not null and p_outcome in ('successful','unit_replaced') then
  update public.mme_warranty_claims set claim_status='completed',completed_at=now(),updated_at=now()
   where id=p_claim_id;
 end if;
 return v_id;
end; $$;

revoke all on function public.mme_register_device_warranty(text,uuid,uuid,text,text,date,date,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_open_warranty_claim(text,uuid,text,text,jsonb,uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_review_warranty_claim(uuid,text,text,uuid,bigint) from public,anon,authenticated;
revoke all on function public.mme_record_device_service(uuid,uuid,uuid,text,text,text,jsonb,integer,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_register_device_warranty(text,uuid,uuid,text,text,date,date,text,uuid) to service_role;
grant execute on function public.mme_open_warranty_claim(text,uuid,text,text,jsonb,uuid,uuid,uuid) to service_role;
grant execute on function public.mme_review_warranty_claim(uuid,text,text,uuid,bigint) to service_role;
grant execute on function public.mme_record_device_service(uuid,uuid,uuid,text,text,text,jsonb,integer,bigint,text,uuid) to service_role;

comment on table public.mme_device_warranties is 'Per-device warranty coverage snapshots and expiration dates.';
comment on table public.mme_warranty_claims is 'Warranty claim decisions, repair/replacement authorization and review audit.';
comment on table public.mme_device_service_history is 'Append-only service, repair, part and diagnostic history for each serialized device.';
