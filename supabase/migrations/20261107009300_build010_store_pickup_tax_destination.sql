-- Build 010.93: store pickup tax destination details.
-- Additive and fail-closed: checkout remains unavailable until a location is fully configured.

alter table public.mme_store_locations
  add column if not exists address_line1 text,
  add column if not exists address_line2 text,
  add column if not exists city text,
  add column if not exists region text,
  add column if not exists postal_code text,
  add column if not exists country_code text;

comment on column public.mme_store_locations.address_line1 is
  'Physical pickup/tax destination address; required before customer pickup checkout can be priced.';
comment on column public.mme_store_locations.country_code is
  'ISO 3166-1 alpha-2 country code used for tax destination validation.';
