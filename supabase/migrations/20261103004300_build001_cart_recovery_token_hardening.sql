-- Build 001: harden cart recovery token attempts and remove unnecessary pgcrypto dependency.
alter table public.mme_cart_sessions add column if not exists recovery_attempt_count integer not null default 0 check(recovery_attempt_count between 0 and 10), add column if not exists recovery_max_attempts integer not null default 5 check(recovery_max_attempts between 1 and 10);
create or replace function public.mme_issue_cart_recovery_token(p_cart_id uuid,p_token_sha256 text,p_expires_at timestamptz)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_cart public.mme_cart_sessions%rowtype;
begin
 if p_cart_id is null or p_token_sha256 is null or p_token_sha256 !~ '^[0-9a-fA-F]{64}$' or p_expires_at is null or p_expires_at<=now() or p_expires_at>now()+interval '72 hours' then raise exception 'Invalid cart recovery token request' using errcode='22023'; end if;
 select * into v_cart from public.mme_cart_sessions where id=p_cart_id for update;
 if not found or v_cart.cart_status<>'abandoned' or v_cart.customer_identity_id is null or not v_cart.marketing_consent then return false; end if;
 update public.mme_cart_sessions set recovery_token_sha256=lower(p_token_sha256),recovery_token_expires_at=p_expires_at,recovery_attempt_count=0,updated_at=now() where id=p_cart_id;
 insert into public.mme_cart_recovery_events(cart_id,event_type,idempotency_key) values(p_cart_id,'recovery_token_issued','recovery-token:'||p_cart_id::text||':'||lower(p_token_sha256)) on conflict(idempotency_key) do nothing;
 return true;
end; $$;
create or replace function public.mme_restore_abandoned_cart(p_cart_id uuid,p_token_sha256 text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_cart public.mme_cart_sessions%rowtype;
begin
 if p_cart_id is null or p_token_sha256 is null or p_token_sha256 !~ '^[0-9a-fA-F]{64}$' then return false; end if;
 select * into v_cart from public.mme_cart_sessions where id=p_cart_id for update;
 if not found or v_cart.cart_status<>'abandoned' or v_cart.recovery_token_sha256 is null or v_cart.recovery_token_expires_at<=now() or v_cart.recovery_attempt_count>=v_cart.recovery_max_attempts then return false; end if;
 update public.mme_cart_sessions set recovery_attempt_count=recovery_attempt_count+1,updated_at=now() where id=p_cart_id;
 if v_cart.recovery_token_sha256<>lower(p_token_sha256) then return false; end if;
 update public.mme_cart_sessions set cart_status='recovered',recovered_at=now(),recovery_token_sha256=null,recovery_token_expires_at=null,last_activity_at=now(),updated_at=now() where id=p_cart_id;
 insert into public.mme_cart_recovery_events(cart_id,event_type,idempotency_key) values(p_cart_id,'cart_restored','cart-restored:'||p_cart_id::text||':'||gen_random_uuid()::text);
 return true;
end; $$;
revoke all on function public.mme_issue_cart_recovery_token(uuid,text,timestamp with time zone) from public,anon,authenticated;
revoke all on function public.mme_restore_abandoned_cart(uuid,text) from public,anon,authenticated;
grant execute on function public.mme_issue_cart_recovery_token(uuid,text,timestamp with time zone) to service_role;
grant execute on function public.mme_restore_abandoned_cart(uuid,text) to service_role;
comment on column public.mme_cart_sessions.recovery_attempt_count is 'Failed and successful recovery token verification attempts for the current token; capped by recovery_max_attempts.';