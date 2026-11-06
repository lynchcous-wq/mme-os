begin;
create table public.mme_security_provider_circuit_state(
 source_system text primary key check(source_system in ('pos','inventory','warranty','crm','evidence','payments','returns')),
 circuit_state text not null default 'closed' check(circuit_state in ('closed','open','half_open','manual_open')),
 failure_count integer not null default 0 check(failure_count>=0),
 failure_threshold integer not null default 3 check(failure_threshold between 1 and 20),
 open_duration_seconds integer not null default 60 check(open_duration_seconds between 10 and 3600),
 opened_until timestamptz,
 last_failure_at timestamptz,
 last_success_at timestamptz,
 last_error_code text,
 active_provider text not null default 'primary' check(active_provider in ('primary','secondary')),
 manual_override boolean not null default false,
 updated_at timestamptz not null default now()
);
create table public.mme_security_provider_failover_events(
 event_id uuid primary key default gen_random_uuid(),
 source_system text not null check(source_system in ('pos','inventory','warranty','crm','evidence','payments','returns')),
 event_type text not null check(event_type in ('circuit_opened','failover_started','failover_succeeded','provider_recovered','manual_override','failover_failed')),
 from_provider text,
 to_provider text,
 reason_code text,
 request_id text,
 created_at timestamptz not null default now()
);
alter table public.mme_security_provider_circuit_state enable row level security;
alter table public.mme_security_provider_failover_events enable row level security;
revoke all on public.mme_security_provider_circuit_state from public,anon,authenticated;
revoke all on public.mme_security_provider_failover_events from public,anon,authenticated;
grant select,insert,update on public.mme_security_provider_circuit_state to service_role;
grant select,insert on public.mme_security_provider_failover_events to service_role;
insert into public.mme_security_provider_circuit_state(source_system) values('pos'),('inventory'),('warranty'),('crm'),('evidence'),('payments'),('returns') on conflict do nothing;
create or replace function public.mme_security_provider_admit(p_source text)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.mme_security_provider_circuit_state%rowtype;
begin
 select * into s from public.mme_security_provider_circuit_state where source_system=p_source for update;
 if not found then raise exception 'unknown_provider_source'; end if;
 if s.manual_override and s.circuit_state='manual_open' then return 'blocked'; end if;
 if s.circuit_state='open' and s.opened_until>now() then return 'secondary'; end if;
 if s.circuit_state='open' and s.opened_until<=now() then
  update public.mme_security_provider_circuit_state set circuit_state='half_open',updated_at=now() where source_system=p_source;
  return 'primary_probe';
 end if;
 if s.circuit_state='half_open' then return 'blocked'; end if;
 return 'primary';
end $$;
create or replace function public.mme_security_provider_record(p_source text,p_provider text,p_success boolean,p_error text default null,p_request text default null)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.mme_security_provider_circuit_state%rowtype; state text;
begin
 select * into s from public.mme_security_provider_circuit_state where source_system=p_source for update;
 if not found then raise exception 'unknown_provider_source'; end if;
 if p_success then
  update public.mme_security_provider_circuit_state set circuit_state='closed',failure_count=0,opened_until=null,last_success_at=now(),last_error_code=null,active_provider=p_provider,manual_override=false,updated_at=now() where source_system=p_source;
  if s.circuit_state in ('open','half_open') or s.active_provider<>p_provider then
   insert into public.mme_security_provider_failover_events(source_system,event_type,from_provider,to_provider,request_id) values(p_source,'provider_recovered',s.active_provider,p_provider,p_request);
  end if;
  return 'closed';
 end if;
 state:=case when p_provider='secondary' then 'open' when s.failure_count+1>=s.failure_threshold then 'open' else 'closed' end;
 update public.mme_security_provider_circuit_state set failure_count=failure_count+1,circuit_state=state,opened_until=case when state='open' then now()+make_interval(secs=>open_duration_seconds) else opened_until end,last_failure_at=now(),last_error_code=left(coalesce(p_error,'provider_failure'),100),updated_at=now() where source_system=p_source;
 if state='open' and s.circuit_state<>'open' then
  insert into public.mme_security_provider_failover_events(source_system,event_type,from_provider,to_provider,reason_code,request_id) values(p_source,'circuit_opened',p_provider,case when p_provider='primary' then 'secondary' else 'none' end,p_error,p_request);
 end if;
 return state;
end $$;
create or replace function public.mme_security_provider_override(p_source text,p_action text,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if length(trim(coalesce(p_reason,'')))<10 then raise exception 'override_reason_required'; end if;
 if p_action='open' then
  update public.mme_security_provider_circuit_state set circuit_state='manual_open',manual_override=true,opened_until=null,updated_at=now() where source_system=p_source;
 elsif p_action='close' then
  update public.mme_security_provider_circuit_state set circuit_state='half_open',manual_override=false,failure_count=0,opened_until=now(),updated_at=now() where source_system=p_source;
 else raise exception 'invalid_override_action'; end if;
 insert into public.mme_security_provider_failover_events(source_system,event_type,reason_code) values(p_source,'manual_override',p_action||':'||left(p_reason,400));
end $$;
revoke all on function public.mme_security_provider_admit(text) from public,anon,authenticated;
revoke all on function public.mme_security_provider_record(text,text,boolean,text,text) from public,anon,authenticated;
revoke all on function public.mme_security_provider_override(text,text,text) from public,anon,authenticated;
grant execute on function public.mme_security_provider_admit(text) to service_role;
grant execute on function public.mme_security_provider_record(text,text,boolean,text,text) to service_role;
grant execute on function public.mme_security_provider_override(text,text,text) to service_role;
commit;