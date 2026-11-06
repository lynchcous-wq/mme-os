-- Build 001: independent review and controlled posting of physical count variances.
-- Trusted server must authenticate actor/approver and enforce MME role/location permissions.

create or replace function public.mme_submit_cycle_count(
 p_session_id uuid,p_actor_identity_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if p_session_id is null or p_actor_identity_id is null then
  raise exception 'Invalid cycle count submission' using errcode='22023';
 end if;
 update public.mme_cycle_count_lines set counted_quantity=0,status='counted',
  updated_at=now()
 where session_id=p_session_id and status='counting';
 update public.mme_cycle_count_sessions set status='review',reviewed_by_identity_id=p_actor_identity_id,
  reviewed_at=now(),updated_at=now() where id=p_session_id and status='open';
 if not found then return false; end if;
 insert into public.mme_cycle_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,'count_submitted',jsonb_build_object('unscanned_lines_defaulted_to_zero',true),p_actor_identity_id);
 return true;
end; $$;

create or replace function public.mme_approve_cycle_count(
 p_session_id uuid,p_approver_identity_id uuid,p_note text default null
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_session public.mme_cycle_count_sessions%rowtype; v_lines integer; v_uncounted integer;
begin
 if p_session_id is null or p_approver_identity_id is null then
  raise exception 'Invalid cycle count approval' using errcode='22023';
 end if;
 select * into v_session from public.mme_cycle_count_sessions where id=p_session_id for update;
 if not found or v_session.status<>'review' then return false; end if;
 if p_approver_identity_id=v_session.opened_by_identity_id then
  raise exception 'Count opener cannot approve their own count' using errcode='23514';
 end if;
 select count(*),count(*) filter(where status not in ('counted','exception'))
 into v_lines,v_uncounted from public.mme_cycle_count_lines where session_id=p_session_id;
 if v_lines=0 or v_uncounted>0 then
  raise exception 'Count contains no lines or incomplete lines' using errcode='23514';
 end if;
 update public.mme_cycle_count_sessions set status='approved',approved_by_identity_id=p_approver_identity_id,
  approved_at=now(),notes=coalesce(left(p_note,1000),notes),updated_at=now()
 where id=p_session_id and status='review';
 insert into public.mme_cycle_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,'count_approved',jsonb_build_object('line_count',v_lines,'note',left(p_note,500)),p_approver_identity_id);
 return true;
end; $$;

create or replace function public.mme_post_cycle_count(
 p_session_id uuid,p_actor_identity_id uuid
) returns integer language plpgsql security definer set search_path=''
as $$
declare v_session public.mme_cycle_count_sessions%rowtype; v_line record;
 v_delta integer; v_posted integer:=0; v_missing integer:=0;
begin
 if p_session_id is null or p_actor_identity_id is null then
  raise exception 'Invalid cycle count posting' using errcode='22023';
 end if;
 select * into v_session from public.mme_cycle_count_sessions where id=p_session_id for update;
 if not found then raise exception 'Cycle count not found' using errcode='P0002'; end if;
 if v_session.status='posted' then return 0; end if;
 if v_session.status<>'approved' or v_session.approved_by_identity_id is null then
  raise exception 'Only independently approved counts can be posted' using errcode='23514';
 end if;
 for v_line in
  select * from public.mme_cycle_count_lines where session_id=p_session_id
  order by product_id,serialized_unit_id nulls first for update
 loop
  if v_line.serialized_unit_id is null then
   v_delta:=v_line.counted_quantity-v_line.expected_quantity;
   if v_delta<>0 then
    perform public.mme_adjust_inventory(v_line.product_id,v_session.location_id,v_delta,
     'Cycle count variance: '||v_session.count_reference,v_session.count_reference,
     p_actor_identity_id,v_session.approved_by_identity_id,null);
    v_posted:=v_posted+1;
   end if;
  elsif v_line.counted_quantity=0 and v_line.expected_quantity=1 then
   update public.mme_serialized_units set unit_status='quarantine',updated_at=now()
    where id=v_line.serialized_unit_id and location_id=v_session.location_id and unit_status='in_stock';
   if not found then
    if exists(select 1 from public.mme_serialized_units where id=v_line.serialized_unit_id and unit_status='reserved') then
     raise exception 'Cannot quarantine a missing unit with an active reservation' using errcode='23514';
    end if;
   else
    v_missing:=v_missing+1;v_posted:=v_posted+1;
   end if;
  end if;
  update public.mme_cycle_count_lines set status='posted',updated_at=now() where id=v_line.id;
 end loop;
 update public.mme_cycle_count_sessions set status='posted',posted_by_identity_id=p_actor_identity_id,
  posted_at=now(),updated_at=now() where id=p_session_id and status='approved';
 if not found then raise exception 'Count state changed during posting' using errcode='40001'; end if;
 insert into public.mme_cycle_count_events(session_id,event_type,event_data,actor_identity_id)
 values(p_session_id,'count_posted',jsonb_build_object('posted_variances',v_posted,
  'missing_serialized_units_quarantined',v_missing,'approved_by',v_session.approved_by_identity_id),p_actor_identity_id);
 return v_posted;
end; $$;

revoke all on function public.mme_approve_cycle_count(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_post_cycle_count(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_approve_cycle_count(uuid,uuid,text) to service_role;
grant execute on function public.mme_post_cycle_count(uuid,uuid) to service_role;

comment on function public.mme_approve_cycle_count(uuid,uuid,text) is
 'Independent reviewer approval for a submitted physical count; opener cannot self-approve.';
comment on function public.mme_post_cycle_count(uuid,uuid) is
 'Posts approved aggregate quantity variances and quarantines missing in-stock serialized devices atomically.';
