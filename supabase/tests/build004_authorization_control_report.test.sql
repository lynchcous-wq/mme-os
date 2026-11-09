begin;

select plan(12);

select has_function(
  'public',
  'mme_employee_authorization_control_report',
  array[]::text[],
  'CEO and freeze control report exists'
);
select ok(
  has_function_privilege('service_role',
    'public.mme_employee_authorization_control_report()', 'execute'),
  'service_role can execute control report'
);
select ok(
  not has_function_privilege('anon',
    'public.mme_employee_authorization_control_report()', 'execute'),
  'anon cannot execute control report'
);
select ok(
  not has_function_privilege('authenticated',
    'public.mme_employee_authorization_control_report()', 'execute'),
  'authenticated cannot execute control report'
);

select is(
  (select legacy_control_configured
   from public.mme_employee_authorization_control_report()),
  false,
  'fresh environment with unprovisioned CEO is reported as unconfigured'
);
select is(
  (select employee_access_frozen
   from public.mme_employee_authorization_control_report()),
  false,
  'fresh environment reports global freeze off'
);
select is(
  (select ceo_identity_linked
   from public.mme_employee_authorization_control_report()),
  false,
  'unprovisioned CEO is not treated as linked'
);
select is(
  (select ceo_legacy_employee_active
   from public.mme_employee_authorization_control_report()),
  false,
  'unprovisioned CEO is not reported as an active legacy employee'
);
select is(
  (select build004_whole_login_locked
   from public.mme_employee_authorization_control_report()),
  false,
  'missing CEO identity does not produce a null whole-login lock diagnostic'
);

update public.employee_security_settings
set employee_access_frozen = true,
    freeze_reason = 'Build 004 control-report test'
where singleton = true;

select is(
  (select employee_access_frozen
   from public.mme_employee_authorization_control_report()),
  true,
  'control report reflects legacy global freeze'
);
select is(
  (select freeze_reason_present
   from public.mme_employee_authorization_control_report()),
  true,
  'control report indicates freeze reason is present without exposing its contents'
);

update public.employee_security_settings
set employee_access_frozen = false,
    freeze_reason = null
where singleton = true;

select is(
  (select employee_access_frozen
   from public.mme_employee_authorization_control_report()),
  false,
  'control report reflects restored global freeze state'
);

select * from finish();
rollback;
