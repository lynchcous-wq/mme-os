-- Build 009.35 — POS Financial Import Worker, Lease Queue & Verified Webhook Intake
begin;

create table public.mme_pos_financial_import_jobs (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.mme_pos_financial_import_batches(id) on delete restrict,
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 status text not null default 'queued' check(status in ('queued','processing','completed','completed_with_quarantine','retry_wait','dead_letter','cancelled')),
 attempts integer not null default 0 check(attempts>=0),
 max_attempts integer not null default 8 check(max_attempts between 1 and 20),
 available_at timestamptz not null default now(),
 lease_token uuid,
 lease_expires_at timestamptz,
 last_error_code text,
 last_error_safe text check(last_error_safe is null or length(last_error_safe)<=500),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 completed_at timestamptz,
 unique(batch_id)
);
create index mme_pos_financial_import_jobs_queue_idx on public.mme_pos_financial_import_jobs(status,available_at,created_at);
create index mme_pos_financial_import_jobs_lease_idx on public.mme_pos_financial_import_jobs(lease_expires_at) where status='processing';

create table public.mme_pos_financial_worker_events (
 id uuid primary key default gen_random_uuid(),
 job_id uuid references public.mme_pos_financial_import_jobs(id) on delete restrict,
 batch_id uuid references public.mme_pos_financial_import_batches(id) on delete restrict,
 location_id uuid not null,
 worker_person_id uuid not null,
 event_type text not null check(event_type in ('job_enqueued','job_claimed','job_completed','job_retry_scheduled','job_dead_lettered','lease_recovered','job_cancelled')),
 reason text not null check(length(btrim(reason)) between 3 and 1000),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_financial_worker_events_idx on public.mme_pos_financial_worker_events(location_id,occurred_at desc);

create table public.mme_pos_financial_webhook_events (
 id uuid primary key default gen_random_uuid(),
 connector_id uuid not null references public.mme_pos_financial_connectors(id) on delete restrict,
 location_id uuid not null,
 provider_key text not null check(provider_key in ('stripe')),
 provider_event_id text not null check(length(btrim(provider_event_id)) between 1 and 240),
 provider_event_type text not null check(length(btrim(provider_event_type)) between 1 and 120),
 provider_account_reference text,
 payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
 status text not null default 'received' check(status in ('received','queued','processed','ignored','failed')),
 received_at timestamptz not null default now(),
 processed_at timestamptz,
 safe_error_code text,
 unique(connector_id,provider_event_id)
);
create index mme_pos_financial_webhook_events_queue_idx on public.mme_pos_financial_webhook_events(status,received_at);

alter table public.mme_pos_financial_import_jobs enable row level security;
alter table public.mme_pos_financial_worker_events enable row level security;
alter table public.mme_pos_financial_webhook_events enable row level security;
revoke all on public.mme_pos_financial_import_jobs,public.mme_pos_financial_worker_events,public.mme_pos_financial_webhook_events from public,anon,authenticated;
grant select,insert,update on public.mme_pos_financial_import_jobs to service_role;
grant select,insert on public.mme_pos_financial_worker_events to service_role;
grant select,insert,update on public.mme_pos_financial_webhook_events to service_role;
revoke delete,truncate on public.mme_pos_financial_import_jobs,public.mme_pos_financial_worker_events,public.mme_pos_financial_webhook_events from service_role;

create or replace function public.mme_pos_enqueue_financial_import_jobs(
 p_actor_person_id uuid,p_limit integer default 100
) returns integer language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_row record; v_count integer:=0;
begin
 if p_limit<1 or p_limit>500 then raise exception 'Enqueue limit must be between 1 and 500' using errcode='22023'; end if;
 for v_row in
  select b.id batch_id,b.connector_id,b.location_id
  from public.mme_pos_financial_import_batches b
  join public.mme_pos_financial_connectors c on c.id=b.connector_id and c.status='active'
  where b.status='staged'
   and public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.finance.report.import',b.location_id)
   and not exists(select 1 from public.mme_pos_financial_import_jobs j where j.batch_id=b.id)
  order by b.staged_at
  limit p_limit
 loop
  insert into public.mme_pos_financial_import_jobs(batch_id,connector_id,location_id)
  values(v_row.batch_id,v_row.connector_id,v_row.location_id)
  on conflict(batch_id) do nothing;
  if found then
   insert into public.mme_pos_financial_worker_events(job_id,batch_id,location_id,worker_person_id,event_type,reason)
   select id,batch_id,location_id,p_actor_person_id,'job_enqueued','Staged financial import batch entered the worker queue.'
   from public.mme_pos_financial_import_jobs where batch_id=v_row.batch_id;
   v_count:=v_count+1;
  end if;
 end loop;
 return v_count;
end;
$$;

create or replace function public.mme_pos_claim_financial_import_job(
 p_worker_person_id uuid,p_lease_seconds integer default 180
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_job public.mme_pos_financial_import_jobs%rowtype; v_token uuid:=gen_random_uuid(); v_recovered boolean:=false;
begin
 if p_lease_seconds<30 or p_lease_seconds>900 then raise exception 'Lease must be 30 to 900 seconds' using errcode='22023'; end if;
 select * into v_job from public.mme_pos_financial_import_jobs
 where ((status in ('queued','retry_wait') and available_at<=now())
    or (status='processing' and lease_expires_at<now()))
  and attempts<max_attempts
  order by available_at,created_at
  for update skip locked limit 1;
 if not found then return null; end if;
 v_recovered:=v_job.status='processing';
 update public.mme_pos_financial_import_jobs set status='processing',attempts=attempts+1,
  lease_token=v_token,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),updated_at=now()
 where id=v_job.id returning * into v_job;
 insert into public.mme_pos_financial_worker_events(job_id,batch_id,location_id,worker_person_id,event_type,reason,metadata)
 values(v_job.id,v_job.batch_id,v_job.location_id,p_worker_person_id,
  case when v_recovered then 'lease_recovered' else 'job_claimed' end,
  case when v_recovered then 'Expired worker lease recovered for idempotent retry.' else 'Worker claimed financial import job.' end,
  jsonb_build_object('attempt',v_job.attempts));
 return jsonb_build_object('job_id',v_job.id,'batch_id',v_job.batch_id,'connector_id',v_job.connector_id,
  'location_id',v_job.location_id,'lease_token',v_token,'attempt',v_job.attempts);
end;
$$;

create or replace function public.mme_pos_finish_financial_import_job(
 p_job_id uuid,p_lease_token uuid,p_worker_person_id uuid,p_success boolean,
 p_error_code text default null,p_safe_error text default null
) returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_job public.mme_pos_financial_import_jobs%rowtype; v_batch_status text; v_next text;
begin
 select * into v_job from public.mme_pos_financial_import_jobs where id=p_job_id for update;
 if not found or v_job.status<>'processing' or v_job.lease_token is distinct from p_lease_token then
  raise exception 'Worker lease is invalid or expired' using errcode='55000';
 end if;
 if not public.mme_pos_authorize_hardware_action(p_worker_person_id,'pos.finance.report.import',v_job.location_id) then
  raise exception 'Worker import permission denied' using errcode='42501';
 end if;
 if p_success then
  select status into v_batch_status from public.mme_pos_financial_import_batches where id=v_job.batch_id;
  if v_batch_status not in ('completed','completed_with_quarantine') then
   raise exception 'Cannot complete job before its batch reaches a terminal state' using errcode='55000';
  end if;
  v_next:=v_batch_status;
  update public.mme_pos_financial_import_jobs set status=v_next,lease_token=null,lease_expires_at=null,
   completed_at=now(),updated_at=now() where id=p_job_id;
  insert into public.mme_pos_financial_worker_events(job_id,batch_id,location_id,worker_person_id,event_type,reason)
  values(p_job_id,v_job.batch_id,v_job.location_id,p_worker_person_id,'job_completed','Financial import job reached a terminal batch state.');
 else
  v_next:=case when v_job.attempts>=v_job.max_attempts then 'dead_letter' else 'retry_wait' end;
  update public.mme_pos_financial_import_jobs set status=v_next,lease_token=null,lease_expires_at=null,
   available_at=case when v_next='retry_wait' then now()+make_interval(secs=>least(3600,15*power(2,least(v_job.attempts-1,8))::integer)) else available_at end,
   last_error_code=left(coalesce(p_error_code,'WORKER_ERROR'),80),last_error_safe=left(coalesce(p_safe_error,'Import worker failed; inspect restricted diagnostics.'),500),
   updated_at=now() where id=p_job_id;
  insert into public.mme_pos_financial_worker_events(job_id,batch_id,location_id,worker_person_id,event_type,reason,metadata)
  values(p_job_id,v_job.batch_id,v_job.location_id,p_worker_person_id,
   case when v_next='dead_letter' then 'job_dead_lettered' else 'job_retry_scheduled' end,
   case when v_next='dead_letter' then 'Maximum import attempts reached; manual review required.' else 'Transient worker failure; retry scheduled with bounded backoff.' end,
   jsonb_build_object('attempt',v_job.attempts,'error_code',left(coalesce(p_error_code,'WORKER_ERROR'),80)));
 end if;
 return v_next;
end;
$$;

create or replace function public.mme_pos_record_financial_webhook_event(
 p_connector_id uuid,p_provider_event_id text,p_event_type text,p_account_reference text,p_payload_sha256 text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_connector public.mme_pos_financial_connectors%rowtype; v_id uuid;
begin
 select * into v_connector from public.mme_pos_financial_connectors where id=p_connector_id for update;
 if not found or v_connector.provider_key<>'stripe' or v_connector.status<>'active' then
  raise exception 'Active Stripe connector not found' using errcode='P0002';
 end if;
 if length(btrim(coalesce(p_provider_event_id,'')))<1 or length(btrim(coalesce(p_event_type,'')))<1
  or p_payload_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Invalid webhook event metadata' using errcode='22023'; end if;
 insert into public.mme_pos_financial_webhook_events(connector_id,location_id,provider_key,provider_event_id,
  provider_event_type,provider_account_reference,payload_sha256,status)
 values(p_connector_id,v_connector.location_id,'stripe',p_provider_event_id,p_event_type,p_account_reference,p_payload_sha256,'received')
 on conflict(connector_id,provider_event_id) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.mme_pos_financial_webhook_events
  where connector_id=p_connector_id and provider_event_id=p_provider_event_id; end if;
 return v_id;
end;
$$;

revoke all on function public.mme_pos_enqueue_financial_import_jobs(uuid,integer) from public,anon,authenticated;
revoke all on function public.mme_pos_claim_financial_import_job(uuid,integer) from public,anon,authenticated;
revoke all on function public.mme_pos_finish_financial_import_job(uuid,uuid,uuid,boolean,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_record_financial_webhook_event(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_enqueue_financial_import_jobs(uuid,integer) to service_role;
grant execute on function public.mme_pos_claim_financial_import_job(uuid,integer) to service_role;
grant execute on function public.mme_pos_finish_financial_import_job(uuid,uuid,uuid,boolean,text,text) to service_role;
grant execute on function public.mme_pos_record_financial_webhook_event(uuid,text,text,text,text) to service_role;

comment on table public.mme_pos_financial_import_jobs is 'Leased, idempotent worker queue for staged financial import batches.';
comment on table public.mme_pos_financial_webhook_events is 'Verified provider event metadata and payload digests only; raw webhook bodies are not persisted.';
commit;
