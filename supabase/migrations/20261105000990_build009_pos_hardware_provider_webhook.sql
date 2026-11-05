-- Build 009.18: enforce a single active webhook adapter version per provider.
begin;
create unique index if not exists mme_pos_hardware_one_enabled_adapter_per_provider
  on public.mme_pos_hardware_provider_adapters(provider_code)
  where enabled=true;
comment on index public.mme_pos_hardware_one_enabled_adapter_per_provider
  is 'Prevents ambiguous provider webhook secret and event mapping selection.';
commit;
