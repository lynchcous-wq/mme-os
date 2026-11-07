-- Build 010.88 — customer security event ledger; append-only and owner-readable.
begin;
create table if not exists public.mme_customer_security_events (
 event_id bigint generated always as identity primary key,
 auth_user_id uuid not null,
 event_type text not null check(event_type in ('sign_in_success','sessions_revoked','password_recovery_completed')),
 event_source text not null default 'customer_portal' check(event_source in ('customer_portal','supabase_auth')),
 event_details jsonb not null default '{}'::jsonb check(jsonb_typeof(event_details)='object'),
 created_at timestamptz not null default now()
);
create index if not exists mme_customer_security_events_owner_created_idx
 on public.mme_customer_security_events(auth_user_id,created_at desc);
alter table public.mme_customer_security_events enable row level security;
revoke all on public.mme_customer_security_events from public,anon,authenticated;
grant select on public.mme_customer_security_events to authenticated;
create policy mme_customer_security_events_owner_read on public.mme_customer_security_events
 for select to authenticated using(auth_user_id=auth.uid());
create or replace function public.mme_customer_security_events_append_only()
returns trigger language plpgsql set search_path=pg_catalog,public
as $$ begin raise exception 'Customer security event history is append-only' using errcode='55000'; end $$;
drop trigger if exists mme_customer_security_events_no_update on public.mme_customer_security_events;
create trigger mme_customer_security_events_no_update before update or delete on public.mme_customer_security_events
 for each row execute function public.mme_customer_security_events_append_only();
comment on table public.mme_customer_security_events is 'Append-only customer security history; browser can read only own events; event writes are server-side only.';
commit;
