begin;

alter table public.products
  drop constraint if exists products_catalog_status_check;

alter table public.products
  add constraint products_catalog_status_check
  check (catalog_status in ('draft','pending_approval','changes_requested','published','archived'));

alter table public.products
  add column if not exists correction_notes text,
  add column if not exists returned_by uuid references auth.users(id) on delete set null,
  add column if not exists returned_at timestamptz;

create table if not exists public.product_catalog_revisions (
  id bigint generated always as identity primary key,
  product_id uuid not null references public.products(id) on delete restrict,
  product_version integer not null,
  actor_id uuid references auth.users(id) on delete set null,
  revision_reason text not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  created_at timestamptz not null default now(),
  unique(product_id, product_version)
);

alter table public.product_catalog_revisions enable row level security;
alter table public.product_catalog_revisions force row level security;

create index if not exists product_catalog_revisions_product_version_idx
  on public.product_catalog_revisions(product_id, product_version desc);

create function public.mme_catalog_revisions_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'Product catalog revisions are append-only';
end;
$$;

drop trigger if exists product_catalog_revisions_no_update_delete on public.product_catalog_revisions;
create trigger product_catalog_revisions_no_update_delete
before update or delete on public.product_catalog_revisions
for each row execute function public.mme_catalog_revisions_immutable();

comment on column public.products.correction_notes is
  'Reviewer-provided correction instructions; cleared only after a successful employee resubmission.';
comment on table public.product_catalog_revisions is
  'Append-only snapshots of product data before employee revisions. Physical stock, costs, prices and payment data are excluded.';

commit;
