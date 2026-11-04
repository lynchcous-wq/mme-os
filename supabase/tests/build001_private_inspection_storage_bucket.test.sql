begin;
select plan(5);

select is(
  (select public::text from storage.buckets where id='mme-inspection-evidence'),
  'false',
  'inspection evidence bucket is private'
);

select is(
  (select file_size_limit::bigint from storage.buckets where id='mme-inspection-evidence'),
  10485760::bigint,
  'inspection evidence bucket enforces a 10 MB file limit'
);

select ok(
  (select allowed_mime_types @> array['image/jpeg','image/png','image/webp','image/heic']::text[]
     from storage.buckets where id='mme-inspection-evidence'),
  'inspection evidence bucket restricts image formats'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname like 'mme_inspection_evidence_%'
  ),
  'no browser-facing bucket-specific object policies are installed'
);

select ok(
  exists (select 1 from storage.buckets where id='mme-inspection-evidence'),
  'dedicated inspection evidence bucket exists'
);

select * from finish();
rollback;
