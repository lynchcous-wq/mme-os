begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('mme-warranty-security-evidence','mme-warranty-security-evidence',false,52428800,
 array['image/jpeg','image/png','image/webp','application/pdf','text/plain','application/json'])
on conflict(id) do update set public=false,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;
create table public.mme_warranty_security_evidence_access_log(
 access_id bigint generated always as identity primary key,
 evidence_id uuid references public.mme_warranty_security_case_evidence(evidence_id) on delete restrict,
 case_id uuid not null references public.mme_warranty_security_cases(case_id) on delete restrict,
 actor_id uuid not null,action text not null check(action in ('upload','view','download','verify','retention_update','legal_hold','deletion_request','deletion_approve','deletion_reject')),
 request_id uuid not null,ip_hash text,details jsonb not null default '{}'::jsonb,occurred_at timestamptz not null default now()
);
create table public.mme_warranty_security_evidence_retention(
 evidence_id uuid primary key references public.mme_warranty_security_case_evidence(evidence_id) on delete restrict,
 retention_until timestamptz,retention_reason text not null,
 legal_hold boolean not null default false,hold_reason text,hold_set_by uuid,hold_set_at timestamptz,
 updated_by uuid not null,updated_at timestamptz not null default now(),
 check((legal_hold and hold_reason is not null and hold_set_by is not null) or not legal_hold)
);
create table public.mme_warranty_security_evidence_deletion_requests(
 deletion_request_id uuid primary key default gen_random_uuid(),
 evidence_id uuid not null references public.mme_warranty_security_case_evidence(evidence_id) on delete restrict,
 requested_by uuid not null,reason text not null check(length(trim(reason)) between 10 and 2000),
 status text not null default 'pending' check(status in ('pending','approved','rejected','executed','blocked')),
 decided_by uuid,decided_at timestamptz,decision_reason text,executed_at timestamptz,
 created_at timestamptz not null default now(),
 check(decided_by is null or decided_by<>requested_by)
);
alter table public.mme_warranty_security_evidence_access_log enable row level security;
alter table public.mme_warranty_security_evidence_retention enable row level security;
alter table public.mme_warranty_security_evidence_deletion_requests enable row level security;
revoke all on public.mme_warranty_security_evidence_access_log,public.mme_warranty_security_evidence_retention,public.mme_warranty_security_evidence_deletion_requests from public,anon,authenticated;
grant select,insert on public.mme_warranty_security_evidence_access_log to service_role;
grant select,insert,update on public.mme_warranty_security_evidence_retention,public.mme_warranty_security_evidence_deletion_requests to service_role;
create or replace function public.mme_warranty_security_evidence_set_legal_hold(p_evidence_id uuid,p_actor_id uuid,p_reason text,p_request_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if length(trim(coalesce(p_reason,'')))<10 then raise exception 'legal_hold_reason_required'; end if;
 insert into public.mme_warranty_security_evidence_retention(evidence_id,legal_hold,hold_reason,hold_set_by,hold_set_at,retention_reason,updated_by)
 values(p_evidence_id,true,p_reason,p_actor_id,now(),'Legal hold',p_actor_id)
 on conflict(evidence_id) do update set legal_hold=true,hold_reason=excluded.hold_reason,hold_set_by=p_actor_id,hold_set_at=now(),updated_by=p_actor_id,updated_at=now();
 return true;
end $$;
revoke all on function public.mme_warranty_security_evidence_set_legal_hold(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_security_evidence_set_legal_hold(uuid,uuid,text,uuid) to service_role;
commit;