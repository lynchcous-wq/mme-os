-- Build 001: require explicit confirmation for every physical count line; never infer zero from a missed scan.
alter table public.mme_cycle_count_lines add column count_confirmed boolean not null default false;
create or replace function public.mme_record_cycle_count_quantity(p_line_id uuid,p_counted_quantity integer,p_actor_identity_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_line public.mme_cycle_count_lines%rowtype; v_session public.mme_cycle_count_sessions%rowtype;
begin
 if p_line_id is null or p_counted_quantity is null or p_counted_quantity<0 or p_actor_identity_id is null or (p_note is not null and length(p_note)>500) then raise exception 'Invalid physical count quantity' using errcode='22023'; end if;
 select * into v_line from public.mme_cycle_count_lines where id=p_line_id for update;
 if not found then raise exception 'Count line not found' using errcode='P0002'; end if;
 select * into v_session from public.mme_cycle_count_sessions where id=v_line.session_id for update;
 if v_session.status<>'open' then raise exception 'Count session is not open' using errcode='23514'; end if;
 if v_line.serialized_unit_id is not null and p_counted_quantity not in (0,1) then raise exception 'Serialized count must be zero or one' using errcode='22023'; end if;
 update public.mme_cycle_count_lines set counted_quantity=p_counted_quantity,count_confirmed=true,status='counted',last_scanned_by_identity_id=p_actor_identity_id,last_scanned_at=now(),updated_at=now() where id=p_line_id;
 insert into public.mme_cycle_count_events(session_id,line_id,event_type,event_data,actor_identity_id) values(v_line.session_id,p_line_id,'line_adjusted',jsonb_build_object('counted_quantity',p_counted_quantity,'note',left(p_note,500),'explicit_confirmation',true),p_actor_identity_id);
 return true;
end; $$;
create or replace function public.mme_submit_cycle_count(p_session_id uuid,p_actor_identity_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_session_id is null or p_actor_identity_id is null then raise exception 'Invalid cycle count submission' using errcode='22023'; end if;
 update public.mme_cycle_count_lines set status=case when count_confirmed then 'counted' else 'exception' end,updated_at=now() where session_id=p_session_id and status='counting';
 update public.mme_cycle_count_sessions set status='review',reviewed_by_identity_id=p_actor_identity_id,reviewed_at=now(),updated_at=now() where id=p_session_id and status='open';
 if not found then return false; end if;
 insert into public.mme_cycle_count_events(session_id,event_type,event_data,actor_identity_id) values(p_session_id,'count_submitted',jsonb_build_object('unconfirmed_lines_flagged',true),p_actor_identity_id);
 return true;
end; $$;
create or replace function public.mme_approve_cycle_count(p_session_id uuid,p_approver_identity_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_session public.mme_cycle_count_sessions%rowtype; v_lines integer; v_unconfirmed integer;
begin
 if p_session_id is null or p_approver_identity_id is null then raise exception 'Invalid cycle count approval' using errcode='22023'; end if;
 select * into v_session from public.mme_cycle_count_sessions where id=p_session_id for update;
 if not found or v_session.status<>'review' then return false; end if;
 if p_approver_identity_id=v_session.opened_by_identity_id then raise exception 'Count opener cannot approve their own count' using errcode='23514'; end if;
 select count(*),count(*) filter(where not count_confirmed or status not in ('counted','exception')) into v_lines,v_unconfirmed from public.mme_cycle_count_lines where session_id=p_session_id;
 if v_lines=0 or v_unconfirmed>0 then raise exception 'Count contains unconfirmed or incomplete lines' using errcode='23514'; end if;
 update public.mme_cycle_count_sessions set status='approved',approved_by_identity_id=p_approver_identity_id,approved_at=now(),notes=coalesce(left(p_note,1000),notes),updated_at=now() where id=p_session_id and status='review';
 insert into public.mme_cycle_count_events(session_id,event_type,event_data,actor_identity_id) values(p_session_id,'count_approved',jsonb_build_object('line_count',v_lines,'note',left(p_note,500)),p_approver_identity_id);
 return true;
end; $$;
revoke all on function public.mme_record_cycle_count_quantity(uuid,integer,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_record_cycle_count_quantity(uuid,integer,uuid,text) to service_role;
comment on column public.mme_cycle_count_lines.count_confirmed is 'True only after a physical scan or explicit employee-confirmed quantity entry; an unscanned line is never assumed to be zero.';