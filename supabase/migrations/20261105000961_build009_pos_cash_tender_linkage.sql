-- Build 009.14 follow-up: bind captured cash tenders and completed cash refunds to the assigned till.
begin;

create or replace function public.mme_pos_record_drawer_cash_sale(
  p_drawer_session_id uuid,p_tender_attempt_id uuid,p_actor_person_id uuid,p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_session public.mme_pos_cash_drawer_sessions%rowtype; v_attempt public.mme_pos_tender_attempts%rowtype;
  v_existing public.mme_pos_cash_drawer_movements%rowtype; v_id uuid;
begin
  if p_drawer_session_id is null or p_tender_attempt_id is null or p_actor_person_id is null
    or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 then
    raise exception 'Invalid cash sale drawer link' using errcode='22023';
  end if;
  select * into v_session from public.mme_pos_cash_drawer_sessions where id=p_drawer_session_id for update;
  if not found or v_session.status<>'open' then raise exception 'Open drawer session not found' using errcode='P0002'; end if;
  if v_session.assigned_person_id<>p_actor_person_id then raise exception 'Only assigned associate may record till sales' using errcode='42501'; end if;
  if not public.mme_pos_authorize_drawer_action(p_actor_person_id,'pos.drawer.cash_in',v_session.location_id) then
    raise exception 'Cash sale recording permission denied' using errcode='42501';
  end if;
  select * into v_attempt from public.mme_pos_tender_attempts where id=p_tender_attempt_id for update;
  if not found or v_attempt.method<>'cash' or v_attempt.status<>'captured'
    or v_attempt.captured_amount_minor<=0 or v_attempt.currency<>v_session.currency then
    raise exception 'A completed captured cash tender in the drawer currency is required' using errcode='23514';
  end if;
  select * into v_existing from public.mme_pos_cash_drawer_movements
   where source_tender_attempt_id=p_tender_attempt_id;
  if found then
    if v_existing.drawer_session_id<>p_drawer_session_id then raise exception 'Cash tender already assigned to another drawer' using errcode='23505'; end if;
    return v_existing.id;
  end if;
  insert into public.mme_pos_cash_drawer_movements(
    drawer_session_id,movement_type,amount_minor,currency,reason_code,actor_person_id,
    source_tender_attempt_id,idempotency_key
  ) values(p_drawer_session_id,'cash_sale',v_attempt.captured_amount_minor,v_attempt.currency,
    'captured_cash_tender',p_actor_person_id,p_tender_attempt_id,p_idempotency_key)
  returning id into v_id;
  update public.mme_pos_cash_drawer_sessions
    set expected_cash_minor=expected_cash_minor+v_attempt.captured_amount_minor,updated_at=now()
    where id=p_drawer_session_id;
  return v_id;
end;
$$;

create or replace function public.mme_pos_record_drawer_cash_refund(
  p_drawer_session_id uuid,p_refund_request_id uuid,p_actor_person_id uuid,p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_session public.mme_pos_cash_drawer_sessions%rowtype; v_request public.mme_pos_refund_requests%rowtype;
  v_attempt public.mme_pos_tender_attempts%rowtype; v_existing public.mme_pos_cash_drawer_movements%rowtype; v_id uuid;
begin
  if p_drawer_session_id is null or p_refund_request_id is null or p_actor_person_id is null
    or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 then
    raise exception 'Invalid cash refund drawer link' using errcode='22023';
  end if;
  select * into v_session from public.mme_pos_cash_drawer_sessions where id=p_drawer_session_id for update;
  if not found or v_session.status<>'open' then raise exception 'Open drawer session not found' using errcode='P0002'; end if;
  if v_session.assigned_person_id<>p_actor_person_id then raise exception 'Only assigned associate may record till refunds' using errcode='42501'; end if;
  if not public.mme_pos_authorize_drawer_action(p_actor_person_id,'pos.drawer.cash_out',v_session.location_id) then
    raise exception 'Cash refund recording permission denied' using errcode='42501';
  end if;
  select * into v_request from public.mme_pos_refund_requests where id=p_refund_request_id for update;
  if not found or v_request.request_type<>'refund' or v_request.status<>'completed' then
    raise exception 'A completed refund request is required' using errcode='23514';
  end if;
  select * into v_attempt from public.mme_pos_tender_attempts where id=v_request.tender_attempt_id;
  if not found or v_attempt.method<>'cash' or v_request.currency<>v_session.currency then
    raise exception 'Refund must relate to a cash tender in the drawer currency' using errcode='23514';
  end if;
  select * into v_existing from public.mme_pos_cash_drawer_movements where source_refund_request_id=p_refund_request_id;
  if found then
    if v_existing.drawer_session_id<>p_drawer_session_id then raise exception 'Cash refund already assigned to another drawer' using errcode='23505'; end if;
    return v_existing.id;
  end if;
  if v_request.amount_minor>v_session.expected_cash_minor then
    raise exception 'Cash refund exceeds expected drawer balance; manager review required' using errcode='23514';
  end if;
  insert into public.mme_pos_cash_drawer_movements(
    drawer_session_id,movement_type,amount_minor,currency,reason_code,actor_person_id,
    source_refund_request_id,idempotency_key
  ) values(p_drawer_session_id,'cash_refund',v_request.amount_minor,v_request.currency,
    'completed_cash_refund',p_actor_person_id,p_refund_request_id,p_idempotency_key)
  returning id into v_id;
  update public.mme_pos_cash_drawer_sessions
    set expected_cash_minor=expected_cash_minor-v_request.amount_minor,updated_at=now()
    where id=p_drawer_session_id;
  return v_id;
end;
$$;

revoke all on function public.mme_pos_record_drawer_cash_sale(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_record_drawer_cash_refund(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_pos_record_drawer_cash_sale(uuid,uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_record_drawer_cash_refund(uuid,uuid,uuid,text) to service_role;

comment on function public.mme_pos_record_drawer_cash_sale(uuid,uuid,uuid,text) is
  'Adds a captured cash tender exactly once to its assigned associate drawer; does not initiate payment.';
comment on function public.mme_pos_record_drawer_cash_refund(uuid,uuid,uuid,text) is
  'Subtracts a completed cash refund exactly once from its assigned associate drawer; does not initiate refund.';

commit;
