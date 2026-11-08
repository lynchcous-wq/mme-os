-- Build 004: whole-login security lock is independent of customer/employee lifecycle.
-- Protected server requests must check this state; session revocation is a separate
-- server-side orchestration concern and is not implemented by this schema change.

alter table public.mme_person_identities
  add column security_status text not null default 'active'
    check (security_status in ('active', 'locked')),
  add column security_locked_at timestamptz,
  add column security_lock_reason text,
  add column security_locked_by_identity_id uuid
    references public.mme_person_identities(id) on delete restrict;

alter table public.mme_person_identities
  add constraint mme_person_identity_security_lock_state_check
  check (
    (security_status = 'active'
      and security_locked_at is null
      and security_lock_reason is null
      and security_locked_by_identity_id is null)
    or
    (security_status = 'locked'
      and security_locked_at is not null
      and security_lock_reason is not null
      and length(btrim(security_lock_reason)) > 0)
  );

create index mme_person_identity_security_status_idx
  on public.mme_person_identities(security_status);

comment on column public.mme_person_identities.security_status is
  'Whole-login security state; independent of customer and employee relationship status. Protected server requests must deny access when locked.';
comment on column public.mme_person_identities.security_lock_reason is
  'Required reason for a whole-login security lock; write through an audited server-side workflow only.';
