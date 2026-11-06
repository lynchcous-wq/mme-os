begin;
create or replace function public.mme_security_incident_escalate_overdue_cases()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 r record;
 changed integer:=0;
begin
 for r in
  select case_id,alert_id,severity,status,escalation_level,sla_due_at
  from public.mme_security_incident_response_cases
  where status not in ('closed','closure_pending')
    and sla_due_at<now()
    and escalation_level<5
    and (escalated_at is null or escalated_at<now()-interval '15 minutes')
  order by sla_due_at asc
  for update skip locked
 loop
  update public.mme_security_incident_response_cases
   set escalation_level=least(escalation_level+1,5),escalated_at=now(),
       status=case when status in ('triage','investigating') then 'containment' else status end,
       updated_at=now()
   where case_id=r.case_id;
  insert into public.mme_security_incident_response_events(
   case_id,actor_id,actor_role,event_type,rationale,event_data,request_id
  ) values(
   r.case_id,'00000000-0000-0000-0000-000000000000'::uuid,'system','escalated',
   'Automatic escalation because the response SLA deadline was exceeded.',
   jsonb_build_object('previousLevel',r.escalation_level,'newLevel',least(r.escalation_level+1,5),'slaDueAt',r.sla_due_at,'trigger','sla_overdue'),
   'sla-worker'
  );
  changed:=changed+1;
 end loop;
 return jsonb_build_object('escalatedCases',changed,'processedAt',now());
end $$;
revoke all on function public.mme_security_incident_escalate_overdue_cases() from public,anon,authenticated;
grant execute on function public.mme_security_incident_escalate_overdue_cases() to service_role;
commit;