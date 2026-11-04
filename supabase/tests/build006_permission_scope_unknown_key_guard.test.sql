begin;
select plan(7);

select has_function('public','mme_employee_authorize_task_action',
  array['uuid','text','text','uuid'],'task authorization function exists');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_employee_authorize_task_action'
     and pg_get_functiondef(p.oid) like '%g.scope - array[''department'',''location_id'']::text[]%'
),'unknown scope keys are explicitly rejected');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_employee_authorize_task_action'
     and pg_get_functiondef(p.oid) like '%g.scope=''{}''::jsonb%'
),'global scope must be explicitly empty object');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_employee_authorize_task_action'
     and pg_get_functiondef(p.oid) like '%g.scope->>''department''=p_department%'
),'department scope must match target department');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_employee_authorize_task_action'
     and pg_get_functiondef(p.oid) like '%p_location_id is not null and g.scope->>''location_id''=p_location_id::text%'
),'location scope must match a supplied target location');

select ok(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mme_employee_authorize_task_action'
     and pg_get_functiondef(p.oid) like '%v_employment_status is distinct from ''active''%'
),'employee must remain active');

select ok(not has_function_privilege('authenticated',
  'public.mme_employee_authorize_task_action(uuid,text,text,uuid)','execute'),
  'browser role cannot directly call authorization decision point');

select * from finish();
rollback;
