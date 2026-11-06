-- Build 009.74: warranty renewal, retention and explicit customer acceptance
begin;
create table public.mme_warranty_renewal_campaigns (
 campaign_id uuid primary key default gen_random_uuid(),
 campaign_code text not null, campaign_version text not null,
 lead_days integer not null check(lead_days in (30,60,90)),
 status text not null default 'draft' check(status in ('draft','approved','active','paused','retired')),
 approved_by uuid, approved_at timestamptz, starts_at timestamptz, ends_at timestamptz,
 created_at timestamptz not null default now(), unique(campaign_code,campaign_version),
 check(ends_at is null or starts_at is null or ends_at>starts_at)
);
create table public.mme_warranty_renewal_opportunities (
 opportunity_id uuid primary key default gen_random_uuid(),
 lifecycle_id uuid not null references public.mme_warranty_lifecycle_records(lifecycle_id) on delete restrict,
 customer_identity_id uuid not null, coverage_ends_at timestamptz not null,
 horizon_days integer not null check(horizon_days in (30,60,90)),
 status text not null default 'identified' check(status in ('identified','eligible','offer_created','presented','accepted','declined','expired','ineligible','converted')),
 campaign_id uuid references public.mme_warranty_renewal_campaigns(campaign_id) on delete restrict,
 last_evaluated_at timestamptz not null default now(), idempotency_key text not null unique,
 unique(lifecycle_id,horizon_days)
);
create index mme_warranty_renewal_opportunities_queue_idx on public.mme_warranty_renewal_opportunities(status,coverage_ends_at);
create table public.mme_warranty_renewal_pricing_snapshots (
 pricing_snapshot_id uuid primary key default gen_random_uuid(),
 opportunity_id uuid not null references public.mme_warranty_renewal_opportunities(opportunity_id) on delete restrict,
 offer_id uuid references public.mme_warranty_renewal_offers(offer_id) on delete restrict,
 product_cost numeric(14,2), service_reserve numeric(14,2), provider_cost numeric(14,2),
 customer_price numeric(14,2) not null check(customer_price>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 gross_margin numeric(14,2), margin_pct numeric(8,4), pricing_rule_version text not null,
 calculated_at timestamptz not null default now(), approved_by uuid, approved_at timestamptz,
 source_reference text not null, idempotency_key text not null unique
);
create table public.mme_warranty_renewal_decisions (
 decision_id uuid primary key default gen_random_uuid(),
 offer_id uuid not null references public.mme_warranty_renewal_offers(offer_id) on delete restrict,
 customer_identity_id uuid not null,
 decision text not null check(decision in ('accepted','declined','withdrawn')),
 decided_at timestamptz not null default now(), acceptance_terms_version text,
 acceptance_evidence_reference text not null, channel text not null check(channel in ('customer_portal','pos','verified_support')),
 authenticated_actor_reference text not null, idempotency_key text not null unique,
 check(decision<>'accepted' or acceptance_terms_version is not null)
);
create unique index mme_warranty_renewal_one_acceptance_idx on public.mme_warranty_renewal_decisions(offer_id) where decision='accepted';
create table public.mme_warranty_renewal_orders (
 renewal_order_id uuid primary key default gen_random_uuid(),
 offer_id uuid not null references public.mme_warranty_renewal_offers(offer_id) on delete restrict,
 decision_id uuid not null unique references public.mme_warranty_renewal_decisions(decision_id) on delete restrict,
 customer_identity_id uuid not null, status text not null default 'awaiting_payment' check(status in ('awaiting_payment','payment_pending','paid','payment_failed','cancelled','fulfilled','refunded')),
 amount numeric(14,2) not null check(amount>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 payment_provider_reference text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 idempotency_key text not null unique
);
create table public.mme_warranty_renewal_payment_attempts (
 payment_attempt_id uuid primary key default gen_random_uuid(),
 renewal_order_id uuid not null references public.mme_warranty_renewal_orders(renewal_order_id) on delete restrict,
 provider_code text not null, provider_payment_reference text,
 status text not null check(status in ('created','requires_customer_action','processing','succeeded','failed','cancelled','unknown')),
 amount numeric(14,2) not null check(amount>=0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 failure_code text, attempted_at timestamptz not null default now(), idempotency_key text not null unique
);
create table public.mme_warranty_renewal_retention_facts (
 retention_fact_id uuid primary key default gen_random_uuid(),
 period_start date not null, period_end date not null, cohort_code text not null,
 eligible_count bigint not null check(eligible_count>=0), presented_count bigint not null check(presented_count>=0),
 accepted_count bigint not null check(accepted_count>=0), converted_count bigint not null check(converted_count>=0),
 realization text not null check(realization in ('actual','projection')),
 model_version text, source_reference text not null, currency_code text,
 recorded_at timestamptz not null default now(), idempotency_key text not null unique,
 check(period_end>=period_start), check(presented_count<=eligible_count),
 check(accepted_count<=presented_count), check(converted_count<=accepted_count),
 check(realization<>'projection' or model_version is not null)
);
do $$ declare t text; begin foreach t in array array['mme_warranty_renewal_campaigns','mme_warranty_renewal_opportunities','mme_warranty_renewal_pricing_snapshots','mme_warranty_renewal_decisions','mme_warranty_renewal_orders','mme_warranty_renewal_payment_attempts','mme_warranty_renewal_retention_facts'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from public,anon,authenticated',t); end loop; end $$;
grant select,insert,update on public.mme_warranty_renewal_campaigns,public.mme_warranty_renewal_opportunities,public.mme_warranty_renewal_pricing_snapshots,public.mme_warranty_renewal_orders,public.mme_warranty_renewal_payment_attempts to service_role;
grant select,insert on public.mme_warranty_renewal_decisions,public.mme_warranty_renewal_retention_facts to service_role;
revoke update,delete,truncate on public.mme_warranty_renewal_decisions from public,anon,authenticated,service_role;
commit;