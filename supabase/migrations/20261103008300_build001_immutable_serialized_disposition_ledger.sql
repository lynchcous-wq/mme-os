-- Build 001: preserve serialized disposition history as append-only evidence.
create or replace function public.mme_prevent_serialized_disposition_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  raise exception 'Serialized unit disposition records are immutable' using errcode='55000';
end;
$$;

drop trigger if exists mme_serialized_unit_dispositions_immutable
  on public.mme_serialized_unit_dispositions;
create trigger mme_serialized_unit_dispositions_immutable
before update or delete on public.mme_serialized_unit_dispositions
for each row execute function public.mme_prevent_serialized_disposition_mutation();

revoke all on function public.mme_prevent_serialized_disposition_mutation() from public,anon,authenticated;
