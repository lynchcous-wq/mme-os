-- Build 004 resolver integration smoke test.
-- Runs only against the disposable local Supabase database in CI.
-- All fixture writes are rolled back; no production identities are touched.
begin;

do $$
declare
  v_verified_auth uuid := 'f1000000-0000-4000-8000-000000000001';
  v_pending_auth uuid := 'f1000000-0000-4000-8000-000000000002';
  v_revoked_auth uuid := 'f1000000-0000-4000-8000-000000000003';
  v_locked_auth uuid := 'f1000000-0000-4000-8000-000000000004';
  v_verified_person uuid := 'f2000000-0000-4000-8000-000000000001';
  v_pending_person uuid := 'f2000000-0000-4000-8000-000000000002';
  v_revoked_person uuid := 'f2000000-0000-4000-8000-000000000003';
  v_locked_person uuid := 'f2000000-0000-4000-8000-000000000004';
begin
  insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (v_verified_auth, 'authenticated', 'authenticated', 'build004-verified@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_pending_auth, 'authenticated', 'authenticated', 'build004-pending@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_revoked_auth, 'authenticated', 'authenticated', 'build004-revoked@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_locked_auth, 'authenticated', 'authenticated', 'build004-locked@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

  insert into public.mme_person_identities(person_id, lifecycle_status)
  values (v_verified_person, 'active'), (v_pending_person, 'active'),
         (v_revoked_person, 'active'), (v_locked_person, 'locked');

  insert into public.mme_login_identities
    (person_id, provider_key, provider_subject, auth_user_id, link_status, verified_at, revoked_at)
  values
    (v_verified_person, 'supabase', v_verified_auth::text, v_verified_auth, 'verified', now(), null),
    (v_pending_person, 'supabase', v_pending_auth::text, v_pending_auth, 'pending', null, null),
    (v_revoked_person, 'supabase', v_revoked_auth::text, v_revoked_auth, 'revoked', now(), now()),
    (v_locked_person, 'supabase', v_locked_auth::text, v_locked_auth, 'verified', now(), null);

  if public.mme_resolve_person_for_auth_subject(v_verified_auth) is distinct from v_verified_person then
    raise exception 'verified active login must resolve to its person identity';
  end if;
  if public.mme_resolve_person_for_auth_subject(v_pending_auth) is not null then
    raise exception 'pending login identity must not resolve';
  end if;
  if public.mme_resolve_person_for_auth_subject(v_revoked_auth) is not null then
    raise exception 'revoked login identity must not resolve';
  end if;
  if public.mme_resolve_person_for_auth_subject(v_locked_auth) is not null then
    raise exception 'login mapped to locked person must not resolve';
  end if;
  if public.mme_resolve_person_for_auth_subject(null) is not null then
    raise exception 'null auth subject must not resolve';
  end if;
end;
$$;

rollback;
