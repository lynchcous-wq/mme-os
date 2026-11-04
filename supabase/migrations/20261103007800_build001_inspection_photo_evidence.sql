-- Build 001: inspection photo evidence metadata.
-- Binary files must be uploaded to a private storage bucket by a trusted server.
-- This table stores object metadata only; never store public image URLs or raw files here.
begin;

create table public.mme_inspection_photo_evidence (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null
    references public.mme_inventory_inspections(id) on delete restrict,
  storage_bucket text not null default 'mme-inspection-evidence'
    check (storage_bucket = 'mme-inspection-evidence'),
  storage_object_key text not null
    check (
      storage_object_key = btrim(storage_object_key)
      and length(storage_object_key) between 10 and 512
      and storage_object_key !~ '(^/|\.\.|\\\\|[?#])'
    ),
  mime_type text not null
    check (mime_type in ('image/jpeg','image/png','image/webp','image/heic')),
  file_size_bytes integer not null
    check (file_size_bytes between 1 and 10485760),
  sha256_hex text not null
    check (sha256_hex ~ '^[a-f0-9]{64}$'),
  caption text not null default '' check (length(caption) <= 500),
  uploaded_by_identity_id uuid not null,
  created_at timestamptz not null default now(),
  unique(storage_bucket, storage_object_key)
);

create index mme_inspection_photo_evidence_inspection_idx
  on public.mme_inspection_photo_evidence(inspection_id,created_at);

alter table public.mme_inspection_photo_evidence enable row level security;
revoke all on public.mme_inspection_photo_evidence from public,anon,authenticated;
grant all on public.mme_inspection_photo_evidence to service_role;

create or replace function public.mme_register_inspection_photo_evidence(
  p_inspection_id uuid,
  p_storage_object_key text,
  p_mime_type text,
  p_file_size_bytes integer,
  p_sha256_hex text,
  p_caption text,
  p_actor_identity_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_inspection_id is null or p_actor_identity_id is null
     or p_storage_object_key is null
     or p_mime_type not in ('image/jpeg','image/png','image/webp','image/heic')
     or p_file_size_bytes not between 1 and 10485760
     or p_sha256_hex is null or p_sha256_hex !~ '^[a-f0-9]{64}$'
     or p_caption is null or length(p_caption)>500 then
    raise exception 'Invalid inspection photo evidence metadata' using errcode='22023';
  end if;

  perform 1 from public.mme_inventory_inspections
   where id=p_inspection_id;
  if not found then
    raise exception 'Inspection not found' using errcode='P0002';
  end if;

  insert into public.mme_inspection_photo_evidence(
    inspection_id,storage_object_key,mime_type,file_size_bytes,
    sha256_hex,caption,uploaded_by_identity_id
  ) values (
    p_inspection_id,btrim(p_storage_object_key),p_mime_type,p_file_size_bytes,
    p_sha256_hex,btrim(p_caption),p_actor_identity_id
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.mme_register_inspection_photo_evidence(uuid,text,text,integer,text,text,uuid)
  from public,anon,authenticated;
grant execute on function public.mme_register_inspection_photo_evidence(uuid,text,text,integer,text,text,uuid)
  to service_role;

comment on table public.mme_inspection_photo_evidence is
  'Private inspection photo metadata. Files belong in a private storage bucket and must be served with short-lived signed URLs.';

commit;
