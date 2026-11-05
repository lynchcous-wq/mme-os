-- Build 001: structured device inspection checklist.
-- Results are linked to one serialized-unit inspection; raw IMEI/serial values are
-- deliberately not duplicated into this checklist table.
begin;

create table public.mme_serialized_device_test_results (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null unique
    references public.mme_inventory_inspections(id) on delete restrict,
  battery_health_percent integer
    check (battery_health_percent is null or battery_health_percent between 0 and 100),
  battery_test text not null default 'not_tested'
    check (battery_test in ('not_tested','pass','fail','not_applicable')),
  screen_test text not null default 'not_tested'
    check (screen_test in ('not_tested','pass','fail','not_applicable')),
  camera_test text not null default 'not_tested'
    check (camera_test in ('not_tested','pass','fail','not_applicable')),
  charging_port_test text not null default 'not_tested'
    check (charging_port_test in ('not_tested','pass','fail','not_applicable')),
  buttons_audio_test text not null default 'not_tested'
    check (buttons_audio_test in ('not_tested','pass','fail','not_applicable')),
  connectivity_test text not null default 'not_tested'
    check (connectivity_test in ('not_tested','pass','fail','not_applicable')),
  imei_serial_verification text not null default 'not_tested'
    check (imei_serial_verification in ('not_tested','pass','fail','not_applicable')),
  activation_lock_status text not null default 'not_tested'
    check (activation_lock_status in ('not_tested','clear','locked','not_applicable')),
  notes text not null default '' check (length(notes) <= 4000),
  tested_by_identity_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (battery_health_percent is null or battery_test <> 'not_tested')
);

create index mme_serialized_device_test_results_created_idx
  on public.mme_serialized_device_test_results(created_at desc);

alter table public.mme_serialized_device_test_results enable row level security;
revoke all on public.mme_serialized_device_test_results from public, anon, authenticated;
grant all on public.mme_serialized_device_test_results to service_role;

create or replace function public.mme_record_serialized_device_tests(
  p_inspection_id uuid,
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
  p_actor_identity_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection record;
  v_result_id uuid;
begin
  if p_inspection_id is null or p_actor_identity_id is null
     or p_battery_health_percent is not null and p_battery_health_percent not between 0 and 100
     or p_battery_test not in ('not_tested','pass','fail','not_applicable')
     or p_screen_test not in ('not_tested','pass','fail','not_applicable')
     or p_camera_test not in ('not_tested','pass','fail','not_applicable')
     or p_charging_port_test not in ('not_tested','pass','fail','not_applicable')
     or p_buttons_audio_test not in ('not_tested','pass','fail','not_applicable')
     or p_connectivity_test not in ('not_tested','pass','fail','not_applicable')
     or p_imei_serial_verification not in ('not_tested','pass','fail','not_applicable')
     or p_activation_lock_status not in ('not_tested','clear','locked','not_applicable')
     or p_notes is null or length(p_notes)>4000
     or p_battery_health_percent is not null and p_battery_test='not_tested' then
    raise exception 'Invalid serialized device test checklist' using errcode='22023';
  end if;

  select id, serialized_unit_id, disposition
    into v_inspection
    from public.mme_inventory_inspections
   where id=p_inspection_id
   for update;

  if not found or v_inspection.serialized_unit_id is null
     or v_inspection.disposition <> 'pending' then
    raise exception 'A pending serialized-unit inspection is required' using errcode='P0002';
  end if;

  insert into public.mme_serialized_device_test_results(
    inspection_id,battery_health_percent,battery_test,screen_test,camera_test,
    charging_port_test,buttons_audio_test,connectivity_test,
    imei_serial_verification,activation_lock_status,notes,tested_by_identity_id
  ) values (
    p_inspection_id,p_battery_health_percent,p_battery_test,p_screen_test,p_camera_test,
    p_charging_port_test,p_buttons_audio_test,p_connectivity_test,
    p_imei_serial_verification,p_activation_lock_status,btrim(p_notes),p_actor_identity_id
  )
  on conflict (inspection_id) do update set
    battery_health_percent=excluded.battery_health_percent,
    battery_test=excluded.battery_test,
    screen_test=excluded.screen_test,
    camera_test=excluded.camera_test,
    charging_port_test=excluded.charging_port_test,
    buttons_audio_test=excluded.buttons_audio_test,
    connectivity_test=excluded.connectivity_test,
    imei_serial_verification=excluded.imei_serial_verification,
    activation_lock_status=excluded.activation_lock_status,
    notes=excluded.notes,
    tested_by_identity_id=excluded.tested_by_identity_id,
    updated_at=now()
  returning id into v_result_id;

  return v_result_id;
end;
$$;

revoke all on function public.mme_record_serialized_device_tests(uuid,integer,text,text,text,text,text,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_record_serialized_device_tests(uuid,integer,text,text,text,text,text,text,text,text,text,uuid) to service_role;

comment on table public.mme_serialized_device_test_results is
  'Structured battery, screen, camera, charging, connectivity, identity and activation-lock checklist for serialized device inspections.';

commit;
