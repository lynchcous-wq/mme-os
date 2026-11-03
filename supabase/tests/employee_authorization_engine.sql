-- Manual verification for 20261103000300 and 20261103000400.
-- Run only against a disposable/test Supabase project after applying all
-- employee and authorization migrations. No users or permissions are created.

do $$
declare
  fn oid;
  fn_def text;
begin
  select p.oid, pg_get_functiondef(p.oid)
    into fn, fn_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'mme_employee_authorize_catalog_action'
     and pg_get_function_identity_arguments(p.oid) =
       'p_actor_user_id uuid, p_permission_key text, p_target_product_id uuid, p_submitter_user_id uuid';

  if fn is null then
    raise exception 'Catalog authorization function is missing';
  end if;

  if not (select prosecdef from pg_proc where oid = fn) then
    raise exception 'Authorization function must run with its controlled definer privileges';
  end if;

  if has_function_privilege('anon', fn, 'EXECUTE')
     or has_function_privilege('authenticated', fn, 'EXECUTE') then
    raise exception 'Browser roles must not execute the authorization decision function';
  end if;

  if not has_function_privilege('service_role', fn, 'EXECUTE') then
    raise exception 'Trusted server service_role must be able to execute authorization function';
  end if;

  if position('from public.products' in lower(fn_def)) = 0
     or position('p_actor_user_id = v_product_creator' in fn_def) = 0 then
    raise exception 'Self-approval protection must derive creator from the product row';
  end if;

  if position('p_actor_user_id = p_submitter_user_id' in fn_def) > 0
     or position('p_submitter_user_id is not null' in fn_def) > 0 then
    raise exception 'Authorization function must not trust caller-supplied submitter identity';
  end if;

  if position('employee_access_frozen' in fn_def) = 0
     or position('expires_at > now()' in fn_def) = 0
     or position('employment_status' in fn_def) = 0 then
    raise exception 'Authorization must check freeze, active employment, and grant expiry';
  end if;
end;
$$;

-- Expected result: DO completes without exception.
-- This structural test does not replace runtime tests using test identities,
-- real sessions, RLS, and actual approve/publish requests.
