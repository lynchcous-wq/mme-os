-- Build 009.10: leased tender dispatch and trusted outcome recording.
-- This migration provides durable worker primitives only. It does not call a
-- payment provider or authorize/capture funds by itself.
begin;

alter table public.mme_pos_tender_outbox
  add column lease_token uuid,
  add column lease_expires_at timestamptz,
  add column last_attempt_at timestamptz;

create index mme_pos_tender_outbox_claim_idx
  on public.mme_pos_tender_outbox(delivery_status, available_at, lease_expires_at, created_at);

create or replace function public.mme_pos_claim_tender_dispatch(
  p_limit integer default 10,
  p_lease_seconds integer default 90
)
returns table(
  outbox_id uuid,
  tender_attempt_id uuid,
  transaction_id uuid,
  method text,
  operation text,
  amount_minor bigint,
  currency text,
  provider text,
  provider_account_reference text,
  payment_method_reference text,
  idempotency_key text,
  lease_token uuid
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 50
     or p_lease_seconds is null or p_lease_seconds < 15 or p_lease_seconds > 600 then
    raise exception 'Invalid tender worker claim limits' using errcode = '22023';
  end if;

  update public.mme_pos_tender_outbox
     set delivery_status = 'dead_letter',
         last_error_code = coalesce(last_error_code, 'max_attempts_exceeded'),
         lease_token = null,
         lease_expires_at = null
   where attempts >= 8
     and ((delivery_status = 'pending') or (delivery_status = 'processing' and lease_expires_at < now()));

  return query
  with candidates as (
    select o.id
      from public.mme_pos_tender_outbox o
     where (
       (o.delivery_status = 'pending' and o.available_at <= now())
       or (o.delivery_status = 'processing' and o.lease_expires_at < now())
     )
       and o.attempts < 8
     order by o.available_at, o.created_at
     for update skip locked
     limit p_limit
  ),
  claimed as (
    update public.mme_pos_tender_outbox o
       set delivery_status = 'processing',
           attempts = o.attempts + 1,
           lease_token = gen_random_uuid(),
           lease_expires_at = now() + make_interval(secs => p_lease_seconds),
           last_attempt_at = now()
      from candidates c
     where o.id = c.id
    returning o.id, o.tender_attempt_id, o.lease_token
  )
  select c.id, a.id, a.transaction_id, a.method, a.operation, a.amount_minor,
         a.currency, a.provider, a.provider_account_reference,
         a.payment_method_reference, a.idempotency_key, c.lease_token
    from claimed c
    join public.mme_pos_tender_attempts a on a.id = c.tender_attempt_id;
end;
$$;

create or replace function public.mme_pos_finish_tender_dispatch(
  p_outbox_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_authorized_amount_minor bigint default 0,
  p_captured_amount_minor bigint default 0,
  p_provider_payment_reference text default null,
  p_provider_operation_reference text default null,
  p_failure_code text default null
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_outbox public.mme_pos_tender_outbox%rowtype;
  v_attempt public.mme_pos_tender_attempts%rowtype;
  v_status text;
  v_reconciliation text;
begin
  if p_outbox_id is null or p_lease_token is null
     or p_outcome is null or p_outcome not in ('authorized','captured','declined','unknown_reconciliation')
     or p_authorized_amount_minor is null or p_authorized_amount_minor < 0
     or p_captured_amount_minor is null or p_captured_amount_minor < 0 then
    raise exception 'Invalid tender dispatch outcome' using errcode = '22023';
  end if;

  select * into v_outbox from public.mme_pos_tender_outbox
   where id = p_outbox_id for update;
  if not found or v_outbox.delivery_status <> 'processing'
     or v_outbox.lease_token is distinct from p_lease_token
     or v_outbox.lease_expires_at is null or v_outbox.lease_expires_at < now() then
    raise exception 'Tender dispatch lease is no longer valid' using errcode = '40001';
  end if;

  select * into v_attempt from public.mme_pos_tender_attempts
   where id = v_outbox.tender_attempt_id for update;

  if (v_attempt.operation = 'authorize' and p_outcome = 'captured')
     or (v_attempt.operation = 'sale' and p_outcome = 'authorized')
     or p_authorized_amount_minor > v_attempt.amount_minor
     or p_captured_amount_minor > v_attempt.amount_minor
     or (v_attempt.operation <> 'sale' and p_captured_amount_minor > p_authorized_amount_minor)
     or (p_outcome = 'captured' and p_captured_amount_minor <= 0)
     or (p_outcome = 'authorized' and p_authorized_amount_minor <= 0)
     or (p_outcome in ('declined','unknown_reconciliation')
         and (p_authorized_amount_minor <> 0 or p_captured_amount_minor <> 0)) then
    raise exception 'Tender provider amounts do not match the requested attempt' using errcode = '22023';
  end if;

  if p_provider_operation_reference is not null and exists (
    select 1 from public.mme_pos_tender_attempts x
     where x.provider = v_attempt.provider
       and x.provider_account_reference = v_attempt.provider_account_reference
       and x.provider_operation_reference = p_provider_operation_reference
       and x.id <> v_attempt.id
  ) then
    raise exception 'Provider operation reference is already assigned' using errcode = '23505';
  end if;

  v_status := case p_outcome
    when 'authorized' then 'authorized'
    when 'captured' then 'captured'
    when 'declined' then 'declined'
    else 'unknown_reconciliation'
  end;
  v_reconciliation := case when p_outcome = 'unknown_reconciliation' then 'manual_review' else 'pending' end;

  update public.mme_pos_tender_attempts
     set status = v_status,
         authorized_amount_minor = p_authorized_amount_minor,
         captured_amount_minor = p_captured_amount_minor,
         provider_payment_reference = p_provider_payment_reference,
         provider_operation_reference = p_provider_operation_reference,
         reconciliation_status = v_reconciliation,
         outcome_unknown = (p_outcome = 'unknown_reconciliation'),
         failure_code = case when p_outcome = 'declined' then left(p_failure_code, 80) else null end,
         updated_at = now()
   where id = v_attempt.id;

  update public.mme_pos_tender_outbox
     set delivery_status = 'delivered',
         delivered_at = now(),
         lease_token = null,
         lease_expires_at = null,
         last_error_code = null
   where id = v_outbox.id;

  return true;
end;
$$;

create or replace function public.mme_pos_retry_tender_dispatch(
  p_outbox_id uuid,
  p_lease_token uuid,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_outbox public.mme_pos_tender_outbox%rowtype;
begin
  select * into v_outbox from public.mme_pos_tender_outbox
   where id = p_outbox_id for update;
  if not found or v_outbox.delivery_status <> 'processing'
     or v_outbox.lease_token is distinct from p_lease_token
     or v_outbox.lease_expires_at is null or v_outbox.lease_expires_at < now() then
    raise exception 'Tender dispatch lease is no longer valid' using errcode = '40001';
  end if;

  update public.mme_pos_tender_outbox
     set delivery_status = case when attempts >= 8 then 'dead_letter' else 'pending' end,
         available_at = case when attempts >= 8 then available_at
           else now() + make_interval(secs => least(3600, 15 * (2 ^ least(attempts, 7))::integer)) end,
         last_error_code = left(coalesce(p_error_code, 'provider_error'), 80),
         lease_token = null,
         lease_expires_at = null
   where id = p_outbox_id;
  return true;
end;
$$;

update public.mme_pos_tender_outbox
   set delivery_status = 'dead_letter',
       last_error_code = coalesce(last_error_code, 'max_attempts_exceeded'),
       lease_token = null,
       lease_expires_at = null
 where attempts >= 8 and delivery_status in ('pending','processing');

revoke all on function public.mme_pos_claim_tender_dispatch(integer,integer) from public, anon, authenticated;
revoke all on function public.mme_pos_finish_tender_dispatch(uuid,uuid,text,bigint,bigint,text,text,text) from public, anon, authenticated;
revoke all on function public.mme_pos_retry_tender_dispatch(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.mme_pos_claim_tender_dispatch(integer,integer) to service_role;
grant execute on function public.mme_pos_finish_tender_dispatch(uuid,uuid,text,bigint,bigint,text,text,text) to service_role;
grant execute on function public.mme_pos_retry_tender_dispatch(uuid,uuid,text) to service_role;

comment on function public.mme_pos_claim_tender_dispatch(integer,integer) is
  'Claims a tender outbox item using a short lease and SKIP LOCKED. Provider dispatch must use the stable idempotency key.';
comment on function public.mme_pos_finish_tender_dispatch(uuid,uuid,text,bigint,bigint,text,text,text) is
  'Records a trusted provider outcome after lease verification. Unknown outcomes are routed to manual reconciliation.';
comment on function public.mme_pos_retry_tender_dispatch(uuid,uuid,text) is
  'Schedules bounded exponential retry or dead-letters after eight attempts.';

commit;
