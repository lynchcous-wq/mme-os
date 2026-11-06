-- Build 010.84 — staff authorization, decision RPC, and verified login/customer activation.
begin;

create or replace function public.mme_employee_authorize_customer_identity_review(p_actor_auth_user_id uuid)
returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_ceo uuid; v_frozen boolean; v_status text;
begin
 if p_actor_auth_user_id is null then return false; end if;
 select ceo_user_id,employee_access_frozen into v_ceo,v_frozen
 from public.employee_security_settings where singleton=true;
 if not found or v_frozen is distinct from false or v_ceo is null then return false; end if;
 select employment_status into v_status from public.employee_relationships where user_id=p_actor_auth_user_id;
 if v_status is distinct from 'active' then return false; end if;
 if p_actor_auth_user_id=v_ceo then return true; end if;
 return exists(select 1 from public.employee_permission_grants g
  where g.employee_user_id=p_actor_auth_user_id
   and g.permission_key='customer.identity.review'
   and g.revoked_at is null and (g.expires_at is null or g.expires_at>now()));
end;
$$;

create or replace function public.mme_customer_identity_review_decide(
 p_actor_auth_user_id uuid,
 p_request_id uuid,
 p_decision text,
 p_person_id uuid default null,
 p_review_note text default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth
as $$
declare v_req public.mme_customer_identity_link_requests%rowtype;
 v_email text; v_confirmed_at timestamptz; v_existing_person uuid; v_mapping_status text;
begin
 if not public.mme_employee_authorize_customer_identity_review(p_actor_auth_user_id) then
  raise exception 'Not authorized to review customer identity requests' using errcode='42501';
 end if;
 if p_request_id is null or p_decision not in ('under_review','approve','reject')
  or (p_review_note is not null and length(p_review_note)>1000) then
  raise exception 'Invalid review decision' using errcode='22023';
 end if;

 select * into v_req from public.mme_customer_identity_link_requests
 where request_id=p_request_id for update;
 if not found then raise exception 'Identity-link request not found' using errcode='P0002'; end if;
 if v_req.request_status not in ('pending','under_review') then
  raise exception 'Request is no longer open for review' using errcode='55000';
 end if;

 if p_decision='under_review' then
  update public.mme_customer_identity_link_requests set request_status='under_review',
   reviewed_by_auth_user_id=p_actor_auth_user_id,review_note=p_review_note,
   updated_at=now() where request_id=p_request_id;
  return jsonb_build_object('request_id',p_request_id,'status','under_review');
 elsif p_decision='reject' then
  update public.mme_customer_identity_link_requests set request_status='rejected',
   reviewed_at=now(),reviewed_by_auth_user_id=p_actor_auth_user_id,
   review_note=p_review_note,updated_at=now() where request_id=p_request_id;
  return jsonb_build_object('request_id',p_request_id,'status','rejected');
 end if;

 if p_person_id is null then raise exception 'An independently verified MME person identity is required' using errcode='22023'; end if;
 if not exists(select 1 from public.mme_person_identities p where p.person_id=p_person_id and p.lifecycle_status='active') then
  raise exception 'Selected MME person identity is not active' using errcode='22023';
 end if;

 -- Re-check the Auth record at approval time. A customer-supplied email or reference
 -- is not proof of identity; staff must verify the MME source records separately.
 select email,email_confirmed_at into v_email,v_confirmed_at from auth.users where id=v_req.auth_user_id;
 if v_email is null or v_confirmed_at is null or lower(v_email)<>lower(v_req.verified_email) then
  raise exception 'Customer email verification is no longer valid' using errcode='55000';
 end if;

 select person_id,link_status into v_existing_person,v_mapping_status
 from public.mme_login_identities where provider_key='supabase' and auth_user_id=v_req.auth_user_id;
 if found and (v_existing_person<>p_person_id or v_mapping_status not in ('verified')) then
  raise exception 'This login is already linked or conflicted; escalate for identity reconciliation' using errcode='23505';
 end if;

 if not found then
  insert into public.mme_login_identities(person_id,provider_key,provider_subject,auth_user_id,link_status,verified_at)
  values(p_person_id,'supabase',v_req.auth_user_id::text,v_req.auth_user_id,'verified',now());
 end if;

 perform public.mme_customer_portal_provision_account_link(v_req.auth_user_id,p_person_id);

 update public.mme_customer_identity_link_requests set request_status='approved',
  reviewed_at=now(),reviewed_by_auth_user_id=p_actor_auth_user_id,
  review_note=p_review_note,linked_person_id=p_person_id,updated_at=now()
 where request_id=p_request_id;
 return jsonb_build_object('request_id',p_request_id,'status','approved','person_id',p_person_id);
end;
$$;

revoke all on function public.mme_employee_authorize_customer_identity_review(uuid) from public,anon,authenticated;
revoke all on function public.mme_customer_identity_review_decide(uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_employee_authorize_customer_identity_review(uuid) to service_role;
grant execute on function public.mme_customer_identity_review_decide(uuid,uuid,text,uuid,text) to service_role;

comment on function public.mme_employee_authorize_customer_identity_review(uuid) is
 'Server-only customer identity review permission. Requires active employee, unfrozen employee access, and CEO authority or explicit customer.identity.review grant.';
comment on function public.mme_customer_identity_review_decide(uuid,uuid,text,uuid,text) is
 'Service-role-only identity review. Server must derive actor UUID from validated employee session. Approval requires active person, confirmed email, no conflicting login mapping, and creates verified login mapping plus customer portal link in one transaction.';

commit;
