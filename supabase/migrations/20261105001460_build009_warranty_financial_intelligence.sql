-- Build 009.66 — warranty financial facts, cost controls and reserve intelligence.
begin;
create table public.mme_warranty_financial_entries (
 financial_entry_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 provider_claim_id uuid references public.mme_warranty_provider_claims(provider_claim_id) on delete restrict,
 entry_type text not null check(entry_type in ('warranty_revenue','repair_parts_cost','repair_labor_cost','provider_recovery','customer_charge','reserve_adjustment')),
 realization text not null check(realization in ('actual','projection')),
 amount numeric(16,2) not null check(amount>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 effective_at timestamptz not null,
 source_reference text not null,
 idempotency_key text not null unique,
 recorded_by uuid not null,
 approved_by uuid,
 approved_at timestamptz,
 notes text,
 created_at timestamptz not null default now(),
 check(approved_by is null or approved_by<>recorded_by),
 check(realization<>'actual' or (approved_by is not null and approved_at is not null))
);
create index mme_warranty_financial_case_idx on public.mme_warranty_financial_entries(repair_case_id,effective_at);
create index mme_warranty_financial_type_idx on public.mme_warranty_financial_entries(entry_type,realization,currency_code,effective_at);
create index mme_warranty_financial_claim_idx on public.mme_warranty_financial_entries(provider_claim_id);

create table public.mme_warranty_reserve_assumptions (
 assumption_id uuid primary key default gen_random_uuid(),
 plan_code text not null,
 product_category text not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 expected_claim_frequency numeric(9,6) not null check(expected_claim_frequency between 0 and 1),
 expected_severity numeric(16,2) not null check(expected_severity>=0),
 expected_admin_cost numeric(16,2) not null default 0 check(expected_admin_cost>=0),
 confidence_level numeric(5,4) not null default 0.9500 check(confidence_level between 0 and 1),
 effective_from date not null,
 effective_to date,
 approved_by uuid not null,
 created_at timestamptz not null default now(),
 check(effective_to is null or effective_to>=effective_from)
);
create index mme_warranty_reserve_assumption_idx on public.mme_warranty_reserve_assumptions(plan_code,product_category,effective_from desc);

create table public.mme_warranty_reserve_snapshots (
 reserve_snapshot_id uuid primary key default gen_random_uuid(),
 as_of_date date not null,
 plan_code text not null,
 product_category text not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 active_contract_count bigint not null check(active_contract_count>=0),
 projected_claim_count numeric(18,4) not null check(projected_claim_count>=0),
 projected_claim_cost numeric(18,2) not null check(projected_claim_cost>=0),
 projected_admin_cost numeric(18,2) not null check(projected_admin_cost>=0),
 required_reserve numeric(18,2) not null check(required_reserve>=0),
 model_version text not null,
 assumption_id uuid not null references public.mme_warranty_reserve_assumptions(assumption_id) on delete restrict,
 generated_by uuid not null,
 approved_by uuid,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 unique(as_of_date,plan_code,product_category,currency_code,model_version),
 check(approved_by is null or approved_by<>generated_by)
);
create index mme_warranty_reserve_snapshot_idx on public.mme_warranty_reserve_snapshots(as_of_date desc,plan_code,product_category);

create table public.mme_warranty_financial_events (
 event_id bigint generated always as identity primary key,
 financial_entry_id uuid references public.mme_warranty_financial_entries(financial_entry_id) on delete restrict,
 reserve_snapshot_id uuid references public.mme_warranty_reserve_snapshots(reserve_snapshot_id) on delete restrict,
 actor_id uuid not null,
 event_type text not null check(event_type in ('financial_entry_recorded','financial_entry_approved','reserve_snapshot_created','reserve_snapshot_approved')),
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 created_at timestamptz not null default now(),
 check((financial_entry_id is not null)::int+(reserve_snapshot_id is not null)::int=1)
);
create index mme_warranty_financial_events_idx on public.mme_warranty_financial_events(event_id);

alter table public.mme_warranty_financial_entries enable row level security;
alter table public.mme_warranty_reserve_assumptions enable row level security;
alter table public.mme_warranty_reserve_snapshots enable row level security;
alter table public.mme_warranty_financial_events enable row level security;
revoke all on public.mme_warranty_financial_entries,public.mme_warranty_reserve_assumptions,public.mme_warranty_reserve_snapshots,public.mme_warranty_financial_events from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_financial_entries,public.mme_warranty_reserve_assumptions,public.mme_warranty_reserve_snapshots to service_role;
grant select,insert on public.mme_warranty_financial_events to service_role;
revoke update,delete,truncate on public.mme_warranty_financial_events from public,anon,authenticated,service_role;

create or replace function public.mme_warranty_financial_record(
 p_case uuid,p_claim uuid,p_type text,p_realization text,p_amount numeric,p_currency text,
 p_effective_at timestamptz,p_source_reference text,p_actor uuid,p_idempotency_key text,p_notes text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v uuid; c public.mme_warranty_repair_cases%rowtype; cl public.mme_warranty_provider_claims%rowtype;
begin
 if p_actor is null or p_amount<0 or length(trim(coalesce(p_idempotency_key,'')))<12 or length(trim(coalesce(p_source_reference,'')))=0 then raise exception 'Actor, amount, source and idempotency key required' using errcode='22023'; end if;
 if p_realization not in ('actual','projection') or p_type not in ('warranty_revenue','repair_parts_cost','repair_labor_cost','provider_recovery','customer_charge','reserve_adjustment') then raise exception 'Unsupported financial classification' using errcode='22023'; end if;
 if p_case is not null then select * into c from public.mme_warranty_repair_cases where repair_case_id=p_case; if not found then raise exception 'Repair case not found' using errcode='P0002'; end if; end if;
 if p_claim is not null then
  select * into cl from public.mme_warranty_provider_claims where provider_claim_id=p_claim;
  if not found or (p_case is not null and cl.repair_case_id<>p_case) then raise exception 'Provider claim does not match repair case' using errcode='23514'; end if;
 end if;
 if p_type='provider_recovery' and (p_claim is null or p_realization<>'actual' and p_realization<>'projection') then raise exception 'Provider recovery must reference a claim' using errcode='23514'; end if;
 insert into public.mme_warranty_financial_entries(repair_case_id,provider_claim_id,entry_type,realization,amount,currency_code,effective_at,source_reference,idempotency_key,recorded_by,notes)
 values(p_case,p_claim,p_type,p_realization,p_amount,p_currency,p_effective_at,p_source_reference,p_idempotency_key,p_actor,left(p_notes,1000))
 on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key
 returning financial_entry_id into v;
 insert into public.mme_warranty_financial_events(financial_entry_id,actor_id,event_type,event_data)
 values(v,p_actor,'financial_entry_recorded',jsonb_build_object('entry_type',p_type,'realization',p_realization,'amount',p_amount,'currency',p_currency));
 return v;
end; $$;

create or replace function public.mme_warranty_financial_approve(p_entry uuid,p_actor uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare e public.mme_warranty_financial_entries%rowtype;
begin
 select * into e from public.mme_warranty_financial_entries where financial_entry_id=p_entry for update;
 if not found or e.realization<>'actual' or e.approved_at is not null then raise exception 'Unapproved actual entry not found' using errcode='55000'; end if;
 if p_actor is null or p_actor=e.recorded_by then raise exception 'Independent finance approver required' using errcode='42501'; end if;
 update public.mme_warranty_financial_entries set approved_by=p_actor,approved_at=now() where financial_entry_id=p_entry;
 insert into public.mme_warranty_financial_events(financial_entry_id,actor_id,event_type,event_data)
 values(p_entry,p_actor,'financial_entry_approved','{}'::jsonb);
end; $$;

create or replace function public.mme_warranty_reserve_create_snapshot(
 p_date date,p_plan text,p_category text,p_currency text,p_active bigint,p_model text,p_actor uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare a public.mme_warranty_reserve_assumptions%rowtype; v uuid; n numeric(18,4); claim_cost numeric(18,2); admin_cost numeric(18,2); reserve numeric(18,2);
begin
 if p_actor is null or p_active<0 then raise exception 'Actor and non-negative contract count required' using errcode='22023'; end if;
 select * into a from public.mme_warranty_reserve_assumptions where plan_code=p_plan and product_category=p_category and currency_code=p_currency and effective_from<=p_date and (effective_to is null or effective_to>=p_date) order by effective_from desc limit 1;
 if not found then raise exception 'No effective approved reserve assumption found' using errcode='P0002'; end if;
 n:=round(p_active*a.expected_claim_frequency,4);
 claim_cost:=round(n*a.expected_severity,2);
 admin_cost:=round(n*a.expected_admin_cost,2);
 reserve:=claim_cost+admin_cost;
 insert into public.mme_warranty_reserve_snapshots(as_of_date,plan_code,product_category,currency_code,active_contract_count,projected_claim_count,projected_claim_cost,projected_admin_cost,required_reserve,model_version,assumption_id,generated_by)
 values(p_date,p_plan,p_category,p_currency,p_active,n,claim_cost,admin_cost,reserve,p_model,a.assumption_id,p_actor)
 on conflict(as_of_date,plan_code,product_category,currency_code,model_version) do update set active_contract_count=excluded.active_contract_count,projected_claim_count=excluded.projected_claim_count,projected_claim_cost=excluded.projected_claim_cost,projected_admin_cost=excluded.projected_admin_cost,required_reserve=excluded.required_reserve,assumption_id=excluded.assumption_id
 returning reserve_snapshot_id into v;
 insert into public.mme_warranty_financial_events(reserve_snapshot_id,actor_id,event_type,event_data)
 values(v,p_actor,'reserve_snapshot_created',jsonb_build_object('required_reserve',reserve,'model_version',p_model));
 return v;
end; $$;

create or replace function public.mme_warranty_reserve_approve(p_snapshot uuid,p_actor uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare s public.mme_warranty_reserve_snapshots%rowtype;
begin
 select * into s from public.mme_warranty_reserve_snapshots where reserve_snapshot_id=p_snapshot for update;
 if not found or s.approved_at is not null then raise exception 'Unapproved reserve snapshot not found' using errcode='55000'; end if;
 if p_actor is null or p_actor=s.generated_by then raise exception 'Independent finance approval required' using errcode='42501'; end if;
 update public.mme_warranty_reserve_snapshots set approved_by=p_actor,approved_at=now() where reserve_snapshot_id=p_snapshot;
 insert into public.mme_warranty_financial_events(reserve_snapshot_id,actor_id,event_type,event_data)
 values(p_snapshot,p_actor,'reserve_snapshot_approved','{}'::jsonb);
end; $$;

create or replace view public.mme_warranty_financial_summary as
select entry_type,realization,currency_code,count(*) entry_count,sum(amount)::numeric(18,2) total_amount,
 count(*) filter(where realization='actual' and approved_at is not null) approved_actual_count,
 sum(amount) filter(where realization='actual' and approved_at is not null)::numeric(18,2) approved_actual_amount,
 sum(amount) filter(where realization='projection')::numeric(18,2) projected_amount
from public.mme_warranty_financial_entries group by entry_type,realization,currency_code;
revoke all on public.mme_warranty_financial_summary from public,anon,authenticated;
grant select on public.mme_warranty_financial_summary to service_role;

revoke all on function public.mme_warranty_financial_record(uuid,uuid,text,text,numeric,text,timestamptz,text,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_financial_approve(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_warranty_reserve_create_snapshot(date,text,text,text,bigint,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_warranty_reserve_approve(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_financial_record(uuid,uuid,text,text,numeric,text,timestamptz,text,uuid,text,text) to service_role;
grant execute on function public.mme_warranty_financial_approve(uuid,uuid) to service_role;
grant execute on function public.mme_warranty_reserve_create_snapshot(date,text,text,text,bigint,text,uuid) to service_role;
grant execute on function public.mme_warranty_reserve_approve(uuid,uuid) to service_role;
commit;
