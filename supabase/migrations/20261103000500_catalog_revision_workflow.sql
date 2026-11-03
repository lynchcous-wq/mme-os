begin;

-- Add a controlled return-for-correction state without rewriting prior migrations.
alter table public.products
  drop constraint if exists products_catalog_status_check;

alter table public.products
  add constraint products_catalog_status_check
  check (catalog_status in ('draft','pending_approval','changes_requested','published','archived'));

alter table public.products
  add column if not exists correction_notes text;

alter table public.products
  add constraint products_correction_notes_length_check
  check (correction_notes is null or char_length(correction_notes) <= 3000);

create index if not exists products_creator_status_updated_idx
  on public.products(created_by, catalog_status, updated_at desc);

comment on column public.products.correction_notes is
  'Reviewer instructions for the creator. Cleared when a corrected revision is resubmitted.';

commit;
