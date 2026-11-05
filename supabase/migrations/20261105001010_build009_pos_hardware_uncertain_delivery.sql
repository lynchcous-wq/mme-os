begin;
alter table public.mme_pos_drawer_hardware_commands
 add column if not exists delivery_uncertain boolean not null default false,
 add column if not exists reconciliation_required boolean not null default false,
 add column if not exists delivery_uncertain_at timestamptz,
 add column if not exists delivery_uncertain_reason text;

create or replace function public.mme_pos_mark_hardware_command_uncertain(
 p_command_id uuid,p_lease_token uuid,p_reason text
) returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_drawer_hardware_commands%rowtype;
begin
 if p_command_id is null or p_lease_token is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300 then
  raise exception 'Invalid uncertain command result' using errcode='22023';
 end if;
 select * into v from public.mme_pos_drawer_hardware_commands where id=p_command_id for update;
 if not found or v.status<>'requested' or v.dispatch_lease_token is distinct from p_lease_token then
  raise exception 'Command lease is not active' using errcode='55000';
 end if;
 if v.command_type<>'open_drawer' then raise exception 'Only drawer commands may be marked uncertain' using errcode='22023'; end if;
 update public.mme_pos_drawer_hardware_commands set status='timed_out',completed_at=now(),
  failure_code='DELIVERY_UNCERTAIN',failure_detail=left(btrim(p_reason),300),
  delivery_uncertain=true,reconciliation_required=true,delivery_uncertain_at=now(),
  delivery_uncertain_reason=left(btrim(p_reason),300),dispatch_lease_token=null,dispatch_lease_until=null
 where id=p_command_id;
 return 'reconciliation_required';
end;
$$;

create or replace function public.mme_pos_claim_hardware_commands(
 p_limit integer default 10,p_lease_seconds integer default 45
) returns table(command_id uuid,device_id uuid,provider text,device_reference text,
 command_type text,idempotency_key text,lease_token uuid,attempt_count integer)
language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_limit not between 1 and 50 or p_lease_seconds not between 10 and 300 then
  raise exception 'Invalid claim parameters' using errcode='22023';
 end if;
 update public.mme_pos_drawer_hardware_commands c set status='timed_out',
  completed_at=coalesce(c.completed_at,now()),failure_code='DELIVERY_UNCERTAIN',
  failure_detail='Drawer command lease expired; device-state reconciliation required.',
  delivery_uncertain=true,reconciliation_required=true,delivery_uncertain_at=coalesce(c.delivery_uncertain_at,now()),
  delivery_uncertain_reason='Drawer command lease expired; device-state reconciliation required.',
  dispatch_lease_token=null,dispatch_lease_until=null
 where c.status='requested' and c.command_type='open_drawer'
  and c.dispatch_lease_token is not null and c.dispatch_lease_until<now()
  and not c.delivery_uncertain;
 return query
 with candidates as (
  select c.id from public.mme_pos_drawer_hardware_commands c
  where c.status='requested' and c.next_attempt_at<=now()
   and (c.dispatch_lease_until is null or c.dispatch_lease_until<now())
   and c.dispatch_attempt_count<c.dispatch_max_attempts and not c.reconciliation_required
  order by c.requested_at for update skip locked limit p_limit
 ), claimed as (
  update public.mme_pos_drawer_hardware_commands c set dispatch_lease_token=gen_random_uuid(),
   dispatch_lease_until=now()+make_interval(secs=>p_lease_seconds),
   dispatch_attempt_count=c.dispatch_attempt_count+1,dispatched_at=now()
  from candidates x where c.id=x.id
  returning c.id,c.device_id,c.command_type,c.idempotency_key,c.dispatch_lease_token,c.dispatch_attempt_count
 )
 select x.id,x.device_id,d.provider,d.device_reference,x.command_type,x.idempotency_key,
  x.dispatch_lease_token,x.dispatch_attempt_count
 from claimed x join public.mme_pos_register_devices d on d.id=x.device_id;
end;
$$;
revoke all on function public.mme_pos_mark_hardware_command_uncertain(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_pos_mark_hardware_command_uncertain(uuid,uuid,text) to service_role;
revoke all on function public.mme_pos_claim_hardware_commands(integer,integer) from public,anon,authenticated;
grant execute on function public.mme_pos_claim_hardware_commands(integer,integer) to service_role;
commit;
