-- Build 004 person-keyed authorization integration tests.
-- Executes actual PL/pgSQL decision functions with synthetic rows only.
-- The surrounding transaction is always rolled back in the disposable CI DB.
begin;

select plan(1);

do $$
declare
  v_actor_user uuid := 'f3000000-0000-4000-8000-000000000001';
  v_expired_user uuid := 'f3000000-0000-4000-8000-000000000002';
  v_revoked_user uuid := 'f3000000-0000-4000-8000-000000000003';
  v_terminated_user uuid := 'f3000000-0000-4000-8000-000000000004';
  v_locked_user uuid := 'f3000000-0000-4000-8000-000000000005';
  v_ceo_user uuid := 'f3000000-0000-4000-8000-000000000006';
  v_approver_user uuid := 'f3000000-0000-4000-8000-000000000007';
  v_actor uuid := 'f4000000-0000-4000-8000-000000000001';
  v_expired uuid := 'f4000000-0000-4000-8000-000000000002';
  v_revoked uuid := 'f4000000-0000-4000-8000-000000000003';
  v_terminated uuid := 'f4000000-0000-4000-8000-000000000004';
  v_locked uuid := 'f4000000-0000-4000-8000-000000000005';
  v_ceo uuid := 'f4000000-0000-4000-8000-000000000006';
  v_approver uuid := 'f4000000-0000-4000-8000-000000000007';
  v_product uuid := 'f5000000-0000-4000-8000-000000000001';
  v_other_product uuid := 'f5000000-0000-4000-8000-000000000002';
  v_location uuid := 'f6000000-0000-4000-8000-000000000001';
  v_other_location uuid := 'f6000000-0000-4000-8000-000000000002';
  v_category uuid;
