begin;
create table if not exists public.mme_warehouse_bins(
 bin_id uuid primary key default gen_random_uuid(),
 location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 bin_code text not null,
 zone_code text,
 shelf_code text,
 active boolean not null default true,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 unique(location_id,bin_code)
);
create table if not exists public.mme_warehouse_pick_waves(
 wave_id uuid primary key default gen_random_uuid(),
 wave_number text not null unique,
 source_type text not null check(source_type in('customer_order','transfer','return','manual')),
 source_reference text,
 wave_status text not null default 'draft' check(wave_status in('draft','released','picking','picked','packing','staged','shipped','cancelled')),
 priority text not null default 'normal' check(priority in('low','normal','high','urgent')),
 assigned_to_auth_user_id uuid,
 created_by_auth_user_id uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.mme_warehouse_pick_lines(
 pick_line_id uuid primary key default gen_random_uuid(),
 wave_id uuid not null references public.mme_warehouse_pick_waves(wave_id) on delete restrict,
 inventory_item_id uuid not null references public.mme_inventory_items(inventory_item_id) on delete restrict,
 source_location_id uuid not null references public.mme_inventory_locations(location_id) on delete restrict,
 bin_id uuid references public.mme_warehouse_bins(bin_id) on delete restrict,
 requested_quantity integer not null check(requested_quantity>0),
 picked_quantity integer not null default 0 check(picked_quantity>=0 and picked_quantity<=requested_quantity),
 line_status text not null default 'open' check(line_status in('open','picking','complete','short','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists mme_warehouse_pick_lines_wave_idx on public.mme_warehouse_pick_lines(wave_id,line_status);
create table if not exists public.mme_warehouse_pick_scans(
 scan_id uuid primary key default gen_random_uuid(),
 pick_line_id uuid not null references public.mme_warehouse_pick_lines(pick_line_id) on delete restrict,
 scanned_code text not null,
 quantity integer not null check(quantity>0),
 scanned_by_auth_user_id uuid not null,
 scanned_at timestamptz not null default now()
);
create index if not exists mme_warehouse_pick_scans_line_idx on public.mme_warehouse_pick_scans(pick_line_id,scanned_at desc);
create table if not exists public.mme_warehouse_pack_checks(
 pack_check_id uuid primary key default gen_random_uuid(),
 wave_id uuid not null references public.mme_warehouse_pick_waves(wave_id) on delete restrict,
 package_reference text not null,
 expected_unit_count integer not null check(expected_unit_count>0),
 verified_unit_count integer not null check(verified_unit_count>=0),
 verification_status text not null check(verification_status in('pending','verified','discrepancy')),
 verified_by_auth_user_id uuid not null,
 notes text,
 verified_at timestamptz not null default now(),
 check((verification_status='verified' and verified_unit_count=expected_unit_count) or verification_status<>'verified')
);
create table if not exists public.mme_warehouse_evidence(
 evidence_id uuid primary key default gen_random_uuid(),
 wave_id uuid not null references public.mme_warehouse_pick_waves(wave_id) on delete restrict,
 evidence_type text not null check(evidence_type in('pack_photo','condition_photo','label_reference','other')),
 storage_object_path text not null,
 content_type text,
 captured_by_auth_user_id uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.mme_warehouse_discrepancies(
 discrepancy_id uuid primary key default gen_random_uuid(),
 wave_id uuid not null references public.mme_warehouse_pick_waves(wave_id) on delete restrict,
 pick_line_id uuid references public.mme_warehouse_pick_lines(pick_line_id) on delete restrict,
 discrepancy_type text not null check(discrepancy_type in('short_pick','wrong_item','damaged','missing_serial','count_mismatch','other')),
 description text not null,
 discrepancy_status text not null default 'open' check(discrepancy_status in('open','investigating','resolved','waived')),
 created_by_auth_user_id uuid not null,
 resolved_by_auth_user_id uuid,
 resolution_note text,
 created_at timestamptz not null default now(),
 resolved_at timestamptz
);
create index if not exists mme_warehouse_discrepancies_status_idx on public.mme_warehouse_discrepancies(discrepancy_status,created_at desc);
create or replace function public.mme_warehouse_record_pick_scan(p_pick_line uuid,p_scanned_code text,p_quantity integer,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l public.mme_warehouse_pick_lines%rowtype; expected_sku text; result jsonb;
begin
 if p_quantity is null or p_quantity<=0 or length(trim(coalesce(p_scanned_code,'')))=0 then raise exception 'invalid_scan_payload'; end if;
 select * into l from public.mme_warehouse_pick_lines where pick_line_id=p_pick_line for update;
 if not found then raise exception 'pick_line_not_found'; end if;
 select sku into expected_sku from public.mme_inventory_items where inventory_item_id=l.inventory_item_id;
 if expected_sku is null or upper(trim(expected_sku))<>upper(trim(p_scanned_code)) then raise exception 'scanned_item_mismatch'; end if;
 if l.picked_quantity+p_quantity>l.requested_quantity then raise exception 'pick_quantity_exceeds_requested'; end if;
 update public.mme_warehouse_pick_lines set picked_quantity=picked_quantity+p_quantity,line_status=case when picked_quantity+p_quantity=requested_quantity then 'complete' else 'picking' end,updated_at=now() where pick_line_id=p_pick_line returning * into l;
 insert into public.mme_warehouse_pick_scans(pick_line_id,scanned_code,quantity,scanned_by_auth_user_id) values(p_pick_line,p_scanned_code,p_quantity,p_actor);
 update public.mme_warehouse_pick_waves set wave_status=case when not exists(select 1 from public.mme_warehouse_pick_lines where wave_id=l.wave_id and line_status<>'complete') then 'picked' else 'picking' end,updated_at=now() where wave_id=l.wave_id and wave_status in('released','picking','picked');
 return jsonb_build_object('pick_line_id',l.pick_line_id,'picked_quantity',l.picked_quantity,'requested_quantity',l.requested_quantity,'line_status',l.line_status);
end $$;
revoke all on function public.mme_warehouse_record_pick_scan(uuid,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.mme_warehouse_record_pick_scan(uuid,text,integer,uuid) to service_role;
do $$declare t text;begin foreach t in array array['mme_warehouse_bins','mme_warehouse_pick_waves','mme_warehouse_pick_lines','mme_warehouse_pick_scans','mme_warehouse_pack_checks','mme_warehouse_evidence','mme_warehouse_discrepancies'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
commit;