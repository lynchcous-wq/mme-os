-- Build 009.85: append-only compliance API audit and atomic rate limits
begin;
create table public.mme_warranty_compliance_api_audit (
 audit_id bigint generated always as identity primary key,
 request_id uuid not null,
 actor_id uuid,
 resource text not null,
 action text not null check(action in ('read','rate_limited','denied','upstream_error')),
 outcome text not null check(outcome in ('allowed','denied','limited','failed')),
 role_claims text[] not null default '{}',
 ip_digest text,
 reason_code text not null,
 occurred_at timestamptz not null default now()
);
create index mme_warranty_compliance_api_audit_actor_idx on public.mme_warranty_compliance_api_audit(actor_id,occurred_at desc);
create index mme_warranty_compliance_api_audit_request_idx on public.mme_warranty_compliance_api_audit(request_id);
create table public.mme_warranty_compliance_api_rate_buckets (
 bucket_key text not null,
 window_start timestamptz not null,
 request_count integer not null check(request_count>=0),
 updated_at timestamptz not null default now(),
 primary key(bucket_key,window_start)
);
alter table public.mme_warranty_compliance_api_audit enable row level security;
alter table public.mme_warranty_compliance_api_rate_buckets enable row level security;
revoke all on public.mme_warranty_compliance_api_audit,public.mme_warranty_compliance_api_rate_buckets from public,anon,authenticated;
grant select,insert on public.mme_warranty_compliance_api_audit to service_role;
grant select,insert,update,delete on public.mme_warranty_compliance_api_rate_buckets to service_role;

create or replace function public.mme_warranty_compliance_consume_rate_limit(p_bucket_key text,p_limit integer default 60,p_window_seconds integer default 60)
returns table(allowed boolean,remaining integer,resets_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_start timestamptz; v_count integer;
begin
 if p_bucket_key is null or length(p_bucket_key)<8 or length(p_bucket_key)>160 or p_limit<1 or p_limit>1000 or p_window_seconds<1 or p_window_seconds>3600 then
  raise exception 'invalid_rate_limit_arguments';
 end if;
 v_start:=to_timestamp(floor(extract(epoch from now())/p_window_seconds)*p_window_seconds);
 insert into public.mme_warranty_compliance_api_rate_buckets(bucket_key,window_start,request_count)
 values(p_bucket_key,v_start,1)
 on conflict(bucket_key,window_start) do update set request_count=public.mme_warranty_compliance_api_rate_buckets.request_count+1,updated_at=now()
 returning request_count into v_count;
 return query select v_count<=p_limit,greatest(p_limit-v_count,0),v_start+make_interval(secs=>p_window_seconds);
end $$;

create or replace function public.mme_warranty_compliance_record_api_audit(
 p_request_id uuid,p_actor_id uuid,p_resource text,p_action text,p_outcome text,
 p_roles text[],p_ip_digest text,p_reason_code text
) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_resource not in ('summary','calendar','approvals','alerts','assignments','unknown') then raise exception 'invalid_audit_resource'; end if;
 if p_action not in ('read','rate_limited','denied','upstream_error') then raise exception 'invalid_audit_action'; end if;
 if p_outcome not in ('allowed','denied','limited','failed') then raise exception 'invalid_audit_outcome'; end if;
 insert into public.mme_warranty_compliance_api_audit(request_id,actor_id,resource,action,outcome,role_claims,ip_digest,reason_code)
 values(p_request_id,p_actor_id,p_resource,p_action,p_outcome,coalesce(p_roles,'{}'),p_ip_digest,left(coalesce(p_reason_code,'unspecified'),80));
end $$;
revoke all on function public.mme_warranty_compliance_consume_rate_limit(text,integer,integer) from public,anon,authenticated;
revoke all on function public.mme_warranty_compliance_record_api_audit(uuid,uuid,text,text,text,text[],text,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_compliance_consume_rate_limit(text,integer,integer) to service_role;
grant execute on function public.mme_warranty_compliance_record_api_audit(uuid,uuid,text,text,text,text[],text,text) to service_role;
commit;
