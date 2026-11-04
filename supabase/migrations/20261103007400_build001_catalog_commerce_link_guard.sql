begin;

-- Explicit, nullable bridge: existing commerce products are not auto-linked
-- merely because their SKUs happen to match catalog SKUs.
alter table public.mme_products
  add column catalog_product_id uuid
  references public.products(id) on delete restrict;

create unique index mme_products_catalog_product_id_uidx
  on public.mme_products(catalog_product_id)
  where catalog_product_id is not null;

create index mme_products_catalog_sale_lookup_idx
  on public.mme_products(active, catalog_product_id);

create table public.mme_product_catalog_link_events (
  id bigint generated always as identity primary key,
  commerce_product_id uuid not null references public.mme_products(id) on delete restrict,
  catalog_product_id uuid not null references public.products(id) on delete restrict,
  event_type text not null check (event_type in ('linked','relinked','unlinked')),
  actor_user_id uuid references auth.users(id) on delete set null,
  db_session_user text not null default session_user,
  created_at timestamptz not null default now()
);

alter table public.mme_product_catalog_link_events enable row level security;
revoke all on public.mme_product_catalog_link_events from public, anon, authenticated;
grant all on public.mme_product_catalog_link_events to service_role;

create or replace function public.mme_validate_catalog_product_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_catalog_sku text;
  v_old_catalog_id uuid;
  v_actor uuid;
begin
  if new.catalog_product_id is not distinct from old.catalog_product_id
     and new.sku is not distinct from old.sku then
    return new;
  end if;

  if new.catalog_product_id is not null then
    select p.sku into v_catalog_sku
    from public.products p
    where p.id = new.catalog_product_id
    for key share;

    if not found then
      raise exception 'Catalog product does not exist' using errcode = '23503';
    end if;

    if v_catalog_sku is distinct from new.sku then
      raise exception 'Linked catalog and commerce SKUs must match exactly' using errcode = '23514';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    v_old_catalog_id := old.catalog_product_id;
    if old.catalog_product_id is distinct from new.catalog_product_id then
      v_actor := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
      insert into public.mme_product_catalog_link_events(
        commerce_product_id, catalog_product_id, event_type, actor_user_id
      )
      values (
        new.id,
        coalesce(new.catalog_product_id, old.catalog_product_id),
        case
          when old.catalog_product_id is null then 'linked'
          when new.catalog_product_id is null then 'unlinked'
          else 'relinked'
        end,
        v_actor
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger mme_products_validate_catalog_link
before insert or update of catalog_product_id, sku on public.mme_products
for each row execute function public.mme_validate_catalog_product_link();

-- This guard runs inside every order-line insert path, including aggregate
-- and mixed/serialized carts. A failed guard rolls back the order transaction.
create or replace function public.mme_require_published_catalog_product()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_catalog_status text;
begin
  select cp.catalog_status into v_catalog_status
  from public.mme_products mp
  join public.products cp on cp.id = mp.catalog_product_id
  where mp.id = new.product_id
    and mp.active = true
  for key share of mp, cp;

  if not found or v_catalog_status <> 'published' then
    raise exception 'Product is not eligible for public sale: catalog link must exist, be published, and commerce product must be active'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger mme_order_lines_require_published_catalog
before insert on public.mme_order_lines
for each row execute function public.mme_require_published_catalog_product();

comment on column public.mme_products.catalog_product_id is
  'Explicit link to the approved product catalog. Null means not eligible for public checkout.';
comment on table public.mme_product_catalog_link_events is
  'Append-only-by-convention audit trail of catalog-to-commerce product link changes.';

commit;
