-- Build 001: customer fulfillment notifications and secure, one-time pickup verification.
create table public.mme_customer_notification_outbox (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.mme_orders(id) on delete restrict,
 fulfillment_id uuid references public.mme_order_fulfillments(id) on delete restrict,
 channel text not null check(channel in ('email','sms')),
 recipient_snapshot text not null check(length(btrim(recipient_snapshot)) between 3 and 320),
 template_key text not null check(template_key in ('order_paid','order_picking','order_shipped','pickup_ready','pickup_reminder','order_delivered','order_picked_up','fulfillment_exception')),
 idempotency_key text not null unique,
 template_data jsonb not null default '{}'::jsonb check(jsonb_typeof(template_data)='object'),
 delivery_status text not null default 'queued' check(delivery_status in ('queued','sending','sent','failed','suppressed')),
 provider text, provider_message_id text, attempt_count integer not null default 0 check(attempt_count>=0),
 last_error_code text, scheduled_at timestamptz not null default now(), sent_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index mme_customer_notification_outbox_queue_idx on public.mme_customer_notification_outbox(delivery_status,scheduled_at) where delivery_status in ('queued','failed');
create table public.mme_pickup_verification_challenges (
 id uuid primary key default gen_random_uuid(),
 fulfillment_id uuid not null references public.mme_order_fulfillments(id) on delete restrict,
 token_sha256 text not null check(token_sha256 ~ '^[0-9a-fA-F]{64}$'),
 expires_at timestamptz not null,
 max_attempts integer not null default 5 check(max_attempts between 1 and 10),
 attempt_count integer not null default 0 check(attempt_count>=0),
 consumed_at timestamptz, revoked_at timestamptz,
 issued_by_identity_id uuid not null,
 created_at timestamptz not null default now(),
 check(consumed_at is null or revoked_at is null)
);
create index mme_pickup_challenges_active_idx on public.mme_pickup_verification_challenges(fulfillment_id,expires_at desc);
alter table public.mme_customer_notification_outbox enable row level security;
alter table public.mme_pickup_verification_challenges enable row level security;
revoke all on public.mme_customer_notification_outbox,public.mme_pickup_verification_challenges from public,anon,authenticated;
grant all on public.mme_customer_notification_outbox,public.mme_pickup_verification_challenges to service_role;

create or replace function public.mme_queue_fulfillment_notification(
 p_order_id uuid,p_fulfillment_id uuid,p_channel text,p_recipient text,
 p_template_key text,p_idempotency_key text,p_template_data jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if p_order_id is null or p_channel not in ('email','sms') or p_recipient is null
  or length(btrim(p_recipient)) not between 3 and 320
  or p_template_key not in ('order_paid','order_picking','order_shipped','pickup_ready','pickup_reminder','order_delivered','order_picked_up','fulfillment_exception')
  or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 8 and 180
  or p_template_data is null or jsonb_typeof(p_template_data)<>'object'
  or (p_fulfillment_id is not null and not exists(select 1 from public.mme_order_fulfillments where id=p_fulfillment_id and order_id=p_order_id))
 then raise exception 'Invalid fulfillment notification request' using errcode='22023'; end if;
 insert into public.mme_customer_notification_outbox(order_id,fulfillment_id,channel,recipient_snapshot,template_key,idempotency_key,template_data)
 values(p_order_id,p_fulfillment_id,p_channel,btrim(p_recipient),p_template_key,btrim(p_idempotency_key),p_template_data)
 on conflict(idempotency_key) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.mme_customer_notification_outbox where idempotency_key=btrim(p_idempotency_key); end if;
 return v_id;
end; $$;

create or replace function public.mme_issue_pickup_verification_challenge(
 p_fulfillment_id uuid,p_token_sha256 text,p_expires_at timestamptz,p_issued_by_identity_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_f public.mme_order_fulfillments%rowtype; v_id uuid;
begin
 if p_fulfillment_id is null or p_token_sha256 is null or p_token_sha256 !~ '^[0-9a-fA-F]{64}$'
  or p_expires_at is null or p_expires_at<=now() or p_expires_at>now()+interval '24 hours'
  or p_issued_by_identity_id is null then raise exception 'Invalid pickup challenge' using errcode='22023'; end if;
 select * into v_f from public.mme_order_fulfillments where id=p_fulfillment_id for update;
 if not found or v_f.fulfillment_method<>'pickup' or v_f.fulfillment_status<>'ready_for_pickup'
 then raise exception 'Pickup order is not ready for verification' using errcode='23514'; end if;
 update public.mme_pickup_verification_challenges set revoked_at=now()
 where fulfillment_id=p_fulfillment_id and consumed_at is null and revoked_at is null;
 insert into public.mme_pickup_verification_challenges(fulfillment_id,token_sha256,expires_at,issued_by_identity_id)
 values(p_fulfillment_id,lower(p_token_sha256),p_expires_at,p_issued_by_identity_id) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.mme_verify_pickup_challenge(
 p_fulfillment_id uuid,p_token_sha256 text
) returns boolean language plpgsql security definer set search_path='' as $$
declare v_f public.mme_order_fulfillments%rowtype; v_c public.mme_pickup_verification_challenges%rowtype;
begin
 if p_fulfillment_id is null or p_token_sha256 is null or p_token_sha256 !~ '^[0-9a-fA-F]{64}$' then return false; end if;
 select * into v_f from public.mme_order_fulfillments where id=p_fulfillment_id for update;
 if not found or v_f.fulfillment_method<>'pickup' or v_f.fulfillment_status<>'ready_for_pickup' then return false; end if;
 select * into v_c from public.mme_pickup_verification_challenges
 where fulfillment_id=p_fulfillment_id and consumed_at is null and revoked_at is null
 order by created_at desc limit 1 for update;
 if not found or v_c.expires_at<=now() or v_c.attempt_count>=v_c.max_attempts then return false; end if;
 update public.mme_pickup_verification_challenges set attempt_count=attempt_count+1 where id=v_c.id;
 if v_c.token_sha256<>lower(p_token_sha256) then return false; end if;
 update public.mme_pickup_verification_challenges set consumed_at=now() where id=v_c.id;
 insert into public.mme_fulfillment_events(fulfillment_id,provider,provider_event_id,event_type,event_status,notes,actor_identity_id)
 values(p_f.id,'pickup','pickup-verified:'||v_c.id::text,'pickup_code_verified','accepted','One-time pickup code verified; employee must complete pickup handoff separately.',null);
 return true;
end; $$;

revoke all on function public.mme_queue_fulfillment_notification(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_issue_pickup_verification_challenge(uuid,text,timestamp with time zone,uuid) from public,anon,authenticated;
revoke all on function public.mme_verify_pickup_challenge(uuid,text) from public,anon,authenticated;
grant execute on function public.mme_queue_fulfillment_notification(uuid,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function public.mme_issue_pickup_verification_challenge(uuid,text,timestamp with time zone,uuid) to service_role;
grant execute on function public.mme_verify_pickup_challenge(uuid,text) to service_role;
comment on table public.mme_customer_notification_outbox is 'Idempotent customer fulfillment notification queue; trusted workers perform provider delivery.';
comment on table public.mme_pickup_verification_challenges is 'Hashed, expiring, single-use pickup codes with attempt limits; successful verification does not complete collection.';
