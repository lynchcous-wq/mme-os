begin;
create table public.mme_pos_financial_sync_runs (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 provider_key text not null,
 status text not null default 'processing' check(status in ('processing','partial','completed','failed','skipped')),
 window_started_at timestamptz not null,
 next_cursor_value text,
 records_fetched integer not null default 0 check(records_fetched>=0),
 records_staged integer not null default 0 check(records_staged>=0),
 records_ignored integer not null default 0 check(records_ignored>=0),
 batches_staged integer not null default 0 check(batches_staged>=0),
 safe_error_code text,
 started_at timestamptz not null default now(),
 finished_at timestamptz,
 worker_person_id uuid not null
);
create index mme_pos_financial_sync_runs_location_idx on public.mme_pos_financial_sync_runs(location_id,started_at desc);
create unique index mme_pos_financial_sync_one_active_connector_idx on public.mme_pos_financial_sync_runs(connector_id) where status='processing';
alter table public.mme_pos_financial_sync_runs enable row level security;
revoke all on public.mme_pos_financial_sync_runs from public,anon,authenticated;
commit;
