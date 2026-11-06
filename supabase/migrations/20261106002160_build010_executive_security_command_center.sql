begin;
create table if not exists public.mme_security_executive_action_audit (
 audit_id uuid primary key default gen_random_uuid(),
 actor_id uuid not null,
 actor_role text not null check(actor_role in ('ceo','cio','it_admin')),
 action text not null check(action in ('acknowledge_alert','resolve_alert')),
 target_alert_id uuid not null references public.mme_security_integration_alerts(alert_id) on delete restrict,
 rationale text not null check(length(trim(rationale)) between 10 and 2000),
 before_state jsonb not null,
 after_state jsonb not null,
 request_id text,
 created_at timestamptz not null default now()
);
create index if not exists mme_security_executive_action_audit_alert_idx on public.mme_security_executive_action_audit(target_alert_id,created_at desc);
create index if not exists mme_security_executive_action_audit_actor_idx on public.mme_security_executive_action_audit(actor_id,created_at desc);
alter table public.mme_security_executive_action_audit enable row level security;
revoke all on public.mme_security_executive_action_audit from public,anon,authenticated;
grant select,insert on public.mme_security_executive_action_audit to service_role;

create or replace function public.mme_security_executive_record_action(
 p_alert_id uuid,p_action text,p_actor_id uuid,p_actor_role text,p_rationale text,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 current_alert public.mme_security_integration_alerts%rowtype;
 updated_alert public.mme_security_integration_alerts%rowtype;
 audit_key uuid;
begin
 if p_actor_role not in ('ceo','cio','it_admin') then raise exception 'executive_action_forbidden'; end if;
 if p_action not in ('acknowledge_alert','resolve_alert') then raise exception 'invalid_executive_action'; end if;
 if p_actor_id is null or coalesce(length(trim(p_rationale)),0)<10 or length(p_rationale)>2000 then raise exception 'invalid_action_context'; end if;
 select * into current_alert from public.mme_security_integration_alerts where alert_id=p_alert_id for update;
 if not found then raise exception 'security_alert_not_found'; end if;
 if p_action='acknowledge_alert' then
  if current_alert.status<>'open' then raise exception 'alert_not_open'; end if;
  update public.mme_security_integration_alerts set status='acknowledged',acknowledged_at=now(),acknowledged_by=p_actor_id where alert_id=p_alert_id returning * into updated_alert;
 else
  if current_alert.status not in ('open','acknowledged') then raise exception 'alert_not_resolvable'; end if;
  update public.mme_security_integration_alerts set status='resolved',resolved_at=now() where alert_id=p_alert_id returning * into updated_alert;
 end if;
 insert into public.mme_security_executive_action_audit(actor_id,actor_role,action,target_alert_id,rationale,before_state,after_state,request_id)
 values(p_actor_id,p_actor_role,p_action,p_alert_id,trim(p_rationale),to_jsonb(current_alert),to_jsonb(updated_alert),p_request_id)
 returning audit_id into audit_key;
 return jsonb_build_object('auditId',audit_key,'alertId',updated_alert.alert_id,'status',updated_alert.status,'action',p_action);
end
$$;
revoke all on function public.mme_security_executive_record_action(uuid,text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_security_executive_record_action(uuid,text,uuid,text,text,text) to service_role;
commit;