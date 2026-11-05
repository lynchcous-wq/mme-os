-- Build 001: private storage bucket for serialized-device inspection evidence.
-- Binary uploads are reserved for trusted server code; browser roles receive no
-- storage.objects policy and cannot read or write inspection evidence directly.
begin;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'mme-inspection-evidence',
  'mme-inspection-evidence',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic']::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Explicitly remove any pre-existing browser policies for this dedicated bucket.
-- The trusted service_role bypasses Storage RLS; anon/authenticated remain denied.
drop policy if exists mme_inspection_evidence_public_read on storage.objects;
drop policy if exists mme_inspection_evidence_authenticated_read on storage.objects;
drop policy if exists mme_inspection_evidence_authenticated_insert on storage.objects;
drop policy if exists mme_inspection_evidence_authenticated_update on storage.objects;
drop policy if exists mme_inspection_evidence_authenticated_delete on storage.objects;


commit;
