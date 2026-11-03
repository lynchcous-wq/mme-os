-- Build 004: prevent direct invocation of the Auth identity trigger function.
-- The trigger was created by the trusted migration owner. PostgreSQL checks
-- EXECUTE privilege when a trigger is created; trigger execution itself is
-- performed by the trigger mechanism. Verify this behavior in the target
-- Supabase/PostgreSQL version before rollout.
revoke all on function public.mme_create_person_identity() from public;
revoke all on function public.mme_create_person_identity() from anon;
revoke all on function public.mme_create_person_identity() from authenticated;
