-- Build 010.86 — customer-editable profile preferences and append-only audit.
begin;
create table if not exists public.mme_customer_profiles (
 auth_user_id uuid primary key,
 preferred_name text check(preferred_name is null or (length(btrim(preferred_name)) between 1 and 80)),
 email_notifications_enabled boolean not null default true,
 sms_notifications_enabled boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_customer_profile_audit (
 audit_id bigint generated always as identity primary key,
 auth_user_id uuid not null,
 actor_auth_user_id uuid not null,
 changed_fields text[] not null,
 before_state jsonb not null,
 after_state jsonb not null,
 created_at timestamptz not null default now()
);
create index if not exists mme_customer_profile_audit_owner_idx
 on public.mme_customer_profile_audit(auth_user_id,created_at desc);
alter table public.mme_customer_profiles enable row level security;
alter table public.mme_customer_profile_audit enable row level security;
revoke all on public.mme_customer_profiles,public.mme_customer_profile_audit from public,anon,authenticated;
grant select on public.mme_customer_profiles to authenticated;
create policy mme_customer_profile_self_read on public.mme_customer_profiles
 for select to authenticated using(auth_user_id=auth.uid());
revoke all on function public.mme_customer_profile_update(uuid,text,boolean,boolean) from public,anon,authenticated;
create or replace function public.mme_customer_profile_update(
 p_auth_user_id uuid,p_preferred_name text,p_email_notifications_enabled boolean,p_sms_notifications_enabled boolean
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth
as $$
declare v_before jsonb; v_after jsonb; v_changed text[]:='{}'; v_email_confirmed timestamptz;
begin
 if p_auth_user_id is null or auth.uid() is distinct from p_auth_user_id then
  raise exception 'Customer session does not match profile owner' using errcode='42501';
 end if;
 if p_preferred_name is not null and (length(btrim(p_preferred_name)) not between 1 and 80
   or p_preferred_name ~ '[[:cntrl:]]') then
  raise exception 'Preferred name must be 1–80 printable characters' using errcode='22023';
 end if;
 if p_email_notifications_enabled is null or p_sms_notifications_enabled is null then
  raise exception 'Notification preferences are required' using errcode='22023';
 end if;
 select email_confirmed_at into v_email_confirmed from auth.users where id=p_auth_user_id;
 if not found or v_email_confirmed is null then
  raise exception 'Verified customer account required' using errcode='42501';
 end if;
 select jsonb_build_object('preferred_name',preferred_name,
  'email_notifications_enabled',email_notifications_enabled,
  'sms_notifications_enabled',sms_notifications_enabled)
 into v_before from public.mme_customer_profiles where auth_user_id=p_auth_user_id;
 if v_before is null then
  v_before=jsonb_build_object('preferred_name',null,'email_notifications_enabled',true,'sms_notifications_enabled',false);
 end if;
 insert into public.mme_customer_profiles(auth_user_id,preferred_name,email_notifications_enabled,sms_notifications_enabled)
 values(p_auth_user_id,nullif(btrim(p_preferred_name),''),p_email_notifications_enabled,p_sms_notifications_enabled)
 on conflict(auth_user_id) do update set preferred_name=excluded.preferred_name,
  email_notifications_enabled=excluded.email_notifications_enabled,
  sms_notifications_enabled=excluded.sms_notifications_enabled,updated_at=now();
 select jsonb_build_object('preferred_name',preferred_name,
  'email_notifications_enabled',email_notifications_enabled,
  'sms_notifications_enabled',sms_notifications_enabled)
 into v_after from public.mme_customer_profiles where auth_user_id=p_auth_user_id;
 if v_before->'preferred_name' is distinct from v_after->'preferred_name' then v_changed=array_append(v_changed,'preferred_name'); end if;
 if v_before->'email_notifications_enabled' is distinct from v_after->'email_notifications_enabled' then v_changed=array_append(v_changed,'email_notifications_enabled'); end if;
 if v_before->'sms_notifications_enabled' is distinct from v_after->'sms_notifications_enabled' then v_changed=array_append(v_changed,'sms_notifications_enabled'); end if;
 if cardinality(v_changed)>0 then
  insert into public.mme_customer_profile_audit(auth_user_id,actor_auth_user_id,changed_fields,before_state,after_state)
  values(p_auth_user_id,p_auth_user_id,v_changed,v_before,v_after);
 end if;
 return v_after;
end;
$$;
grant execute on function public.mme_customer_profile_update(uuid,text,boolean,boolean) to authenticated;
comment on table public.mme_customer_profiles is 'Customer-editable display name and notification preferences only; verified identity and contact channels remain in their source systems.';
comment on table public.mme_customer_profile_audit is 'Append-only customer profile change history; inaccessible to browser roles.';
commit;
