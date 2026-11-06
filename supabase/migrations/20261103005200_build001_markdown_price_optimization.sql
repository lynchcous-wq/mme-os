-- Build 001: auditable product-level markdown proposals with explicit approval and cost floor.
create table public.mme_price_markdown_proposals (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.mme_products(id) on delete restrict,
 current_price_cents bigint not null check(current_price_cents>=0),
 proposed_price_cents bigint not null check(proposed_price_cents>=0 and proposed_price_cents<current_price_cents),
 weighted_average_cost_cents bigint not null check(weighted_average_cost_cents>=0),
 markdown_percent numeric(6,2) not null check(markdown_percent>0 and markdown_percent<100),
 rule_key text not null check(rule_key in ('no_sales_90d','slow_sales_60d','excess_stock_cover')),
 evidence_snapshot jsonb not null,
 status text not null default 'pending_approval' check(status in ('pending_approval','approved','rejected','stale','cancelled')),
 requested_by_identity_id uuid not null,
 decided_by_identity_id uuid,
 decided_at timestamptz,
 decision_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(proposed_price_cents>=weighted_average_cost_cents)
);
create unique index mme_price_markdown_one_pending_product_idx
 on public.mme_price_markdown_proposals(product_id) where status='pending_approval';
create index mme_price_markdown_status_created_idx
 on public.mme_price_markdown_proposals(status,created_at desc);
alter table public.mme_price_markdown_proposals enable row level security;
revoke all on public.mme_price_markdown_proposals from public,anon,authenticated;
grant all on public.mme_price_markdown_proposals to service_role;

create or replace function public.mme_create_price_markdown_proposal(
 p_product_id uuid,p_requester_identity_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_product public.mme_products%rowtype; v_units90 bigint; v_units60 bigint;
 v_available bigint; v_cost bigint; v_cover numeric; v_rule text; v_pct numeric;
 v_price bigint; v_proposed bigint; v_id uuid;
begin
 if p_product_id is null or p_requester_identity_id is null then
  raise exception 'Product and requester are required' using errcode='22023'; end if;
 select * into v_product from public.mme_products where id=p_product_id and active=true and serialized=false for update;
 if not found then raise exception 'Active aggregate product not found' using errcode='P0002'; end if;
 select coalesce(sum(units_sold_90d),0),coalesce(sum(units_sold_60d),0),
  coalesce(sum(available_quantity),0),
  case when sum(available_quantity)=0 then null
   when sum(units_sold_30d)=0 then null
   else sum(available_quantity)::numeric/(sum(units_sold_30d)::numeric/30.0) end
 into v_units90,v_units60,v_available,v_cover
 from public.mme_inventory_sales_velocity_v where product_id=p_product_id;
 select round(sum(b.average_unit_cost_cents*b.on_hand_quantity)::numeric/nullif(sum(b.on_hand_quantity),0))::bigint
 into v_cost from public.mme_inventory_balances b where b.product_id=p_product_id and b.on_hand_quantity>0;
 if v_cost is null or v_available<=0 then
  raise exception 'Reliable cost and available stock are required' using errcode='23514'; end if;
 if exists(select 1 from public.mme_price_markdown_proposals where product_id=p_product_id and status='pending_approval') then
  raise exception 'A pending markdown proposal already exists' using errcode='23505'; end if;
 if v_units90=0 then v_rule:='no_sales_90d';v_pct:=15;
 elsif v_units60=0 then v_rule:='slow_sales_60d';v_pct:=10;
 elsif v_cover>90 then v_rule:='excess_stock_cover';v_pct:=5;
 else raise exception 'Product does not currently meet markdown criteria' using errcode='22023'; end if;
 v_price:=v_product.unit_price_cents;
 v_proposed:=greatest(v_cost,round(v_price*(1-v_pct/100.0))::bigint);
 if v_proposed>=v_price then raise exception 'No cost-protected markdown is available' using errcode='23514'; end if;
 insert into public.mme_price_markdown_proposals(product_id,current_price_cents,proposed_price_cents,
  weighted_average_cost_cents,markdown_percent,rule_key,evidence_snapshot,requested_by_identity_id)
 values(p_product_id,v_price,v_proposed,v_cost,round(100.0*(v_price-v_proposed)/v_price,2),v_rule,
  jsonb_build_object('units_sold_90d',v_units90,'units_sold_60d',v_units60,
   'available_quantity',v_available,'days_stock_cover_at_30d_velocity',v_cover,
   'calculated_at',now(),'pricing_scope','product_global'),
  p_requester_identity_id) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_decide_price_markdown_proposal(
 p_proposal_id uuid,p_approver_identity_id uuid,p_approve boolean,p_note text default null
) returns boolean language plpgsql security definer set search_path='' as $$
declare v public.mme_price_markdown_proposals%rowtype; v_product public.mme_products%rowtype; v_cost bigint;
begin
 if p_proposal_id is null or p_approver_identity_id is null or p_approve is null then
  raise exception 'Invalid markdown decision' using errcode='22023'; end if;
 select * into v from public.mme_price_markdown_proposals where id=p_proposal_id for update;
 if not found or v.status<>'pending_approval' then raise exception 'Proposal is not pending' using errcode='23514'; end if;
 if v.requested_by_identity_id=p_approver_identity_id then raise exception 'Requester cannot approve own markdown' using errcode='42501'; end if;
 if not p_approve then
  if p_note is null or length(btrim(p_note))<5 then raise exception 'Rejection reason is required' using errcode='22023'; end if;
  update public.mme_price_markdown_proposals set status='rejected',decided_by_identity_id=p_approver_identity_id,decided_at=now(),decision_note=left(btrim(p_note),1000),updated_at=now() where id=p_proposal_id;
  return true;
 end if;
 select * into v_product from public.mme_products where id=v.product_id for update;
 select round(sum(b.average_unit_cost_cents*b.on_hand_quantity)::numeric/nullif(sum(b.on_hand_quantity),0))::bigint
 into v_cost from public.mme_inventory_balances b where b.product_id=v.product_id and b.on_hand_quantity>0;
 if not found or v_product.unit_price_cents<>v.current_price_cents or v_cost is null
  or v_cost>v.proposed_price_cents or v_product.unit_price_cents<=v.proposed_price_cents then
  update public.mme_price_markdown_proposals set status='stale',decided_by_identity_id=p_approver_identity_id,decided_at=now(),decision_note='Price or cost changed; regenerate proposal.',updated_at=now() where id=p_proposal_id;
  return false;
 end if;
 update public.mme_products set unit_price_cents=v.proposed_price_cents,updated_at=now() where id=v.product_id;
 update public.mme_price_markdown_proposals set status='approved',decided_by_identity_id=p_approver_identity_id,decided_at=now(),decision_note=left(p_note,1000),updated_at=now() where id=p_proposal_id;
 return true;
end; $$;

revoke all on function public.mme_create_price_markdown_proposal(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_decide_price_markdown_proposal(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.mme_create_price_markdown_proposal(uuid,uuid) to service_role;
grant execute on function public.mme_decide_price_markdown_proposal(uuid,uuid,boolean,text) to service_role;
comment on table public.mme_price_markdown_proposals is 'Product-global markdown proposals. Approval changes catalog price only after current-price and weighted-average-cost revalidation. Trusted API must authenticate CEO-level approval.';
