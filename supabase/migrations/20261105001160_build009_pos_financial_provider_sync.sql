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
create or replace function public.mme_pos_start_financial_sync_run(
 p_connector_id uuid,p_worker_person_id uuid,p_window_started_at timestamptz
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_run uuid;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 if v_connector.status<>'active' then raise exception 'Financial connector is not active' using errcode='55000'; end if;
 if not public.mme_pos_authorize_hardware_action(p_worker_person_id,'pos.finance.report.import',v_connector.location_id) then
  raise exception 'Financial sync permission denied' using errcode='42501';
 end if;
 insert into public.mme_pos_financial_sync_runs(connector_id,location_id,provider_key,window_started_at,worker_person_id)
 values(v_connector.id,v_connector.location_id,v_connector.provider_key,p_window_started_at,p_worker_person_id)
 on conflict do nothing returning id into v_run;
 return v_run;
end;
$$;
