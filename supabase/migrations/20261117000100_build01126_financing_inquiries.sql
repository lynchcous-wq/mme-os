-- Build 011.26 — public financing inquiry intake
-- Stores only a customer-requested contact inquiry. This is NOT a credit application.
-- Do not collect SSNs, dates of birth, bank details, income, credit scores, or identity documents here.

create table if not exists public.mme_financing_inquiries (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  email text not null check (char_length(email) between 3 and 320),
  phone text not null check (char_length(phone) between 7 and 32),
  product_interest text not null check (product_interest in ('television','computer','phone_tablet','wearable','accessories','multiple','not_sure')),
  estimated_budget text not null check (estimated_budget in ('under_250','250_499','500_999','1000_1999','2000_plus','not_sure')),
  preferred_contact text not null check (preferred_contact in ('email','phone','either')),
  consent_to_contact boolean not null check (consent_to_contact = true),
  status text not null default 'new' check (status in ('new','in_review','contacted','closed','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists mme_financing_inquiries_status_created_idx
  on public.mme_financing_inquiries (status, created_at desc);

alter table public.mme_financing_inquiries enable row level security;

-- No browser role may read, insert, update, or delete financing inquiries.
-- Server route uses the private service-role key only after origin, rate-limit,
-- validation, and consent checks. Keep that key out of client bundles.
revoke all on table public.mme_financing_inquiries from public, anon, authenticated;

comment on table public.mme_financing_inquiries is
  'Customer-requested financing contact inquiries only; not a credit application or lender decision record.';
