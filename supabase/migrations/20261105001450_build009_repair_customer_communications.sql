-- Build 009.65 — customer-safe repair timeline, appointment scheduling and notification outbox.
begin;
create table public.mme_repair_customer_preferences (
 customer_identity_id uuid primary key,
 email_enabled boolean not null default true,
 sms_enabled boolean not null default false,
 preferred_channel text not null default 'email' check(preferred_channel in ('email','sms','none')),
 consent_recorded_at timestamptz,
 consent_source text,
 updated_at timestamptz not null default now(),
 check(preferred_channel<>'sms' or sms_enabled),
 check(preferred_channel<>'none' or (not email_enabled and not sms_enabled))
);
create table public.mme_repair_appointments (
 appointment_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 customer_identity_id uuid not null,
 location_id uuid references public.mme_store_locations(id) on delete restrict,
 appointment_type text not null check(appointment_type in ('drop_off','diagnostic','consultation','pickup')),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'requested' check(status in ('requested','confirmed','rescheduled','cancelled','completed','no_show')),
 created_by uuid not null,
 updated_by uuid,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(ends_at>starts_at)
);
create index mme_repair_appointments_schedule_idx on public.mme_repair_appointments(location_id,starts_at,status);
create index mme_repair_appointments_case_idx on public.mme_repair_appointments(repair_case_id,starts_at desc);

create table public.mme_repair_customer_timeline (
 timeline_event_id bigint generated always as identity primary key,
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 customer_identity_id uuid not null,
 event_code text not null check(event_code in ('case_received','coverage_review','coverage_decided','diagnosis_started','awaiting_parts','repair_started','quality_check','ready_for_pickup','shipped','completed','appointment_confirmed','appointment_changed','appointment_cancelled','customer_action_required')),
 customer_message text not null check(length(btrim(customer_message)) between 1 and 500),
 visible_at timestamptz not null default now(),
 source_event_id bigint,
 created_at timestamptz not null default now()
);
create index mme_repair_customer_timeline_idx on public.mme_repair_customer_timeline(customer_identity_id,repair_case_id,visible_at desc);

create table public.mme_repair_notification_outbox (
 notification_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 customer_identity_id uuid not null,
 timeline_event_id bigint references public.mme_repair_customer_timeline(timeline_event_id) on delete restrict,
 channel text not null check(channel in ('email','sms')),
 template_code text not null check(template_code in ('repair_status_update','appointment_confirmed','appointment_changed','appointment_cancelled','customer_action_required')),
 payload jsonb not null default '{}'::jsonb check(jsonb_typeof(payload)='object'),
 status text not null default 'queued' check(status in ('queued','processing','sent','failed','suppressed','dead_letter')),
 attempts integer not null default 0 check(attempts>=0),
 available_at timestamptz not null default now(),
 provider_message_id text,
 last_error_code text,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_repair_notification_queue_idx on public.mme_repair_notification_outbox(status,available_at) where status in ('queued','failed');
create index mme_repair_notification_customer_idx on public.mme_repair_notification_outbox(customer_identity_id,created_at desc);

alter table public.mme_repair_customer_preferences enable row level security;
alter table public.mme_repair_appointments enable row level security;
alter table public.mme_repair_customer_timeline enable row level security;
alter table public.mme_repair_notification_outbox enable row level security;
revoke all on public.mme_repair_customer_preferences,public.mme_repair_appointments,public.mme_repair_customer_timeline,public.mme_repair_notification_outbox from public,anon,authenticated;
grant select,insert,update on public.mme_repair_customer_preferences,public.mme_repair_appointments to service_role;
grant select,insert on public.mme_repair_customer_timeline to service_role;
grant select,insert,update on public.mme_repair_notification_outbox to service_role;
revoke update,delete,truncate on public.mme_repair_customer_timeline from public,anon,authenticated,service_role;

create or replace function public.mme_repair_enqueue_customer_update(p_case uuid,p_event_code text,p_message text,p_actor uuid,p_idempotency_key text)
returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_warranty_repair_cases%rowtype; pref public.mme_repair_customer_preferences%rowtype; v bigint; ch text; pref_found boolean:=false;
begin
 if p_actor is null or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Actor and idempotency key required' using errcode='22023'; end if;
 select * into r from public.mme_warranty_repair_cases where repair_case_id=p_case for update;
 if not found then raise exception 'Repair case not found' using errcode='P0002'; end if;
 select * into pref from public.mme_repair_customer_preferences where customer_identity_id=r.customer_identity_id;
 pref_found:=found;
 insert into public.mme_repair_customer_timeline(repair_case_id,customer_identity_id,event_code,customer_message)
 values(p_case,r.customer_identity_id,p_event_code,left(p_message,500)) returning timeline_event_id into v;
 ch:=case when pref_found and pref.preferred_channel='sms' and pref.sms_enabled then 'sms'
          when pref_found and pref.preferred_channel='email' and pref.email_enabled then 'email' else null end;
 if ch is not null then
  insert into public.mme_repair_notification_outbox(repair_case_id,customer_identity_id,timeline_event_id,channel,template_code,payload,idempotency_key)
  values(p_case,r.customer_identity_id,v,ch,'repair_status_update',jsonb_build_object('event_code',p_event_code,'timeline_event_id',v),p_idempotency_key)
  on conflict(idempotency_key) do nothing;
 end if;
 return v;
end; $$;

create or replace function public.mme_repair_create_appointment(
 p_case uuid,p_customer uuid,p_location uuid,p_type text,p_start timestamptz,p_end timestamptz,p_actor uuid,p_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_warranty_repair_cases%rowtype; v uuid;
begin
 if p_actor is null or length(trim(coalesce(p_key,'')))<12 or p_end<=p_start then raise exception 'Valid actor, key and appointment window required' using errcode='22023'; end if;
 select * into r from public.mme_warranty_repair_cases where repair_case_id=p_case for update;
 if not found or r.customer_identity_id<>p_customer then raise exception 'Repair case/customer mismatch' using errcode='42501'; end if;
 if r.status in ('completed','denied','cancelled') then raise exception 'Closed repair case cannot be scheduled' using errcode='55000'; end if;
 perform pg_advisory_xact_lock(hashtextextended(coalesce(p_location::text,'unassigned'),0));
 if exists(select 1 from public.mme_repair_appointments a where a.location_id is not distinct from p_location and a.status in ('requested','confirmed','rescheduled') and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(p_start,p_end,'[)')) then
  raise exception 'Appointment window conflicts with an existing booking' using errcode='23P01';
 end if;
 insert into public.mme_repair_appointments(repair_case_id,customer_identity_id,location_id,appointment_type,starts_at,ends_at,created_by,idempotency_key)
 values(p_case,p_customer,p_location,p_type,p_start,p_end,p_actor,p_key) returning appointment_id into v;
 return v;
end; $$;

revoke all on function public.mme_repair_enqueue_customer_update(uuid,text,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_repair_create_appointment(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_repair_enqueue_customer_update(uuid,text,text,uuid,text) to service_role;
grant execute on function public.mme_repair_create_appointment(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text) to service_role;
commit;
