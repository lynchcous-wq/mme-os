-- Build 011.16 — CEO role foundation.
-- Idempotent role catalog seed only. Does not create users, employee records,
-- role assignments, or permission grants. Account activation requires a verified
-- Supabase Auth user and explicit administrative provisioning.
insert into public.mme_roles (role_key, display_name, department_key, version, active)
values ('ceo', 'Chief Executive Officer', 'executive', 1, true)
on conflict (role_key) do nothing;
