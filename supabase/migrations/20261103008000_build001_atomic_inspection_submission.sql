-- Build 001: atomic, server-only serialized inspection submission.
-- A submitted device is quarantined while pending manager review.
begin;

create or replace function public.mme_submit_serialized_inspection(
  p_reference text,
  p_unit_id uuid,
  p_inspection_type text,
  p_reason text,
  p_findings jsonb,
  p_battery_health_percent integer,
  p_battery_test text,
  p_screen_test text,
  p_camera_test text,
  p_charging_port_test text,
  p_buttons_audio_test text,
  p_connectivity_test text,
  p_imei_serial_verification text,
  p_activation_lock_status text,
  p_notes text,
  p_actor_user_id uuid,
  p_actor_identity_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit record;
  v_inspection_id uuid;
begin
  if p_actor_user_id is null or p_actor_identity_id is null
     or p_unit_id is null
     or p_reference is null or length(btrim(p_reference)) < 3 or length(p_reference) > 100
     or p_reason is null or length(btrim(p_reason)) < 5
     or p_findings is null or jsonb_typeof(p_findings) <> 'object'
     or p_battery_health_percent is not null and p_battery_health_percent not between 0 and 100
     or p_battery_test not in ('pass','fail','not_applicable')
     or p_screen_test not in ('pass','fail','not_applicable')
     or p_camera_test not in ('pass','fail','not_applicable')
     or p_charging_port_test not in ('pass','fail','not_applicable')
     or p_buttons_audio_test not in ('pass','fail','not_applicable')
     or p_connectivity_test not in ('pass','fail','not_applicable')
     or p_imei_serial_verification not in ('pass','fail','not_applicable')
     or p_activation_lock_status not in ('clear','locked','not_applicable')
     or p_notes is null or length(p_notes) > 4000
     or p_battery_health_percent is not null and p_battery_test = 'not_applicable' then
    raise exception 'Inspection submission is incomplete or invalid' using errcode = '22023';
  end if;

  select id, product_id, location_id, unit_status
    into v_unit
    from public.mme_serialized_units
   where id = p_unit_id
   for update;

  if not found or v_unit.unit_status not in ('in_stock','sold') then
    raise exception 'Device is not eligible for a new inspection' using errcode = 'P0001';
  end if;

  if not public.mme_employee_authorize_inventory_action(
    p_actor_user_id,
    'inventory.inspection.submit',
    v_unit.product_id,
    v_unit.location_id
  ) then
    raise exception 'Employee is not authorized to submit this inspection' using errcode = '42501';
  end if;

  -- Keep the device out of sale inventory until a separately authorized
  -- manager resolves the pending inspection.
  v_inspection_id := public.mme_inspect_serialized_unit(
    p_reference,
    p_unit_id,
    p_inspection_type,
    'quarantine',
    p_reason,
    p_findings,
    '[]'::jsonb,
    p_actor_identity_id,
    null
  );

  perform public.mme_record_serialized_device_tests(
    v_inspection_id,
    p_battery_health_percent,
    p_battery_test,
    p_screen_test,
    p_camera_test,
    p_charging_port_test,
    p_buttons_audio_test,
    p_connectivity_test,
    p_imei_serial_verification,
    p_activation_lock_status,
    p_notes,
    p_actor_identity_id
  );

  return v_inspection_id;
end;
$$;

revoke all on function public.mme_submit_serialized_inspection(
  text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid
) from public, anon, authenticated;
grant execute on function public.mme_submit_serialized_inspection(
  text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid
) to service_role;

comment on function public.mme_submit_serialized_inspection(
  text,uuid,text,text,jsonb,integer,text,text,text,text,text,text,text,text,text,uuid,uuid
) is
  'Atomic server-only inspection submission. Checks active employee permission and unit scope, quarantines the device pending review, and records checklist results in one transaction. Actor identity mapping must be resolved by trusted server code.';

commit;
