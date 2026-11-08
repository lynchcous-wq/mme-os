create table if not exists public.mme_identity_unlock_requests (
 id uuid primary key default gen_random_uuid(),
 target_identity_id uuid not null references public.mme_person_identities(id) on delete restrict,
 requested_by_identity_id uuid not null references public.mme_person_identities(id) on delete restrict,
 reason text not null check(length(btrim(reason))>0),
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 approved_by_identity_id uuid references public.mme_person_identities(id) on delete restrict,
 approved_at timestamptz, created_at timestamptz not null default now(),
 check(approved_by_identity_id is null or approved_by_identity_id<>requested_by_identity_id)
);
create index if not exists mme_identity_unlock_requests_pending_idx on public.mme_identity_unlock_requests(target_identity_id,created_at desc) where status='pending';
alter table public.mme_identity_unlock_requests enable row level security;
revoke all on public.mme_identity_unlock_requests from public,anon,authenticated;
grant select,insert,update,delete on public.mme_identity_unlock_requests to service_role;

create or replace function private.mme_freeze_identity(p_target_identity_id uuid,p_actor_identity_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare v_target public.mme_person_identities%rowtype;
begin
 if p_target_identity_id is null or p_actor_identity_id is null or p_target_identity_id=p_actor_identity_id then raise exception 'Invalid target or self-freeze prohibited' using errcode='42501'; end if;
 if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'Freeze reason required' using errcode='22023'; end if;
 perform 1 from public.mme_person_identities where id=p_actor_identity_id and security_status='active';
 if not found then raise exception 'Active actor identity required' using errcode='42501'; end if;
 select * into v_target from public.mme_person_identities where id=p_target_identity_id for update;
 if not found then raise exception 'Target identity not found' using errcode='P0002'; end if;
 if v_target.security_status='locked' then return jsonb_build_object('status','already_locked'); end if;
 update public.mme_person_identities set security_status='locked',security_locked_at=now(),security_lock_reason=btrim(p_reason),security_locked_by_identity_id=p_actor_identity_id where id=p_target_identity_id;
 delete from auth.sessions where user_id=v_target.auth_user_id;
 insert into public.mme_identity_audit_events(actor_identity_id,actor_service_key,target_identity_id,action_key,outcome,reason,before_state,after_state)
 values(p_actor_identity_id,'mme_account_security',p_target_identity_id,'identity.freeze','success',btrim(p_reason),jsonb_build_object('security_status',v_target.security_status),jsonb_build_object('security_status','locked','sessions_revoked',true));
 return jsonb_build_object('status','frozen','target_identity_id',p_target_identity_id,'sessions_revoked',true);
end;$f$;

create or replace function private.mme_request_identity_unlock(p_target_identity_id uuid,p_requester_identity_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=''
as $f$
declare v_id uuid;
begin
 if p_target_identity_id is null or p_requester_identity_id is null or p_target_identity_id=p_requester_identity_id then raise exception 'Invalid target or self-unlock request prohibited' using errcode='42501'; end if;
 if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'Unlock reason required' using errcode='22023'; end if;
 perform 1 from public.mme_person_identities where id=p_requester_identity_id and security_status='active';
 if not found then raise exception 'Active requester identity required' using errcode='42501'; end if;
 perform 1 from public.mme_person_identities where id=p_target_identity_id and security_status='locked';
 if not found then raise exception 'Target identity is not locked' using errcode='P0002'; end if;
 if exists(select 1 from public.mme_identity_unlock_requests where target_identity_id=p_target_identity_id and status='pending') then raise exception 'Pending unlock request already exists' using errcode='23505'; end if;
 insert into public.mme_identity_unlock_requests(target_identity_id,requested_by_identity_id,reason) values(p_target_identity_id,p_requester_identity_id,btrim(p_reason)) returning id into v_id;
 insert into public.mme_identity_audit_events(actor_identity_id,actor_service_key,target_identity_id,action_key,outcome,reason,after_state)
 values(p_requester_identity_id,'mme_account_security',p_target_identity_id,'identity.unlock_requested','success',btrim(p_reason),jsonb_build_object('request_id',v_id,'status','pending'));
 return v_id;
end;$f$;

create or replace function private.mme_approve_identity_unlock(p_request_id uuid,p_approver_identity_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare v_req public.mme_identity_unlock_requests%rowtype;
begin
 if p_request_id is null or p_approver_identity_id is null then raise exception 'Request and approver required' using errcode='22023'; end if;
 perform 1 from public.mme_person_identities where id=p_approver_identity_id and security_status='active';
 if not found then raise exception 'Active approver identity required' using errcode='42501'; end if;
 select * into v_req from public.mme_identity_unlock_requests where id=p_request_id for update;
 if not found or v_req.status<>'pending' then raise exception 'Pending unlock request not found' using errcode='P0002'; end if;
 if p_approver_identity_id in (v_req.target_identity_id,v_req.requested_by_identity_id) then raise exception 'Target/requester cannot approve unlock' using errcode='42501'; end if;
 perform 1 from public.mme_person_identities where id=v_req.target_identity_id and security_status='locked' for update;
 if not found then raise exception 'Target no longer locked' using errcode='P0002'; end if;
 update public.mme_person_identities set security_status='active',security_locked_at=null,security_lock_reason=null,security_locked_by_identity_id=null where id=v_req.target_identity_id;
 update public.mme_identity_unlock_requests set status='approved',approved_by_identity_id=p_approver_identity_id,approved_at=now() where id=p_request_id;
 insert into public.mme_identity_audit_events(actor_identity_id,actor_service_key,target_identity_id,action_key,outcome,reason,before_state,after_state)
 values(p_approver_identity_id,'mme_account_security',v_req.target_identity_id,'identity.unlock_approved','success',v_req.reason,jsonb_build_object('security_status','locked','request_id',p_request_id),jsonb_build_object('security_status','active','fresh_sign_in_required',true));
 return jsonb_build_object('status','unlocked','target_identity_id',v_req.target_identity_id,'fresh_sign_in_required',true);
end;$f$;
revoke all on function private.mme_freeze_identity(uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.mme_request_identity_unlock(uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.mme_approve_identity_unlock(uuid,uuid) from public,anon,authenticated;
grant execute on function private.mme_freeze_identity(uuid,uuid,text) to service_role;
grant execute on function private.mme_request_identity_unlock(uuid,uuid,text) to service_role;
grant execute on function private.mme_approve_identity_unlock(uuid,uuid) to service_role;