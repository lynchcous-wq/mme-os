-- Build 010.94: shipping package profiles for carrier-rated fulfillment.
-- Additive only. Products without complete shipping profiles remain pickup-only.

alter table public.mme_products
  add column if not exists shipping_weight_oz integer,
  add column if not exists shipping_length_in numeric(8,2),
  add column if not exists shipping_width_in numeric(8,2),
  add column if not exists shipping_height_in numeric(8,2),
  add column if not exists shipping_hazmat boolean not null default false;

alter table public.mme_products
  add constraint mme_products_shipping_weight_positive
    check (shipping_weight_oz is null or shipping_weight_oz > 0),
  add constraint mme_products_shipping_length_positive
    check (shipping_length_in is null or shipping_length_in > 0),
  add constraint mme_products_shipping_width_positive
    check (shipping_width_in is null or shipping_width_in > 0),
  add constraint mme_products_shipping_height_positive
    check (shipping_height_in is null or shipping_height_in > 0);

comment on column public.mme_products.shipping_weight_oz is
  'Verified shipping weight in ounces; required for carrier-rated shipping.';
comment on column public.mme_products.shipping_hazmat is
  'True when carrier handling restrictions apply; shipping is blocked until an eligible service is confirmed.';
