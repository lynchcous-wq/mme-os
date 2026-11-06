-- Build 009.75: durable warranty renewal scan and worker queue
begin;
create table public.mme_warranty_renewal_worker_jobs (
 job_id uuid primary key default gen_random_uuid(),
 opportunity_id uuid not null references public.mme_warranty_renewal_opportunities(opportunity_id) on delete restrict,
 job_type text not null check(job_type in ('review_opportunity','prepare_offer','queue_reminder')),
 status text not null default 'queued' check(status in ('queued','processing','succeeded','retry','dead_letter','cancelled')),
 available_at timestamptz not null default now(), attempts integer not null default 0 check(attempts>=0),
 max_attempts integer not null default 8 check(max_attempts between 1 and 20),
 lease_token uuid, lease_expires_at timestamptz, last_error_code text,
 idempotency_key text not null unique, created_at timestamptz not null default now(), completed_at timestamptz,
 check((status='processing')=(lease_token is not null and lease_expires_at is not null))
);
create index mme_warranty_renewal_worker_queue_idx on public.mme_warranty_renewal_worker_jobs(available_at,created_at) where status in ('queued','retry');
create table public.mme_warranty_renewal_worker_runs (
 run_id uuid primary key default gen_random_uuid(), started_at timestamptz not null default now(),
 completed_at timestamptz, run_status text not null default 'running' check(run_status in ('running','succeeded','partial','failed')),
 scanned_count integer not null default 0, opportunity_count integer not null default 0,
 job_count integer not null default 0, error_code text, initiated_by text not null default 'scheduler'
);
alter table public.mme_warranty_renewal_worker_jobs enable row level security;
alter table public.mme_warranty_renewal_worker_runs enable row level security;
revoke all on public.mme_warranty_renewal_worker_jobs,public.mme_warranty_renewal_worker_runs from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_renewal_worker_jobs,public.mme_warranty_renewal_worker_runs to service_role;

create or replace function public.mme_warranty_renewal_scan(p_as_of timestamptz default now())
returns table(scanned integer, opportunities_created integer, jobs_created integer)
language plpgsql security definer set search_path=public,pg_temp as $$
declare r record; v_scanned integer:=0; v_opportunities integer:=0; v_jobs integer:=0; v_id uuid; v_run uuid;
begin
 insert into public.mme_warranty_renewal_worker_runs(initiated_by) values('scheduler_or_service') returning run_id into v_run;
 for r in
  select l.lifecycle_id,l.customer_identity_id,l.coverage_ends_at,h.days,c.campaign_id
  from public.mme_warranty_lifecycle_records l
  cross join (values(30),(60),(90)) as h(days)
  join public.mme_warranty_renewal_campaigns c on c.lead_days=h.days and c.status='active'
    and c.approved_by is not null and c.approved_at is not null
    and (c.starts_at is null or c.starts_at<=p_as_of) and (c.ends_at is null or c.ends_at>p_as_of)
  where l.lifecycle_status='active' and l.coverage_ends_at is not null
    and l.coverage_ends_at>p_as_of
    and l.coverage_ends_at<=p_as_of+make_interval(days=>h.days)
    and l.coverage_ends_at>p_as_of+make_interval(days=>h.days-1)
  order by l.coverage_ends_at
 loop
  v_scanned:=v_scanned+1;
  insert into public.mme_warranty_renewal_opportunities
   (lifecycle_id,customer_identity_id,coverage_ends_at,horizon_days,status,campaign_id,idempotency_key)
  values(r.lifecycle_id,r.customer_identity_id,r.coverage_ends_at,r.days,'identified',r.campaign_id,
   'renewal:'||r.lifecycle_id::text||':'||r.days::text)
  on conflict(lifecycle_id,horizon_days) do nothing
  returning opportunity_id into v_id;
  if v_id is not null then
   v_opportunities:=v_opportunities+1;
   insert into public.mme_warranty_renewal_worker_jobs(opportunity_id,job_type,idempotency_key)
   values(v_id,'review_opportunity','renewal-review:'||v_id::text)
   on conflict(idempotency_key) do nothing;
   if found then v_jobs:=v_jobs+1; end if;
  end if;
  v_id:=null;
 end loop;
 update public.mme_warranty_renewal_worker_runs set completed_at=now(),run_status='succeeded',
  scanned_count=v_scanned,opportunity_count=v_opportunities,job_count=v_jobs where run_id=v_run;
 return query select v_scanned,v_opportunities,v_jobs;
exception when others then
 update public.mme_warranty_renewal_worker_runs set completed_at=now(),run_status='failed',error_code=sqlstate where run_id=v_run;
 raise;
end $$;

create or replace function public.mme_warranty_renewal_claim_jobs(p_limit integer default 25,p_lease_seconds integer default 120)
returns setof public.mme_warranty_renewal_worker_jobs
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_limit<1 or p_limit>100 or p_lease_seconds<30 or p_lease_seconds>900 then
  raise exception 'invalid_worker_claim_parameters' using errcode='22023';
 end if;
 return query
 with candidates as (
  select j.job_id from public.mme_warranty_renewal_worker_jobs j
  where (j.status in ('queued','retry') and j.available_at<=now())
     or (j.status='processing' and j.lease_expires_at<now() and j.attempts<j.max_attempts)
  order by j.available_at,j.created_at
  for update skip locked limit p_limit
 ), claimed as (
  update public.mme_warranty_renewal_worker_jobs j set status='processing',attempts=j.attempts+1,
   lease_token=gen_random_uuid(),lease_expires_at=now()+make_interval(secs=>p_lease_seconds)
  from candidates c where j.job_id=c.job_id and j.attempts<j.max_attempts
  returning j.*
 ) select * from claimed;
end $$;

create or replace function public.mme_warranty_renewal_complete_job(p_job_id uuid,p_lease_token uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 update public.mme_warranty_renewal_worker_jobs set status='succeeded',completed_at=now(),lease_token=null,lease_expires_at=null
 where job_id=p_job_id and status='processing' and lease_token=p_lease_token;
 get diagnostics n=row_count; return n=1;
end $$;

create or replace function public.mme_warranty_renewal_fail_job(p_job_id uuid,p_lease_token uuid,p_error_code text,p_retry_seconds integer default 300)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_status text;
begin
 update public.mme_warranty_renewal_worker_jobs set
  status=case when attempts>=max_attempts then 'dead_letter' else 'retry' end,
  available_at=case when attempts>=max_attempts then available_at else now()+make_interval(secs=>greatest(30,least(p_retry_seconds,86400))) end,
  last_error_code=left(coalesce(p_error_code,'worker_error'),80),lease_token=null,lease_expires_at=null
 where job_id=p_job_id and status='processing' and lease_token=p_lease_token
 returning status into v_status;
 return v_status;
end $$;

revoke all on function public.mme_warranty_renewal_scan(timestamptz) from public,anon,authenticated;
revoke all on function public.mme_warranty_renewal_claim_jobs(integer,integer) from public,anon,authenticated;
revoke all on function public.mme_warranty_renewal_complete_job(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_warranty_renewal_fail_job(uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.mme_warranty_renewal_scan(timestamptz) to service_role;
grant execute on function public.mme_warranty_renewal_claim_jobs(integer,integer) to service_role;
grant execute on function public.mme_warranty_renewal_complete_job(uuid,uuid) to service_role;
grant execute on function public.mme_warranty_renewal_fail_job(uuid,uuid,text,integer) to service_role;
commit;