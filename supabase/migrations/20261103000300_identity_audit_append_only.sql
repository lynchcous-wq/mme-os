-- Build 004 security hardening: identity audit events are append-only.
-- Apply only after the foundation migrations have been reviewed in a dedicated
-- development Supabase project. Runtime application roles must not own this table.

create or replace function public.mme_reject_identity_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'MME identity audit events are append-only'
    using errcode = '42501';
end;
$$;

drop trigger if exists mme_identity_audit_no_update_delete
  on public.mme_identity_audit_events;
create trigger mme_identity_audit_no_update_delete
  before update or delete on public.mme_identity_audit_events
  for each row execute function public.mme_reject_identity_audit_mutation();

drop trigger if exists mme_identity_audit_no_truncate
  on public.mme_identity_audit_events;
create trigger mme_identity_audit_no_truncate
  before truncate on public.mme_identity_audit_events
  for each statement execute function public.mme_reject_identity_audit_mutation();

-- Keep direct client roles from manipulating the audit identity sequence.
revoke all on sequence public.mme_identity_audit_events_id_seq
  from public, anon, authenticated;

comment on table public.mme_identity_audit_events is
  'Append-only MME identity audit trail. Mutations and truncation are rejected by database triggers.';
