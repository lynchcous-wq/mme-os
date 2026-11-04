-- Build 001: saved carts and abandoned-checkout recovery metadata.
-- Carts never reserve stock; checkout always revalidates live prices and availability.
create table public.mme_cart_sessions (
 id uuid primary key default gen_random_uuid(),
 customer_identity_id uuid,
 guest_session_sha256 text,
 cart_status text not null default 'active' check(cart_status in ('active','abandoned','recovered','converted','expired')),
 currency text not null default 'USD' check(currency='USD'),
 marketing_consent boolean not null default false,
 consent_captured_at timestamptz,
 consent_source text,
 last_activity_at timestamptz not null default now(),
 abandoned_at timestamptz,
 recovered_at timestamptz,
 converted_order_id uuid references public.mme_orders(id) on delete restrict,
 recovery_token_sha256 text,
 recovery_token_expires_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(customer_identity_id is not null or guest_session_sha256 is not null),
 check(guest_session_sha256 is null or guest_session_sha256 ~ '^[0-9a-fA-F]{64}$'),
 check(recovery_token_sha256 is null or recovery_token_sha256 ~ '^[0-9a-fA-F]{64}$'),
 check((marketing_consent=false) or consent_captured_at is not null)
);
create index mme_cart_sessions_abandonment_idx on public.mme_cart_sessions(cart_status,last_activity_at);
create index mme_cart_sessions_customer_idx on public.mme_cart_sessions(customer_identity_id,last_activity_at desc);
create table public.mme_cart_items (
 id uuid primary key default gen_random_uuid(),
 cart_id uuid not null references public.mme_cart_sessions(id) on delete cascade,
 product_id uuid not null references public.mme_products(id) on delete restrict,
 location_id uuid not null references public.mme_store_locations(id) on delete restrict,
 quantity integer not null check(quantity between 1 and 20),
 added_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(cart_id,product_id,location_id)
);
create index mme_cart_items_product_idx on public.mme_cart_items(product_id,location_id);
create table public.mme_cart_recovery_events (
 id uuid primary key default gen_random_uuid(),
 cart_id uuid not null references public.mme_cart_sessions(id) on delete restrict,
 event_type text not null check(event_type in ('cart_saved','checkout_started','cart_abandoned','recovery_token_issued','recovery_opened','cart_restored','checkout_converted','recovery_expired')),
 idempotency_key text not null unique,
 attribution jsonb not null default '{}'::jsonb check(jsonb_typeof(attribution)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_cart_recovery_events_cart_idx on public.mme_cart_recovery_events(cart_id,occurred_at desc);
alter table public.mme_cart_sessions enable row level security;
alter table public.mme_cart_items enable row level security;
alter table public.mme_cart_recovery_events enable row level security;
revoke all on public.mme_cart_sessions,public.mme_cart_items,public.mme_cart_recovery_events from public,anon,authenticated;
grant all on public.mme_cart_sessions,public.mme_cart_items,public.mme_cart_recovery_events to service_role;

create or replace function public.mme_mark_abandoned_carts(p_idle_minutes integer default 60,p_limit integer default 250)
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 if p_idle_minutes is null or p_idle_minutes not between 15 and 10080 or p_limit is null or p_limit not between 1 and 1000 then
  raise exception 'Invalid abandoned cart worker limits' using errcode='22023'; end if;
 with candidates as (
  select id from public.mme_cart_sessions
  where cart_status='active' and last_activity_at<=now()-make_interval(mins=>p_idle_minutes)
  order by last_activity_at for update skip locked limit p_limit
 ), changed as (
  update public.mme_cart_sessions c set cart_status='abandoned',abandoned_at=now(),updated_at=now()
  from candidates x where c.id=x.id returning c.id
 ), events as (
  insert into public.mme_cart_recovery_events(cart_id,event_type,idempotency_key)
  select id,'cart_abandoned','cart-abandoned:'||id::text from changed
  on conflict(idempotency_key) do nothing returning id
 ) select count(*) into v_count from changed;
 return v_count;
end; $$;

create or replace function public.mme_issue_cart_recovery_token(p_cart_id uuid,p_token_sha256 text,p_expires_at timestamptz)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_cart public.mme_cart_sessions%rowtype;
begin
 if p_cart_id is null or p_token_sha256 is null or p_token_sha256 !~ '^[0-9a-fA-F]{64}$'
  or p_expires_at is null or p_expires_at<=now() or p_expires_at>now()+interval '72 hours' then
  raise exception 'Invalid cart recovery token request' using errcode='22023'; end if;
 select * into v_cart from public.mme_cart_sessions where id=p_cart_id for update;
 if not found or v_cart.cart_status<>'abandoned' or v_cart.customer_identity_id is null or not v_cart.marketing_consent then
  return false; end if;
 update public.mme_cart_sessions set recovery_token_sha256=lower(p_token_sha256),recovery_token_expires_at=p_expires_at,updated_at=now() where id=p_cart_id;
 insert into public.mme_cart_recovery_events(cart_id,event_type,idempotency_key)
 values(p_cart_id,'recovery_token_issued','recovery-token:'||p_cart_id::text||':'||encode(digest(p_token_sha256,'sha256'),'hex'))
 on conflict(idempotency_key) do nothing;
 return true;
end; $$;

create or replace function public.mme_restore_abandoned_cart(p_cart_id uuid,p_token_sha256 text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_cart public.mme_cart_sessions%rowtype;
begin
 if p_cart_id is null or p_token_sha256 is null or p_token_sha256 !~ '^[0-9a-fA-F]{64}$' then return false; end if;
 select * into v_cart from public.mme_cart_sessions where id=p_cart_id for update;
 if not found or v_cart.cart_status<>'abandoned' or v_cart.recovery_token_sha256 is null
  or v_cart.recovery_token_expires_at<=now() or v_cart.recovery_token_sha256<>lower(p_token_sha256) then return false; end if;
 update public.mme_cart_sessions set cart_status='recovered',recovered_at=now(),recovery_token_sha256=null,recovery_token_expires_at=null,last_activity_at=now(),updated_at=now() where id=p_cart_id;
 insert into public.mme_cart_recovery_events(cart_id,event_type,idempotency_key)
 values(p_cart_id,'cart_restored','cart-restored:'||p_cart_id::text||':'||gen_random_uuid()::text);
 return true;
end; $$;

revoke all on function public.mme_mark_abandoned_carts(integer,integer) from public,anon,authenticated;
revoke all on function public.mme_issue_cart_recovery_token(uuid,text,timestamp with time zone) from public,anon,authenticated;
revoke all on function public.mme_restore_abandoned_cart(uuid,text) from public,anon,authenticated;
grant execute on function public.mme_mark_abandoned_carts(integer,integer) to service_role;
grant execute on function public.mme_issue_cart_recovery_token(uuid,text,timestamp with time zone) to service_role;
grant execute on function public.mme_restore_abandoned_cart(uuid,text) to service_role;
comment on table public.mme_cart_sessions is 'Saved carts and recovery metadata; cart contents never reserve or decrement inventory.';
comment on table public.mme_cart_recovery_events is 'Idempotent cart abandonment and recovery attribution event history.';
