-- Build 004: create an opaque MME identity for each Supabase Auth user.
-- This does not create customer or employee relationships.
create or replace function public.mme_create_person_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.mme_person_identities (auth_user_id)
  values (new.id)
  on conflict (auth_user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists mme_auth_user_identity_created on auth.users;
create trigger mme_auth_user_identity_created
  after insert on auth.users
  for each row execute function public.mme_create_person_identity();