begin
  insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (v_actor_user, 'authenticated', 'authenticated', 'build004-actor@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_expired_user, 'authenticated', 'authenticated', 'build004-expired@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_revoked_user, 'authenticated', 'authenticated', 'build004-revoked-grant@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_terminated_user, 'authenticated', 'authenticated', 'build004-terminated@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_locked_user, 'authenticated', 'authenticated', 'build004-locked-actor@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_ceo_user, 'authenticated', 'authenticated', 'build004-ceo@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_approver_user, 'authenticated', 'authenticated', 'build004-approver@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

  insert into public.mme_person_identities(person_id, lifecycle_status)
  values (v_actor, 'active'), (v_expired, 'active'), (v_revoked, 'active'),
         (v_terminated, 'active'), (v_locked, 'locked'), (v_ceo, 'active'),
         (v_approver, 'active');

  insert into public.employee_relationships(user_id, person_id, employment_status, terminated_at)
  values
    (v_actor_user, v_actor, 'active', null),
    (v_expired_user, v_expired, 'active', null),
    (v_revoked_user, v_revoked, 'active', null),
    (v_terminated_user, v_terminated, 'terminated', now()),
    (v_locked_user, v_locked, 'active', null),
    (v_ceo_user, v_ceo, 'active', null),
    (v_approver_user, v_approver, 'active', null);

  update public.employee_security_settings
     set ceo_person_id = v_ceo, employee_access_frozen = false, freeze_reason = null
   where singleton = true;


  insert into public.mme_login_identities
    (person_id, provider_key, provider_subject, auth_user_id, link_status, verified_at, revoked_at)
  values
    (v_actor, 'supabase', v_actor_user::text, v_actor_user, 'verified', now(), null),
    (v_approver, 'supabase', v_approver_user::text, v_approver_user, 'verified', now(), null);

  insert into public.employee_permission_grants
    (employee_user_id, person_id, permission_key, scope, granted_by_user_id,
     granted_at, expires_at, revoked_at, revoked_by_user_id, reason)
  values
    (v_approver_user, v_approver, 'catalog.approve', '{}'::jsonb,
     v_ceo_user, now(), null, null, null, 'Synthetic catalog approval grant');

  select id into v_category from public.product_categories where slug = 'televisions' limit 1;
  insert into public.products
    (id, category_id, sku, slug, name, catalog_status, created_by)
  values
    (v_product, v_category, 'BUILD004-APPROVAL-001', 'build004-approval-001',
     'Synthetic approval test product', 'pending_approval', v_actor_user);

  if public.mme_person_authorize_catalog_action(v_actor, 'catalog.approve', v_product) then
    raise exception 'catalog creator must not approve their own product';
  end if;
  if not public.mme_person_authorize_catalog_action(v_approver, 'catalog.approve', v_product) then
    raise exception 'separate authorized approver should be allowed to approve pending product';
  end if;
  if public.mme_person_authorize_catalog_action(v_approver, 'catalog.approve', v_other_product) then
    raise exception 'approver must not approve an unknown or unmapped product';
  end if;

  insert into public.employee_permission_grants
    (employee_user_id, person_id, permission_key, scope, granted_by_user_id,
     granted_at, expires_at, revoked_at, revoked_by_user_id, reason)
  values
    (v_actor_user, v_actor, 'catalog.edit', jsonb_build_object('product_id', v_product::text),
     v_ceo_user, now(), null, null, null, 'Synthetic scoped active grant'),
    (v_actor_user, v_actor, 'inventory.inspection.view', jsonb_build_object('location_id', v_location::text),
     v_ceo_user, now(), null, null, null, 'Synthetic scoped active grant'),
    (v_expired_user, v_expired, 'catalog.edit', '{}'::jsonb,
     v_ceo_user, now() - interval '2 days', now() - interval '1 day', null, null, 'Synthetic expired grant'),
    (v_revoked_user, v_revoked, 'catalog.edit', '{}'::jsonb,
     v_ceo_user, now() - interval '2 days', null, now(), v_ceo_user, 'Synthetic revoked grant');

  if not public.mme_person_authorize_catalog_action(v_actor, 'catalog.edit', v_product) then
    raise exception 'active person with matching product scope should be authorized';
  end if;
  if public.mme_person_authorize_catalog_action(v_actor, 'catalog.edit', v_other_product) then
    raise exception 'product-scoped grant must not authorize a different product';
  end if;
  if not public.mme_person_authorize_inventory_action(v_actor, 'inventory.inspection.view', null, v_location) then
    raise exception 'active person with matching location scope should be authorized';
  end if;
  if public.mme_person_authorize_inventory_action(v_actor, 'inventory.inspection.view', null, v_other_location) then
    raise exception 'location-scoped grant must not authorize a different location';
  end if;
  if public.mme_person_authorize_catalog_action(v_expired, 'catalog.edit', null) then
    raise exception 'expired grant must be denied';
  end if;
  if public.mme_person_authorize_catalog_action(v_revoked, 'catalog.edit', null) then
    raise exception 'revoked grant must be denied';
  end if;
  if public.mme_person_authorize_catalog_action(v_terminated, 'catalog.edit', null) then
    raise exception 'terminated employee must be denied';
  end if;
  if public.mme_person_authorize_catalog_action(v_locked, 'catalog.edit', null) then
    raise exception 'locked person identity must be denied';
  end if;
  if not public.mme_person_authorize_catalog_action(v_ceo, 'catalog.edit', null) then
    raise exception 'configured active CEO should retain authorized catalog access';
  end if;

  update public.employee_security_settings
     set employee_access_frozen = true, freeze_reason = 'Synthetic integration test freeze'
   where singleton = true;
  if public.mme_person_authorize_catalog_action(v_actor, 'catalog.edit', v_product) then
    raise exception 'frozen employee access must deny ordinary employee actions';
  end if;

  update public.employee_security_settings
     set employee_access_frozen = false, freeze_reason = null, ceo_person_id = null
   where singleton = true;
  if public.mme_person_authorize_catalog_action(v_actor, 'catalog.edit', v_product) then
    raise exception 'missing CEO configuration must fail closed';
  end if;
end;
$$;

select pass('Build 004 SQL assertions completed without exception');
select * from finish();

rollback;
