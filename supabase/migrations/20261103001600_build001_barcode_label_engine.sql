-- Build 001: versioned 2x3-inch barcode label profiles and auditable print batches.
-- Barcode graphics are rendered by the trusted print service; this migration stores payloads/snapshots only.

create table public.mme_label_profiles (
 id uuid primary key default gen_random_uuid(),
 profile_key text not null unique,
 display_name text not null,
 label_width_inches numeric(4,2) not null default 2.00 check(label_width_inches between 1 and 4),
 label_height_inches numeric(4,2) not null default 3.00 check(label_height_inches between 1 and 6),
 barcode_symbology text not null default 'CODE128' check(barcode_symbology in ('CODE128','EAN13','UPC_A')),
 information_density text not null default 'automatic' check(information_density in ('automatic','compact','standard','expanded')),
 show_mme_logo boolean not null default true,
 show_qr_code boolean not null default false,
 show_product_title boolean not null default true,
 show_sku boolean not null default true,
 show_condition boolean not null default true,
 show_price boolean not null default true,
 show_serial_last4 boolean not null default true,
 show_location boolean not null default false,
 logo_asset_path text,
 active boolean not null default true,
 version integer not null default 1 check(version>0),
 created_by_identity_id uuid not null,
 updated_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(label_width_inches=2.00 and label_height_inches=3.00),
 check(logo_asset_path is null or (logo_asset_path like 'mme-branding/%' and logo_asset_path not like '%..%'))
);

create table public.mme_label_profile_versions (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references public.mme_label_profiles(id) on delete restrict,
 version integer not null check(version>0),
 configuration jsonb not null check(jsonb_typeof(configuration)='object'),
 changed_by_identity_id uuid not null,
 changed_at timestamptz not null default now(),
 unique(profile_id,version)
);

create table public.mme_label_print_jobs (
 id uuid primary key default gen_random_uuid(),
 job_number text not null unique,
 profile_id uuid not null references public.mme_label_profiles(id) on delete restrict,
 profile_version integer not null,
 status text not null default 'queued' check(status in ('queued','rendering','printed','partially_printed','failed','cancelled')),
 printer_name text,
 printer_connection text check(printer_connection in ('usb','network','bluetooth','system')),
 label_count integer not null default 0 check(label_count between 0 and 2000),
 requested_by_identity_id uuid not null,
 requested_at timestamptz not null default now(),
 started_at timestamptz,
 completed_at timestamptz,
 failure_reason text,
 created_at timestamptz not null default now()
);

create table public.mme_label_print_job_items (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.mme_label_print_jobs(id) on delete restrict,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 sku_snapshot text not null,
 title_snapshot text not null,
 condition_snapshot text not null,
 price_cents_snapshot bigint not null check(price_cents_snapshot>=0),
 barcode_payload text not null,
 serial_last4 text,
 location_code_snapshot text,
 copy_count integer not null default 1 check(copy_count between 1 and 100),
 render_status text not null default 'pending' check(render_status in ('pending','rendered','printed','failed')),
 created_at timestamptz not null default now(),
 check(serial_last4 is null or serial_last4 ~ '^[A-Za-z0-9]{4}$')
);

create index mme_label_jobs_status_idx on public.mme_label_print_jobs(status,requested_at desc);
create index mme_label_job_items_job_idx on public.mme_label_print_job_items(job_id);
create index mme_label_job_items_barcode_idx on public.mme_label_print_job_items(barcode_payload);

alter table public.mme_label_profiles enable row level security;
alter table public.mme_label_profile_versions enable row level security;
alter table public.mme_label_print_jobs enable row level security;
alter table public.mme_label_print_job_items enable row level security;
revoke all on public.mme_label_profiles,public.mme_label_profile_versions,public.mme_label_print_jobs,public.mme_label_print_job_items from anon,authenticated;
grant all on public.mme_label_profiles,public.mme_label_profile_versions,public.mme_label_print_jobs,public.mme_label_print_job_items to service_role;

