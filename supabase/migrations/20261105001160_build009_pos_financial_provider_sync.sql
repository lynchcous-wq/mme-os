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
revoke all on public.mme_pos_financial_sync_runs from public,anon,authenticated;\ngrant select,insert,update on public.mme_pos_financial_sync_runs to service_role;\nrevoke delete,truncate on public.mme_pos_financial_sync_runs from service_role;
commit;
create or replace function public.mme_pos_start_financial_sync_run(
 p_connector_id uuid,p_worker_person_id uuid,p_window_started_at timestamptz
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_run uuid;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found then raise exception 'Financial connector not found' using errcode='P0002'; end if;
 update public.mme_pos_financial_sync_runs set status='failed',safe_error_code='STALE_RUN_RECOVERED',finished_at=now()
  where connector_id=p_connector_id and status='processing' and started_at<now()-interval '15 minutes';
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
create or replace function public.mme_pos_finish_financial_sync_run(
 p_run_id uuid,p_worker_person_id uuid,p_status text,p_cursor_value text,
 p_records_fetched integer,p_records_staged integer,p_records_ignored integer,
 p_batches_staged integer,p_safe_error_code text default null
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_run public.mme_pos_financial_sync_runs%rowtype;
begin
 select * into v_run from public.mme_pos_financial_sync_runs where id=p_run_id for update;
 if not found then raise exception 'Financial sync run not found' using errcode='P0002'; end if;
 if v_run.status<>'processing' then return false; end if;
 if v_run.worker_person_id<>p_worker_person_id or
  not public.mme_pos_authorize_hardware_action(p_worker_person_id,'pos.finance.report.import',v_run.location_id) then
  raise exception 'Financial sync run permission denied' using errcode='42501';
 end if;
 if p_status not in ('partial','completed','failed','skipped') or
  p_records_fetched<0 or p_records_staged<0 or p_records_ignored<0 or p_batches_staged<0 then
  raise exception 'Invalid financial sync result' using errcode='22023';
 end if;
 update public.mme_pos_financial_sync_runs set status=p_status,next_cursor_value=p_cursor_value,
  records_fetched=p_records_fetched,records_staged=p_records_staged,records_ignored=p_records_ignored,
  batches_staged=p_batches_staged,safe_error_code=p_safe_error_code,finished_at=now()
 where id=p_run_id;
 if p_status in ('partial','completed') then
  insert into public.mme_pos_financial_import_cursors(connector_id,location_id,cursor_value,cursor_updated_at,updated_at)
  values(v_run.connector_id,v_run.location_id,p_cursor_value,now(),now())
  on conflict(connector_id) do update set cursor_value=excluded.cursor_value,
   cursor_updated_at=excluded.cursor_updated_at,updated_at=excluded.updated_at;
  update public.mme_pos_financial_connectors set last_attempt_at=now(),
   last_success_at=case when p_status='completed' then now() else last_success_at end,
   last_error_code=null,updated_at=now() where id=v_run.connector_id;
  insert into public.mme_pos_financial_connector_events(connector_id,location_id,actor_person_id,event_type,reason,metadata)
  values(v_run.connector_id,v_run.location_id,p_worker_person_id,'cursor_advanced',
   'Provider page was durably staged before cursor advancement.',
   jsonb_build_object('run_id',p_run_id,'status',p_status,'records_fetched',p_records_fetched,
    'records_staged',p_records_staged,'records_ignored',p_records_ignored,'batches_staged',p_batches_staged));
 else
  update public.mme_pos_financial_connectors set last_attempt_at=now(),
   last_error_code=coalesce(p_safe_error_code,'PROVIDER_SYNC_FAILED'),updated_at=now()
  where id=v_run.connector_id;
 end if;
 return true;
end;
$$;

revoke all on function public.mme_pos_start_financial_sync_run(uuid,uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_pos_finish_financial_sync_run(uuid,uuid,text,text,integer,integer,integer,integer,text) from public,anon,authenticated;
grant execute on function public.mme_pos_start_financial_sync_run(uuid,uuid,timestamptz) to service_role;
grant execute on function public.mme_pos_finish_financial_sync_run(uuid,uuid,text,text,integer,integer,integer,integer,text) to service_role;
commit;
