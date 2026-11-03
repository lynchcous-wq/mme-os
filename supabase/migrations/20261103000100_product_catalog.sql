begin;
create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.product_categories(id) on delete restrict,
  name text not null,
  slug text not null unique,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.product_categories(id) on delete restrict,
  sku text not null unique,
  slug text not null unique,
  name text not null,
  brand text,
  manufacturer text,
  model_number text,
  upc_ean text,
  description text,
  condition text not null default 'inspection_required'
    check (condition in ('new','open_box','like_new','refurbished','used_excellent','used_good','used_fair','parts_only','damaged','inspection_required')),
  tracking_mode text not null default 'quantity'
    check (tracking_mode in ('quantity','serialized')),
  catalog_status text not null default 'draft'
    check (catalog_status in ('draft','pending_approval','published','archived')),
  specifications jsonb not null default '{}'::jsonb
    check (jsonb_typeof(specifications) = 'object'),
  warranty_summary text,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  published_at timestamptz,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (catalog_status <> 'published' or (approved_by is not null and approved_at is not null and published_at is not null))
);
create index products_category_status_idx on public.products(category_id, catalog_status);
create index products_brand_model_idx on public.products(brand, model_number);
create table public.product_media (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  media_type text not null check (media_type in ('image','video')),
  storage_key text,
  external_url text,
  alt_text text,
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  check ((storage_key is not null and external_url is null) or (storage_key is null and external_url is not null))
);
create table public.product_catalog_events (
  id bigint generated always as identity primary key,
  product_id uuid not null references public.products(id) on delete restrict,
  event_type text not null,
  actor_id uuid references auth.users(id) on delete set null,
  product_version integer not null,
  event_data jsonb not null default '{}'::jsonb check (jsonb_typeof(event_data) = 'object'),
  created_at timestamptz not null default now()
);
alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.product_media enable row level security;
alter table public.product_catalog_events enable row level security;
insert into public.product_categories (name, slug, sort_order) values
  ('Televisions','televisions',10),
  ('Laptops','laptops',20),
  ('Tablets','tablets',30),
  ('Cellphones','cellphones',40),
  ('Smartwatches','smartwatches',50),
  ('Accessories','accessories',60),
  ('Audio','audio',70),
  ('Gaming','gaming',80),
  ('Smart Home','smart-home',90),
  ('Services and Subscriptions','services-subscriptions',100)
on conflict (slug) do nothing;
comment on table public.products is 'Product/model catalog only. Physical units, stock, reservations, COGS and selling prices are owned by separate MME OS modules.';
commit;
