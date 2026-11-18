-- Build 011.27 — private financing provider onboarding register
-- Internal merchant-partnership metadata only. Never store consumer applications or provider secrets.

create table if not exists public.mme_financing_provider_programs (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null unique check (provider_key in (
    'synchrony','bread-pay','citi','affirm','klarna','paypal-pay-later','acima','snap-finance'
  )),
  status text not null default 'research' check (status in (
    'research','eligible_to_apply','application_submitted','due_diligence',
    'approved','integration_testing','active','suspended','declined'
  )),
  merchant_id text,
  approved_products text[] not null default '{}',
  agreement_reference text,
  terms_verified_at timestamptz,
  settlement_profile_reference text,
  integration_mode text check (integration_mode is null or integration_mode in ('hosted','api','psp','in_store','hybrid')),
  internal_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists mme_financing_provider_programs_status_idx
  on public.mme_financing_provider_programs (status, provider_key);

insert into public.mme_financing_provider_programs (provider_key)
values ('synchrony'),('bread-pay'),('citi'),('affirm'),('klarna'),('paypal-pay-later'),('acima'),('snap-finance')
on conflict (provider_key) do nothing;

alter table public.mme_financing_provider_programs enable row level security;
revoke all on table public.mme_financing_provider_programs from public, anon, authenticated;

comment on table public.mme_financing_provider_programs is
  'Private MME merchant partnership onboarding state; contains no consumer application payloads, provider credentials or secrets.';
