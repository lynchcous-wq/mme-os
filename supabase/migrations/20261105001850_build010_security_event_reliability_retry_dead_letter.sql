begin;
create table public.mme_warranty_security_event_delivery_queue(
 job_id uuid primary key default gen_random_uuid(),
 event_id text not null,
 source_system text not null check(source_system in ('pos','inventory','warranty','crm','evidence','payments','returns')),
 event_type text not null,
 subject_fingerprint text not null check(subject_fingerprint ~ '^[a-f0-9]{64}$'),
 payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
 task_type text not null check(task_type in ('correlate','notify','reconcile')),
 task_payload jsonb not null default '{}'::jsonb,
 status text not null default 'pending' check(status in ('pending','processing','succeeded','retry_wait','dead_letter')),
 attempt_count integer not null default 0 check(attempt_count>=0),
 max_attempts integer not null default 8 check(max_attempts between 1 and 20),
 next_attempt_at timestamptz not null default now(),
 lease_until timestamptz,
 leased_by text,
 last_error_code text,
 last_error_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 completed_at timestamptz,
 unique(event_id,task_type)
);
create index mme_security_delivery_due_idx on public.mme_warranty_security_event_delivery_queue(status,next_attempt_at) where status in ('pending','retry_wait');
create index mme_security_delivery_dead_idx on public.mme_warranty_security_event_delivery_queue(created_at desc) where status='dead_letter';
create table public.mme_warranty_security_event_delivery_attempts(
 attempt_id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.mme_warranty_security_event_delivery_queue(job_id) on delete restrict,
 attempt_number integer not null,
 worker_id text not null,
 outcome text not null check(outcome in ('succeeded','retry_scheduled','dead_letter')),
 error_code text,
 started_at timestamptz not null,
 finished_at timestamptz not null default now(),
 unique(job_id,attempt_number)
);
create table public.mme_warranty_security_event_delivery_receipts(
 receipt_id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.mme_warranty_security_event_delivery_queue(job_id) on delete restrict,
 event_id text not null,
 receipt_type text not null check(receipt_type in ('accepted','attempted','succeeded','retry_scheduled','dead_letter','replayed')),
 detail jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
alter table public.mme_warranty_security_event_delivery_queue enable row level security;
alter table public.mme_warranty_security_event_delivery_attempts enable row level security;
alter table public.mme_warranty_security_event_delivery_receipts enable row level security;
revoke all on public.mme_warranty_security_event_delivery_queue from public,anon,authenticated;
revoke all on public.mme_warranty_security_event_delivery_attempts from public,anon,authenticated;
revoke all on public.mme_warranty_security_event_delivery_receipts from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_security_event_delivery_queue to service_role;
grant select,insert on public.mme_warranty_security_event_delivery_attempts to service_role;
grant select,insert on public.mme_warranty_security_event_delivery_receipts to service_role;
create or replace function public.mme_security_delivery_claim(p_worker text,p_limit integer default 10)
returns setof public.mme_warranty_security_event_delivery_queue
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query
 with candidates as (
  select job_id from public.mme_warranty_security_event_delivery_queue
  where ((status in ('pending','retry_wait') and next_attempt_at<=now()) or (status='processing' and lease_until<now()))
  and attempt_count<max_attempts
  order by next_attempt_at,created_at
  for update skip locked limit greatest(1,least(p_limit,50))
 )
 update public.mme_warranty_security_event_delivery_queue q
 set status='processing',attempt_count=q.attempt_count+1,leased_by=p_worker,lease_until=now()+interval '2 minutes',updated_at=now()
 from candidates c where q.job_id=c.job_id returning q.*;
end $$;
create or replace function public.mme_security_delivery_finish(p_job uuid,p_worker text,p_success boolean,p_error text default null)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.mme_warranty_security_event_delivery_queue%rowtype; delay_seconds integer;
begin
 select * into q from public.mme_warranty_security_event_delivery_queue where job_id=p_job for update;
 if not found or q.status<>'processing' or q.leased_by<>p_worker then raise exception 'delivery_lease_not_owned'; end if;
 if p_success then
  update public.mme_warranty_security_event_delivery_queue set status='succeeded',completed_at=now(),lease_until=null,leased_by=null,updated_at=now() where job_id=p_job;
  return 'succeeded';
 end if;
 if q.attempt_count>=q.max_attempts then
  update public.mme_warranty_security_event_delivery_queue set status='dead_letter',last_error_code=left(coalesce(p_error,'processing_failed'),100),last_error_at=now(),lease_until=null,leased_by=null,updated_at=now() where job_id=p_job;
  return 'dead_letter';
 end if;
 delay_seconds=least(21600,30*power(2,greatest(0,q.attempt_count-1))::integer);
 update public.mme_warranty_security_event_delivery_queue set status='retry_wait',next_attempt_at=now()+make_interval(secs=>delay_seconds),last_error_code=left(coalesce(p_error,'processing_failed'),100),last_error_at=now(),lease_until=null,leased_by=null,updated_at=now() where job_id=p_job;
 return 'retry_wait';
end $$;
revoke all on function public.mme_security_delivery_claim(text,integer) from public,anon,authenticated;
revoke all on function public.mme_security_delivery_finish(uuid,text,boolean,text) from public,anon,authenticated;
grant execute on function public.mme_security_delivery_claim(text,integer) to service_role;
grant execute on function public.mme_security_delivery_finish(uuid,text,boolean,text) to service_role;
commit;