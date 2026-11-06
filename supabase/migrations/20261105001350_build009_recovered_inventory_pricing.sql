-- Build 009.55 — recovered inventory pricing, margin controls and website price handoff.
begin;

create table public.mme_recovered_market_comparables (
 comparable_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 source_name text not null,
 source_url text,
 observed_price numeric(14,2) not null check(observed_price>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 product_condition text not null check(product_condition in ('new','open_box','refurbished','used','parts_only')),
 observed_at timestamptz not null,
 expires_at timestamptz,
 evidence_reference text,
 recorded_by uuid not null,
 created_at timestamptz not null default now()
);
create index mme_recovered_market_comparables_asset_idx on public.mme_recovered_market_comparables(recovery_asset_id,observed_at desc);

create table public.mme_recovered_pricing_policies (
 policy_id uuid primary key default gen_random_uuid(),
 policy_name text not null,
 product_category text,
 resale_classification text not null check(resale_classification in ('open_box','refurbished','parts_only')),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 minimum_margin_percent numeric(7,3) not null check(minimum_margin_percent between 0 and 99.999),
 target_margin_percent numeric(7,3) not null check(target_margin_percent between 0 and 99.999),
 markdown_step_percent numeric(7,3) not null default 5 check(markdown_step_percent between 0 and 50),
 markdown_interval_days integer not null default 14 check(markdown_interval_days between 1 and 365),
 maximum_markdown_percent numeric(7,3) not null default 25 check(maximum_markdown_percent between 0 and 90),
 under_minimum_requires_approval boolean not null default true,
 active boolean not null default true,
 created_by uuid not null,
 created_at timestamptz not null default now(),
 check(target_margin_percent>=minimum_margin_percent)
);
create index mme_recovered_pricing_policies_active_idx on public.mme_recovered_pricing_policies(active,product_category,resale_classification);

create table public.mme_recovered_price_recommendations (
 recommendation_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 policy_id uuid not null references public.mme_recovered_pricing_policies(policy_id) on delete restrict,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 recovered_unit_cost numeric(14,2) not null check(recovered_unit_cost>=0),
 comparable_median numeric(14,2) check(comparable_median is null or comparable_median>=0),
 minimum_selling_price numeric(14,2) not null check(minimum_selling_price>=0),
 target_selling_price numeric(14,2) not null check(target_selling_price>=0),
 recommended_selling_price numeric(14,2) not null check(recommended_selling_price>=0),
 estimated_gross_profit numeric(14,2) not null,
 estimated_margin_percent numeric(7,3) not null,
 recommendation_status text not null default 'pending' check(recommendation_status in ('pending','approved','rejected','superseded','expired')),
 rationale jsonb not null default '{}'::jsonb,
 generated_at timestamptz not null default now(),
 reviewed_by uuid,
 reviewed_at timestamptz,
 review_note text
);
create index mme_recovered_price_recommendations_asset_idx on public.mme_recovered_price_recommendations(recovery_asset_id,generated_at desc);

create table public.mme_recovered_price_overrides (
 override_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 recommendation_id uuid references public.mme_recovered_price_recommendations(recommendation_id) on delete restrict,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 prior_price numeric(14,2) check(prior_price is null or prior_price>=0),
 override_price numeric(14,2) not null check(override_price>=0),
 reason text not null,
 requested_by uuid not null,
 approved_by uuid,
 approval_status text not null default 'pending' check(approval_status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 approved_at timestamptz,
 check(approved_by is null or approved_by<>requested_by)
);
create index mme_recovered_price_overrides_asset_idx on public.mme_recovered_price_overrides(recovery_asset_id,created_at desc);

create table public.mme_recovered_markdown_plans (
 markdown_plan_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 policy_id uuid not null references public.mme_recovered_pricing_policies(policy_id) on delete restrict,
 starting_price numeric(14,2) not null check(starting_price>=0),
 current_price numeric(14,2) not null check(current_price>=0),
 markdown_step_percent numeric(7,3) not null check(markdown_step_percent between 0 and 50),
 maximum_markdown_percent numeric(7,3) not null check(maximum_markdown_percent between 0 and 90),
 markdown_count integer not null default 0 check(markdown_count>=0),
 next_review_at timestamptz not null,
 plan_status text not null default 'active' check(plan_status in ('active','paused','completed','approval_required','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_recovered_markdown_due_idx on public.mme_recovered_markdown_plans(plan_status,next_review_at);

create table public.mme_recovered_price_publication_outbox (
 publication_id uuid primary key default gen_random_uuid(),
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 idempotency_key text not null unique,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 selling_price numeric(14,2) not null check(selling_price>=0),
 condition_disclosure text not null,
 publication_status text not null default 'pending' check(publication_status in ('pending','processing','published','failed','cancelled')),
 catalog_transaction_reference text,
 last_error text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_recovered_price_publication_queue_idx on public.mme_recovered_price_publication_outbox(publication_status,created_at);

create table public.mme_recovered_pricing_audit (
 audit_id bigint generated always as identity primary key,
 recovery_asset_id uuid not null references public.mme_inventory_recovery_assets(recovery_asset_id) on delete restrict,
 actor_user_id uuid not null,
 action text not null,
 prior_state jsonb not null default '{}'::jsonb,
 new_state jsonb not null default '{}'::jsonb,
 reason text,
 created_at timestamptz not null default now()
);

alter table public.mme_recovered_market_comparables enable row level security;
alter table public.mme_recovered_pricing_policies enable row level security;
alter table public.mme_recovered_price_recommendations enable row level security;
alter table public.mme_recovered_price_overrides enable row level security;
alter table public.mme_recovered_markdown_plans enable row level security;
alter table public.mme_recovered_price_publication_outbox enable row level security;
alter table public.mme_recovered_pricing_audit enable row level security;
revoke all on public.mme_recovered_market_comparables,public.mme_recovered_pricing_policies,
 public.mme_recovered_price_recommendations,public.mme_recovered_price_overrides,
 public.mme_recovered_markdown_plans,public.mme_recovered_price_publication_outbox,
 public.mme_recovered_pricing_audit from public,anon,authenticated;
grant select,insert,update on public.mme_recovered_market_comparables,public.mme_recovered_pricing_policies,
 public.mme_recovered_price_recommendations,public.mme_recovered_price_overrides,
 public.mme_recovered_markdown_plans,public.mme_recovered_price_publication_outbox to service_role;
grant select,insert on public.mme_recovered_pricing_audit to service_role;
revoke update,delete,truncate on public.mme_recovered_pricing_audit from public,anon,authenticated,service_role;

create or replace function public.mme_recovered_inventory_generate_price(
 p_recovery_asset_id uuid,p_policy_id uuid,p_actor_user_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 v_asset public.mme_inventory_recovery_assets%rowtype;
 v_policy public.mme_recovered_pricing_policies%rowtype;
 v_cost numeric(14,2); v_median numeric(14,2); v_floor numeric(14,2);
 v_target numeric(14,2); v_price numeric(14,2); v_margin numeric(7,3); v_id uuid;
begin
 select * into v_asset from public.mme_inventory_recovery_assets where recovery_asset_id=p_recovery_asset_id for update;
 if not found or v_asset.asset_status not in ('classified','posted_to_inventory') or v_asset.resale_classification not in ('open_box','refurbished','parts_only') then
  raise exception 'Classified resale-eligible asset required' using errcode='55000'; end if;
 select * into v_policy from public.mme_recovered_pricing_policies where policy_id=p_policy_id and active for share;
 if not found or v_policy.resale_classification<>v_asset.resale_classification then raise exception 'Active matching pricing policy required' using errcode='55000'; end if;
 select coalesce(sum(amount),0) into v_cost from public.mme_recovered_asset_cost_ledger where recovery_asset_id=p_recovery_asset_id and currency_code=v_policy.currency_code;
 select percentile_cont(0.5) within group(order by observed_price) into v_median
 from public.mme_recovered_market_comparables where recovery_asset_id=p_recovery_asset_id
 and currency_code=v_policy.currency_code and product_condition in (v_asset.resale_classification,'used')
 and observed_at>now()-interval '30 days' and (expires_at is null or expires_at>now());
 v_floor:=case when v_policy.minimum_margin_percent=0 then v_cost else v_cost/(1-v_policy.minimum_margin_percent/100) end;
 v_target:=case when v_policy.target_margin_percent=0 then v_cost else v_cost/(1-v_policy.target_margin_percent/100) end;
 v_price:=round(case when v_median is null then v_target else least(v_target,greatest(v_floor,v_median)) end,2);
 v_margin:=case when v_price=0 then 0 else round(((v_price-v_cost)/v_price)*100,3) end;
 insert into public.mme_recovered_price_recommendations(recovery_asset_id,policy_id,currency_code,recovered_unit_cost,
  comparable_median,minimum_selling_price,target_selling_price,recommended_selling_price,
  estimated_gross_profit,estimated_margin_percent,rationale)
 values(p_recovery_asset_id,p_policy_id,v_policy.currency_code,v_cost,v_median,round(v_floor,2),round(v_target,2),
  v_price,v_price-v_cost,v_margin,jsonb_build_object('method','cost_plus_margin_capped_by_recent_comparable',
  'minimum_margin_percent',v_policy.minimum_margin_percent,'target_margin_percent',v_policy.target_margin_percent,
  'comparable_window_days',30))
 returning recommendation_id into v_id;
 insert into public.mme_recovered_pricing_audit(recovery_asset_id,actor_user_id,action,new_state)
 values(p_recovery_asset_id,p_actor_user_id,'price_recommendation_generated',
 jsonb_build_object('recommendation_id',v_id,'price',v_price,'cost',v_cost,'margin',v_margin));
 return v_id;
end; $$;

create or replace function public.mme_recovered_inventory_approve_price(p_recommendation_id uuid,p_reviewer uuid,p_review_note text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v public.mme_recovered_price_recommendations%rowtype;
begin
 select * into v from public.mme_recovered_price_recommendations where recommendation_id=p_recommendation_id for update;
 if not found or v.recommendation_status<>'pending' or p_reviewer is null then raise exception 'Pending recommendation and reviewer required' using errcode='55000'; end if;
 update public.mme_recovered_price_recommendations set recommendation_status='approved',reviewed_by=p_reviewer,reviewed_at=now(),review_note=left(p_review_note,2000) where recommendation_id=p_recommendation_id;
 insert into public.mme_recovered_pricing_audit(recovery_asset_id,actor_user_id,action,prior_state,new_state)
 values(v.recovery_asset_id,p_reviewer,'price_recommendation_approved',jsonb_build_object('status','pending'),
 jsonb_build_object('status','approved','price',v.recommended_selling_price));
end; $$;

create or replace function public.mme_recovered_inventory_request_price_override(
 p_recovery_asset_id uuid,p_recommendation_id uuid,p_override_price numeric,p_reason text,p_requester uuid,p_currency_code text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v public.mme_recovered_price_recommendations%rowtype; v_id uuid;
begin
 if p_override_price<0 or p_reason is null or length(trim(p_reason))<5 or p_requester is null then raise exception 'Valid override price, reason and requester required' using errcode='22023'; end if;
 if p_recommendation_id is not null then
  select * into v from public.mme_recovered_price_recommendations where recommendation_id=p_recommendation_id and recovery_asset_id=p_recovery_asset_id;
  if not found then raise exception 'Recommendation does not match asset' using errcode='22023'; end if;
 end if;
 insert into public.mme_recovered_price_overrides(recovery_asset_id,recommendation_id,currency_code,
  prior_price,override_price,reason,requested_by)
 values(p_recovery_asset_id,p_recommendation_id,p_currency_code,
  case when p_recommendation_id is null then null else v.recommended_selling_price end,
  p_override_price,left(p_reason,1000),p_requester) returning override_id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_recovered_inventory_approve_override(p_override_id uuid,p_approver uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v public.mme_recovered_price_overrides%rowtype;
begin
 select * into v from public.mme_recovered_price_overrides where override_id=p_override_id for update;
 if not found or v.approval_status<>'pending' or p_approver is null or p_approver=v.requested_by then
  raise exception 'Independent approver required for pending override' using errcode='55000'; end if;
 update public.mme_recovered_price_overrides set approval_status='approved',approved_by=p_approver,approved_at=now() where override_id=p_override_id;
 insert into public.mme_recovered_pricing_audit(recovery_asset_id,actor_user_id,action,new_state)
 values(v.recovery_asset_id,p_approver,'price_override_approved',jsonb_build_object('override_id',p_override_id,'price',v.override_price));
end; $$;

create or replace function public.mme_recovered_inventory_create_markdown_plan(
 p_recovery_asset_id uuid,p_policy_id uuid,p_starting_price numeric,p_next_review_at timestamptz
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_policy public.mme_recovered_pricing_policies%rowtype; v_id uuid;
begin
 select * into v_policy from public.mme_recovered_pricing_policies where policy_id=p_policy_id and active;
 if not found or p_starting_price<0 or p_next_review_at<=now() then raise exception 'Active policy, valid price and future review time required' using errcode='22023'; end if;
 insert into public.mme_recovered_markdown_plans(recovery_asset_id,policy_id,starting_price,current_price,markdown_step_percent,maximum_markdown_percent,next_review_at)
 values(p_recovery_asset_id,p_policy_id,p_starting_price,p_starting_price,v_policy.markdown_step_percent,v_policy.maximum_markdown_percent,p_next_review_at)
 returning markdown_plan_id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_recovered_inventory_apply_markdown(p_markdown_plan_id uuid,p_actor_user_id uuid)
returns numeric language plpgsql security definer set search_path=pg_catalog,public as $$
declare v public.mme_recovered_markdown_plans%rowtype; p public.mme_recovered_pricing_policies%rowtype;
 v_cost numeric(14,2); v_floor numeric(14,2); v_new numeric(14,2); v_total numeric(7,3);
begin
 select * into v from public.mme_recovered_markdown_plans where markdown_plan_id=p_markdown_plan_id for update;
 if not found or v.plan_status<>'active' or v.next_review_at>now() then raise exception 'Markdown plan is not due and active' using errcode='55000'; end if;
 select * into p from public.mme_recovered_pricing_policies where policy_id=v.policy_id;
 select coalesce(sum(amount),0) into v_cost from public.mme_recovered_asset_cost_ledger where recovery_asset_id=v.recovery_asset_id and currency_code=p.currency_code;
 v_floor:=case when p.minimum_margin_percent=0 then v_cost else v_cost/(1-p.minimum_margin_percent/100) end;
 v_total:=((v.starting_price-v.current_price)/nullif(v.starting_price,0))*100;
 if v_total+v.markdown_step_percent>v.maximum_markdown_percent then
  update public.mme_recovered_markdown_plans set plan_status='completed',updated_at=now() where markdown_plan_id=p_markdown_plan_id;
  return v.current_price;
 end if;
 v_new:=greatest(round(v.current_price*(1-v.markdown_step_percent/100),2),ceil(v_floor*100)/100);
 if v_new>=v.current_price or v_new<v_floor then
  update public.mme_recovered_markdown_plans set plan_status='approval_required',updated_at=now() where markdown_plan_id=p_markdown_plan_id;
  return v.current_price;
 end if;
 update public.mme_recovered_markdown_plans set current_price=v_new,markdown_count=markdown_count+1,
  next_review_at=now()+(p.markdown_interval_days||' days')::interval,updated_at=now()
 where markdown_plan_id=p_markdown_plan_id;
 insert into public.mme_recovered_pricing_audit(recovery_asset_id,actor_user_id,action,prior_state,new_state)
 values(v.recovery_asset_id,p_actor_user_id,'markdown_applied',jsonb_build_object('price',v.current_price),
 jsonb_build_object('price',v_new,'floor',v_floor));
 return v_new;
end; $$;

create or replace function public.mme_recovered_inventory_queue_price_publication(
 p_recovery_asset_id uuid,p_idempotency_key text,p_selling_price numeric,p_currency_code text,p_condition_disclosure text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v public.mme_recovered_price_recommendations%rowtype; v_id uuid;
begin
 if p_selling_price<0 or p_condition_disclosure is null or length(trim(p_condition_disclosure))<10 then raise exception 'Price and meaningful condition disclosure required' using errcode='22023'; end if;
 if not exists(select 1 from public.mme_recovered_inventory_assets where recovery_asset_id=p_recovery_asset_id and asset_status='posted_to_inventory') then raise exception 'Asset must exist in authoritative inventory first' using errcode='55000'; end if;
 if not exists(select 1 from public.mme_recovered_price_recommendations where recovery_asset_id=p_recovery_asset_id and recommendation_status='approved' and recommended_selling_price=p_selling_price)
 and not exists(select 1 from public.mme_recovered_price_overrides where recovery_asset_id=p_recovery_asset_id and approval_status='approved' and override_price=p_selling_price) then
  raise exception 'Price must match an approved recommendation or override' using errcode='55000'; end if;
 insert into public.mme_recovered_price_publication_outbox(recovery_asset_id,idempotency_key,currency_code,selling_price,condition_disclosure)
 values(p_recovery_asset_id,p_idempotency_key,p_currency_code,p_selling_price,left(p_condition_disclosure,2000))
 on conflict(idempotency_key) do nothing returning publication_id into v_id;
 if v_id is null then select publication_id into v_id from public.mme_recovered_price_publication_outbox where idempotency_key=p_idempotency_key; end if;
 return v_id;
end; $$;

create or replace function public.mme_recovered_inventory_mark_price_published(p_publication_id uuid,p_catalog_transaction_reference text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 update public.mme_recovered_price_publication_outbox set publication_status='published',
  catalog_transaction_reference=p_catalog_transaction_reference,updated_at=now()
 where publication_id=p_publication_id and publication_status in ('pending','processing')
 and p_catalog_transaction_reference is not null;
 if not found then raise exception 'Pending publication and catalog transaction reference required' using errcode='55000'; end if;
end; $$;

create or replace view public.mme_recovered_inventory_profitability as
select a.recovery_asset_id,a.asset_reference,a.resale_classification,a.condition_grade,
 coalesce(c.recovered_cost,0) as recovered_cost,v.estimated_resale_value,
 v.estimated_net_recovery,
 case when v.estimated_resale_value>0 then round((v.estimated_net_recovery/v.estimated_resale_value)*100,3) else 0 end as estimated_margin_percent
from public.mme_inventory_recovery_assets a
left join lateral (select sum(amount) recovered_cost from public.mme_recovered_asset_cost_ledger l where l.recovery_asset_id=a.recovery_asset_id) c on true
left join lateral (select estimated_resale_value,estimated_net_recovery from public.mme_recovered_asset_valuations x where x.recovery_asset_id=a.recovery_asset_id order by valued_at desc limit 1) v on true;
revoke all on public.mme_recovered_inventory_profitability from public,anon,authenticated;
grant select on public.mme_recovered_inventory_profitability to service_role;

revoke all on function public.mme_recovered_inventory_generate_price(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_recovered_inventory_approve_price(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_recovered_inventory_request_price_override(uuid,uuid,numeric,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_recovered_inventory_approve_override(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_recovered_inventory_create_markdown_plan(uuid,uuid,numeric,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_recovered_inventory_apply_markdown(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_recovered_inventory_queue_price_publication(uuid,text,numeric,text,text) from public,anon,authenticated;
revoke all on function public.mme_recovered_inventory_mark_price_published(uuid,text) from public,anon,authenticated;
grant execute on all functions in schema public to service_role;
commit;