begin;

-- Build 004: read-only dry-run of legacy employee permission grants.
-- Produces proposed mappings only. It never creates roles or grants.
create or replace function public.mme_employee_permission_migration_dry_run()
returns table (
  source_grant_id uuid,
  legacy_user_id uuid,
  person_identity_id uuid,
  build004_employee_relationship_id uuid,
  source_permission_key text,
  source_grant_status text,
  proposed_resource_key text,
  proposed_action_key text,
  proposed_scope jsonb,
  mapping_status text,
  review_reasons text[]
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with grant_rows as (
    select
      g.id as source_grant_id,
      g.employee_user_id as legacy_user_id,
      p.id as person_identity_id,
      e.id as build004_employee_relationship_id,
      g.permission_key as source_permission_key,
      g.scope as source_scope,
      coalesce((
        select s.ceo_user_id is not null
           and s.employee_access_frozen is false
        from public.employee_security_settings s
        where s.singleton is true
      ), false) as legacy_controls_ready,
      case
        when g.revoked_at is not null then 'revoked'
        when g.expires_at is not null and g.expires_at <= statement_timestamp() then 'expired'
        else 'active'
      end as source_grant_status,
      case
        when g.permission_key in (
          'inventory.inspection.view',
          'inventory.inspection.submit',
          'inventory.inspection.resolve',
          'inventory.inspection.approve'
        ) then 'inventory.inspection'
        when g.permission_key in ('catalog.approve','catalog.publish') then 'catalog'
        when g.permission_key ~ '^tasks\.[a-z][a-z0-9_.:-]{0,80}$' then 'tasks'
        else null
      end as proposed_resource_key,
      case
        when g.permission_key like 'inventory.inspection.%'
          then substring(g.permission_key from length('inventory.inspection.') + 1)
        when g.permission_key like 'catalog.%'
          then substring(g.permission_key from length('catalog.') + 1)
        when g.permission_key ~ '^tasks\.[a-z][a-z0-9_.:-]{0,80}$'
          then substring(g.permission_key from length('tasks.') + 1)
        else null
      end as proposed_action_key
    from public.employee_permission_grants g
    left join public.mme_person_identities p on p.auth_user_id = g.employee_user_id
    left join public.mme_employee_relationships e on e.person_identity_id = p.id
  ),
  assessed as (
    select
      x.*,
      case
        when x.source_permission_key like 'inventory.inspection.%' then
          (x.source_scope = '{}'::jsonb
            or (x.source_scope ? 'product_id'
                and x.source_scope - 'product_id' = '{}'::jsonb
                and (x.source_scope ->> 'product_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
            or (x.source_scope ? 'location_id'
                and x.source_scope - 'location_id' = '{}'::jsonb
                and (x.source_scope ->> 'location_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
        when x.source_permission_key in ('catalog.approve','catalog.publish') then
          (x.source_scope = '{}'::jsonb
            or (x.source_scope ? 'product_id'
                and x.source_scope - 'product_id' = '{}'::jsonb
                and (x.source_scope ->> 'product_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
        when x.source_permission_key ~ '^tasks\.[a-z][a-z0-9_.:-]{0,80}$' then
          (x.source_scope = '{}'::jsonb
            or (
              jsonb_typeof(x.source_scope) = 'object'
              and (x.source_scope - array['department','location_id']::text[]) = '{}'::jsonb
              and (
                (x.source_scope ? 'department'
                 and nullif(btrim(x.source_scope ->> 'department'),'') is not null)
                or (x.source_scope ? 'location_id'
                    and nullif(btrim(x.source_scope ->> 'location_id'),'') is not null)
              )
              and (
                not (x.source_scope ? 'location_id')
                or (x.source_scope ->> 'location_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              )
            ))
        else false
      end as scope_is_compatible
    from grant_rows x
  )
  select
    a.source_grant_id,
    a.legacy_user_id,
    a.person_identity_id,
    a.build004_employee_relationship_id,
    a.source_permission_key,
    a.source_grant_status,
    a.proposed_resource_key,
    a.proposed_action_key,
    case when a.proposed_resource_key is null then null else a.source_scope end,
    case
      when a.source_grant_status <> 'active' then 'inactive'
      when a.proposed_resource_key is null then 'unsupported'
      when a.person_identity_id is null then 'review_required'
      when a.build004_employee_relationship_id is null then 'review_required'
      when not a.scope_is_compatible then 'review_required'
      when not a.legacy_controls_ready then 'review_required'
      else 'mapping_candidate'
    end,
    array_remove(array[
      case when a.source_grant_status = 'revoked' then 'source grant is revoked' end,
      case when a.source_grant_status = 'expired' then 'source grant is expired' end,
      case when a.proposed_resource_key is null then 'permission key has no approved crosswalk' end,
      case when a.person_identity_id is null then 'legacy user has no Build 004 person identity' end,
      case when a.person_identity_id is not null and a.build004_employee_relationship_id is null
        then 'person identity has no Build 004 employee relationship' end,
      case when a.proposed_resource_key is not null and not a.scope_is_compatible
        then 'scope is not canonical for the proposed resource' end,
      case when not a.legacy_controls_ready
        then 'legacy CEO provisioning is missing or global employee access is frozen; parity review required' end
    ], null)::text[]
  from assessed a
  order by a.legacy_user_id, a.source_permission_key, a.source_grant_id;
$$;

revoke all on function public.mme_employee_permission_migration_dry_run()
  from public, anon, authenticated;
grant execute on function public.mme_employee_permission_migration_dry_run()
  to service_role;

comment on function public.mme_employee_permission_migration_dry_run() is
  'Build 004 read-only permission migration dry run. Maps known legacy permission keys, checks legacy scope shape and identity linkage, and classifies each source grant. Does not write roles, assignments, grants, audit events, or employee records. Service-role execution only.';

commit;
)
            or (x.source_scope ? 'location_id'
                and x.source_scope - 'location_id' = '{}'::jsonb
                and nullif(btrim(x.source_scope ->> 'location_id'),'') is not null))
        when x.source_permission_key in ('catalog.approve','catalog.publish') then
          (x.source_scope = '{}'::jsonb
            or (x.source_scope ? 'product_id'
                and x.source_scope - 'product_id' = '{}'::jsonb
                and nullif(btrim(x.source_scope ->> 'product_id'),'') is not null))
        when x.source_permission_key ~ '^tasks\.[a-z][a-z0-9_.:-]{0,80}$' then
          (x.source_scope = '{}'::jsonb
            or (
              jsonb_typeof(x.source_scope) = 'object'
              and (x.source_scope - array['department','location_id']::text[]) = '{}'::jsonb
              and (
                (x.source_scope ? 'department'
                 and nullif(btrim(x.source_scope ->> 'department'),'') is not null)
                or (x.source_scope ? 'location_id'
                    and nullif(btrim(x.source_scope ->> 'location_id'),'') is not null)
              )
              and (
                not (x.source_scope ? 'location_id')
                or (x.source_scope ->> 'location_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              )
            ))
        else false
      end as scope_is_compatible
    from grant_rows x
  )
  select
    a.source_grant_id,
    a.legacy_user_id,
    a.person_identity_id,
    a.build004_employee_relationship_id,
    a.source_permission_key,
    a.source_grant_status,
    a.proposed_resource_key,
    a.proposed_action_key,
    case when a.proposed_resource_key is null then null else a.source_scope end,
    case
      when a.source_grant_status <> 'active' then 'inactive'
      when a.proposed_resource_key is null then 'unsupported'
      when a.person_identity_id is null then 'review_required'
      when a.build004_employee_relationship_id is null then 'review_required'
      when not a.scope_is_compatible then 'review_required'
      when not a.legacy_controls_ready then 'review_required'
      else 'mapping_candidate'
    end,
    array_remove(array[
      case when a.source_grant_status = 'revoked' then 'source grant is revoked' end,
      case when a.source_grant_status = 'expired' then 'source grant is expired' end,
      case when a.proposed_resource_key is null then 'permission key has no approved crosswalk' end,
      case when a.person_identity_id is null then 'legacy user has no Build 004 person identity' end,
      case when a.person_identity_id is not null and a.build004_employee_relationship_id is null
        then 'person identity has no Build 004 employee relationship' end,
      case when a.proposed_resource_key is not null and not a.scope_is_compatible
        then 'scope is not canonical for the proposed resource' end,
      case when not a.legacy_controls_ready
        then 'legacy CEO provisioning is missing or global employee access is frozen; parity review required' end
    ], null)::text[]
  from assessed a
  order by a.legacy_user_id, a.source_permission_key, a.source_grant_id;
$$;

revoke all on function public.mme_employee_permission_migration_dry_run()
  from public, anon, authenticated;
grant execute on function public.mme_employee_permission_migration_dry_run()
  to service_role;

comment on function public.mme_employee_permission_migration_dry_run() is
  'Build 004 read-only permission migration dry run. Maps known legacy permission keys, checks legacy scope shape and identity linkage, and classifies each source grant. Does not write roles, assignments, grants, audit events, or employee records. Service-role execution only.';

commit;
))
        when x.source_permission_key in ('catalog.approve','catalog.publish') then
          (x.source_scope = '{}'::jsonb
            or (x.source_scope ? 'product_id'
                and x.source_scope - 'product_id' = '{}'::jsonb
                and nullif(btrim(x.source_scope ->> 'product_id'),'') is not null))
        when x.source_permission_key ~ '^tasks\.[a-z][a-z0-9_.:-]{0,80}$' then
          (x.source_scope = '{}'::jsonb
            or (
              jsonb_typeof(x.source_scope) = 'object'
              and (x.source_scope - array['department','location_id']::text[]) = '{}'::jsonb
              and (
                (x.source_scope ? 'department'
                 and nullif(btrim(x.source_scope ->> 'department'),'') is not null)
                or (x.source_scope ? 'location_id'
                    and nullif(btrim(x.source_scope ->> 'location_id'),'') is not null)
              )
              and (
                not (x.source_scope ? 'location_id')
                or (x.source_scope ->> 'location_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              )
            ))
        else false
      end as scope_is_compatible
    from grant_rows x
  )
  select
    a.source_grant_id,
    a.legacy_user_id,
    a.person_identity_id,
    a.build004_employee_relationship_id,
    a.source_permission_key,
    a.source_grant_status,
    a.proposed_resource_key,
    a.proposed_action_key,
    case when a.proposed_resource_key is null then null else a.source_scope end,
    case
      when a.source_grant_status <> 'active' then 'inactive'
      when a.proposed_resource_key is null then 'unsupported'
      when a.person_identity_id is null then 'review_required'
      when a.build004_employee_relationship_id is null then 'review_required'
      when not a.scope_is_compatible then 'review_required'
      when not a.legacy_controls_ready then 'review_required'
      else 'mapping_candidate'
    end,
    array_remove(array[
      case when a.source_grant_status = 'revoked' then 'source grant is revoked' end,
      case when a.source_grant_status = 'expired' then 'source grant is expired' end,
      case when a.proposed_resource_key is null then 'permission key has no approved crosswalk' end,
      case when a.person_identity_id is null then 'legacy user has no Build 004 person identity' end,
      case when a.person_identity_id is not null and a.build004_employee_relationship_id is null
        then 'person identity has no Build 004 employee relationship' end,
      case when a.proposed_resource_key is not null and not a.scope_is_compatible
        then 'scope is not canonical for the proposed resource' end,
      case when not a.legacy_controls_ready
        then 'legacy CEO provisioning is missing or global employee access is frozen; parity review required' end
    ], null)::text[]
  from assessed a
  order by a.legacy_user_id, a.source_permission_key, a.source_grant_id;
$$;

revoke all on function public.mme_employee_permission_migration_dry_run()
  from public, anon, authenticated;
grant execute on function public.mme_employee_permission_migration_dry_run()
  to service_role;

comment on function public.mme_employee_permission_migration_dry_run() is
  'Build 004 read-only permission migration dry run. Maps known legacy permission keys, checks legacy scope shape and identity linkage, and classifies each source grant. Does not write roles, assignments, grants, audit events, or employee records. Service-role execution only.';

commit;
)
            or (x.source_scope ? 'location_id'
                and x.source_scope - 'location_id' = '{}'::jsonb
                and nullif(btrim(x.source_scope ->> 'location_id'),'') is not null))
        when x.source_permission_key in ('catalog.approve','catalog.publish') then
          (x.source_scope = '{}'::jsonb
            or (x.source_scope ? 'product_id'
                and x.source_scope - 'product_id' = '{}'::jsonb
                and nullif(btrim(x.source_scope ->> 'product_id'),'') is not null))
        when x.source_permission_key ~ '^tasks\.[a-z][a-z0-9_.:-]{0,80}$' then
          (x.source_scope = '{}'::jsonb
            or (
              jsonb_typeof(x.source_scope) = 'object'
              and (x.source_scope - array['department','location_id']::text[]) = '{}'::jsonb
              and (
                (x.source_scope ? 'department'
                 and nullif(btrim(x.source_scope ->> 'department'),'') is not null)
                or (x.source_scope ? 'location_id'
                    and nullif(btrim(x.source_scope ->> 'location_id'),'') is not null)
              )
              and (
                not (x.source_scope ? 'location_id')
                or (x.source_scope ->> 'location_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              )
            ))
        else false
      end as scope_is_compatible
    from grant_rows x
  )
  select
    a.source_grant_id,
    a.legacy_user_id,
    a.person_identity_id,
    a.build004_employee_relationship_id,
    a.source_permission_key,
    a.source_grant_status,
    a.proposed_resource_key,
    a.proposed_action_key,
    case when a.proposed_resource_key is null then null else a.source_scope end,
    case
      when a.source_grant_status <> 'active' then 'inactive'
      when a.proposed_resource_key is null then 'unsupported'
      when a.person_identity_id is null then 'review_required'
      when a.build004_employee_relationship_id is null then 'review_required'
      when not a.scope_is_compatible then 'review_required'
      when not a.legacy_controls_ready then 'review_required'
      else 'mapping_candidate'
    end,
    array_remove(array[
      case when a.source_grant_status = 'revoked' then 'source grant is revoked' end,
      case when a.source_grant_status = 'expired' then 'source grant is expired' end,
      case when a.proposed_resource_key is null then 'permission key has no approved crosswalk' end,
      case when a.person_identity_id is null then 'legacy user has no Build 004 person identity' end,
      case when a.person_identity_id is not null and a.build004_employee_relationship_id is null
        then 'person identity has no Build 004 employee relationship' end,
      case when a.proposed_resource_key is not null and not a.scope_is_compatible
        then 'scope is not canonical for the proposed resource' end,
      case when not a.legacy_controls_ready
        then 'legacy CEO provisioning is missing or global employee access is frozen; parity review required' end
    ], null)::text[]
  from assessed a
  order by a.legacy_user_id, a.source_permission_key, a.source_grant_id;
$$;

revoke all on function public.mme_employee_permission_migration_dry_run()
  from public, anon, authenticated;
grant execute on function public.mme_employee_permission_migration_dry_run()
  to service_role;

comment on function public.mme_employee_permission_migration_dry_run() is
  'Build 004 read-only permission migration dry run. Maps known legacy permission keys, checks legacy scope shape and identity linkage, and classifies each source grant. Does not write roles, assignments, grants, audit events, or employee records. Service-role execution only.';

commit;