create or replace function public.mme_create_label_profile(
 p_profile_key text,p_display_name text,p_actor_identity_id uuid,p_logo_asset_path text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_config jsonb;
begin
 if p_profile_key is null or p_profile_key !~ '^[a-z0-9][a-z0-9_-]{1,39}$'
  or p_display_name is null or length(btrim(p_display_name)) not between 2 and 80
  or p_actor_identity_id is null
  or p_logo_asset_path is not null and (p_logo_asset_path not like 'mme-branding/%' or p_logo_asset_path like '%..%') then
  raise exception 'Invalid label profile' using errcode='22023';
 end if;
 insert into public.mme_label_profiles(profile_key,display_name,created_by_identity_id,updated_by_identity_id,logo_asset_path)
 values(p_profile_key,btrim(p_display_name),p_actor_identity_id,p_actor_identity_id,p_logo_asset_path)
 returning id into v_id;
 select jsonb_build_object('width_inches',label_width_inches,'height_inches',label_height_inches,
  'barcode_symbology',barcode_symbology,'information_density',information_density,
  'show_mme_logo',show_mme_logo,'show_qr_code',show_qr_code,'show_product_title',show_product_title,
  'show_sku',show_sku,'show_condition',show_condition,'show_price',show_price,
  'show_serial_last4',show_serial_last4,'show_location',show_location,'logo_asset_path',logo_asset_path)
 into v_config from public.mme_label_profiles where id=v_id;
 insert into public.mme_label_profile_versions(profile_id,version,configuration,changed_by_identity_id)
 values(v_id,1,v_config,p_actor_identity_id);
 return v_id;
end; $$;

create or replace function public.mme_update_label_profile(
 p_profile_id uuid,p_display_name text,p_barcode_symbology text,p_information_density text,
 p_show_mme_logo boolean,p_show_qr_code boolean,p_show_product_title boolean,
 p_show_sku boolean,p_show_condition boolean,p_show_price boolean,
 p_show_serial_last4 boolean,p_show_location boolean,p_logo_asset_path text,
 p_actor_identity_id uuid
) returns integer language plpgsql security definer set search_path=''
as $$
declare v_version integer; v_config jsonb;
begin
 if p_profile_id is null or p_actor_identity_id is null or p_display_name is null
  or length(btrim(p_display_name)) not between 2 and 80
  or p_barcode_symbology not in ('CODE128','EAN13','UPC_A')
  or p_information_density not in ('automatic','compact','standard','expanded')
  or p_show_mme_logo is null or p_show_qr_code is null or p_show_product_title is null
  or p_show_sku is null or p_show_condition is null or p_show_price is null
  or p_show_serial_last4 is null or p_show_location is null
  or p_logo_asset_path is not null and (p_logo_asset_path not like 'mme-branding/%' or p_logo_asset_path like '%..%') then
  raise exception 'Invalid label profile update' using errcode='22023';
 end if;
 update public.mme_label_profiles set display_name=btrim(p_display_name),barcode_symbology=p_barcode_symbology,
  information_density=p_information_density,show_mme_logo=p_show_mme_logo,show_qr_code=p_show_qr_code,
  show_product_title=p_show_product_title,show_sku=p_show_sku,show_condition=p_show_condition,
  show_price=p_show_price,show_serial_last4=p_show_serial_last4,show_location=p_show_location,
  logo_asset_path=p_logo_asset_path,version=version+1,updated_by_identity_id=p_actor_identity_id,updated_at=now()
 where id=p_profile_id and active=true returning version into v_version;
 if not found then raise exception 'Active label profile not found' using errcode='P0002'; end if;
 select jsonb_build_object('width_inches',label_width_inches,'height_inches',label_height_inches,
  'barcode_symbology',barcode_symbology,'information_density',information_density,
  'show_mme_logo',show_mme_logo,'show_qr_code',show_qr_code,'show_product_title',show_product_title,
  'show_sku',show_sku,'show_condition',show_condition,'show_price',show_price,
  'show_serial_last4',show_serial_last4,'show_location',show_location,'logo_asset_path',logo_asset_path)
 into v_config from public.mme_label_profiles where id=p_profile_id;
 insert into public.mme_label_profile_versions(profile_id,version,configuration,changed_by_identity_id)
 values(p_profile_id,v_version,v_config,p_actor_identity_id);
 return v_version;
end; $$;

create or replace function public.mme_create_label_print_job(
 p_job_number text,p_profile_id uuid,p_actor_identity_id uuid,p_items jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_job uuid; v_profile record; v_item record; v_count integer:=0; v_total integer:=0;
begin
 if p_job_number is null or length(btrim(p_job_number)) not between 3 and 80
  or p_profile_id is null or p_actor_identity_id is null
  or p_items is null or jsonb_typeof(p_items)<>'array'
  or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>500 then
  raise exception 'Invalid label print request' using errcode='22023';
 end if;
 select * into v_profile from public.mme_label_profiles where id=p_profile_id and active=true for share;
 if not found then raise exception 'Active label profile not found' using errcode='P0002'; end if;
 if v_profile.barcode_symbology<>'CODE128' then
  raise exception 'This Build 001 renderer currently supports CODE128 only' using errcode='0A000';
 end if;
 if v_profile.show_qr_code then
  raise exception 'QR label output is disabled in the initial MME label renderer' using errcode='0A000';
 end if;
 insert into public.mme_label_print_jobs(job_number,profile_id,profile_version,requested_by_identity_id,label_count)
 values(upper(btrim(p_job_number)),p_profile_id,v_profile.version,p_actor_identity_id,0) returning id into v_job;
 for v_item in
  select x.product_id,x.copy_count,x.serial_last4,x.location_id
  from jsonb_to_recordset(p_items) x(product_id uuid,copy_count integer,serial_last4 text,location_id uuid)
  order by x.product_id,x.location_id
 loop
  if v_item.copy_count is null or v_item.copy_count<1 or v_item.copy_count>100
   or v_item.serial_last4 is not null and v_item.serial_last4 !~ '^[A-Za-z0-9]{4}$' then
   raise exception 'Invalid label quantity or serial suffix' using errcode='22023';
  end if;
  if v_profile.show_location and v_item.location_id is null then
   raise exception 'Location is required by the selected label profile' using errcode='22023';
  end if;
  insert into public.mme_label_print_job_items(job_id,product_id,sku_snapshot,title_snapshot,
   condition_snapshot,price_cents_snapshot,barcode_payload,serial_last4,location_code_snapshot,copy_count)
  select v_job,p.id,p.sku,p.title,p.condition_grade,p.unit_price_cents,
   'MME:'||p.sku,v_item.serial_last4,l.location_code,v_item.copy_count
  from public.mme_products p
  left join public.mme_store_locations l on l.id=v_item.location_id and l.active=true
  where p.id=v_item.product_id and p.active=true;
  if not found then raise exception 'Active product or selected location not found' using errcode='P0002'; end if;
  v_count:=v_count+1; v_total:=v_total+v_item.copy_count;
  if v_total>2000 then raise exception 'Print batch exceeds 2000 labels' using errcode='22023'; end if;
 end loop;
 if v_count<>(select count(*) from jsonb_to_recordset(p_items) x(product_id uuid,copy_count integer,serial_last4 text,location_id uuid)) then
  raise exception 'Invalid label item' using errcode='22023';
 end if;
 update public.mme_label_print_jobs set label_count=v_total where id=v_job;
 return v_job;
end; $$;

create or replace function public.mme_set_label_print_job_status(
 p_job_id uuid,p_status text,p_printer_name text,p_printer_connection text,p_failure_reason text,
 p_actor_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_old text;
begin
 if p_job_id is null or p_actor_identity_id is null or p_status not in ('rendering','printed','partially_printed','failed','cancelled')
  or p_printer_connection is not null and p_printer_connection not in ('usb','network','bluetooth','system') then
  raise exception 'Invalid print status update' using errcode='22023';
 end if;
 select status into v_old from public.mme_label_print_jobs where id=p_job_id for update;
 if not found or v_old not in ('queued','rendering') then return false; end if;
 if not ((v_old='queued' and p_status in ('rendering','failed','cancelled'))
  or (v_old='rendering' and p_status in ('printed','partially_printed','failed','cancelled'))) then return false; end if;
 update public.mme_label_print_jobs set status=p_status,printer_name=coalesce(p_printer_name,printer_name),
  printer_connection=coalesce(p_printer_connection,printer_connection),
  failure_reason=case when p_status='failed' then left(p_failure_reason,500) else null end,
  started_at=case when p_status='rendering' then coalesce(started_at,now()) else started_at end,
  completed_at=case when p_status in ('printed','partially_printed','failed','cancelled') then now() else completed_at end
 where id=p_job_id;
 return true;
end; $$;

revoke all on function public.mme_create_label_profile(text,text,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_update_label_profile(uuid,text,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_create_label_print_job(text,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.mme_set_label_print_job_status(uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mme_create_label_profile(text,text,uuid,text) to service_role;
grant execute on function public.mme_update_label_profile(uuid,text,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,uuid) to service_role;
grant execute on function public.mme_create_label_print_job(text,uuid,uuid,jsonb) to service_role;
grant execute on function public.mme_set_label_print_job_status(uuid,text,text,text,text,uuid) to service_role;

comment on table public.mme_label_profiles is 'Versioned 2x3-inch MME barcode label profiles; logo on, QR off, automatic density by default.';
comment on table public.mme_label_print_jobs is 'Auditable print batches; actual rendering and printer transport are handled by the trusted print service.';
