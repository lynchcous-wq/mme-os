-- Build 009.67 — explainable warranty risk signals and human investigation controls.
begin;
create table public.mme_warranty_risk_rules (
 rule_code text primary key,
 description text not null,
 signal_category text not null check(signal_category in ('duplicate_claim','repeat_repair','serial_anomaly','provider_anomaly','evidence_gap','employee_control_exception')),
 weight integer not null check(weight between 1 and 100),
 enabled boolean not null default true,
 effective_from timestamptz not null default now(),
 effective_to timestamptz,
 approved_by uuid not null,
 created_at timestamptz not null default now(),
 check(effective_to is null or effective_to>effective_from)
);
create table public.mme_warranty_risk_assessments (
 assessment_id uuid primary key default gen_random_uuid(),
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 assessed_at timestamptz not null default now(),
 score integer not null check(score between 0 and 100),
 band text not null check(band in ('low','review','elevated','high')),
 model_version text not null,
 status text not null default 'pending_review' check(status in ('pending_review','reviewed_no_issue','escalated','resolved','superseded')),
 generated_by uuid not null,
 reviewed_by uuid,
 reviewed_at timestamptz,
 rationale text not null,
 unique(repair_case_id,model_version,assessed_at),
 check(reviewed_by is null or reviewed_by<>generated_by)
);
create index mme_warranty_risk_assessments_queue_idx on public.mme_warranty_risk_assessments(status,band,assessed_at desc);
create index mme_warranty_risk_assessments_case_idx on public.mme_warranty_risk_assessments(repair_case_id,assessed_at desc);
create table public.mme_warranty_risk_signals (
 signal_id uuid primary key default gen_random_uuid(),
 assessment_id uuid not null references public.mme_warranty_risk_assessments(assessment_id) on delete restrict,
 rule_code text not null references public.mme_warranty_risk_rules(rule_code) on delete restrict,
 signal_category text not null,
 signal_weight integer not null check(signal_weight between 1 and 100),
 source_reference text not null,
 explanation text not null check(length(btrim(explanation)) between 5 and 1000),
 evidence_metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence_metadata)='object'),
 created_at timestamptz not null default now(),
 unique(assessment_id,rule_code,source_reference)
);
create index mme_warranty_risk_signals_assessment_idx on public.mme_warranty_risk_signals(assessment_id);
create table public.mme_warranty_risk_investigations (
 investigation_id uuid primary key default gen_random_uuid(),
 assessment_id uuid not null references public.mme_warranty_risk_assessments(assessment_id) on delete restrict,
 repair_case_id uuid not null references public.mme_warranty_repair_cases(repair_case_id) on delete restrict,
 status text not null default 'open' check(status in ('open','evidence_requested','under_review','substantiated','unsubstantiated','inconclusive','closed')),
 priority text not null default 'normal' check(priority in ('normal','high','urgent')),
 assigned_reviewer uuid,
 opened_by uuid not null,
 opened_at timestamptz not null default now(),
 closed_by uuid,
 closed_at timestamptz,
 resolution_code text check(resolution_code in ('valid_claim','duplicate_confirmed','policy_abuse_confirmed','process_error','insufficient_evidence','false_positive','other')),
 resolution_notes text,
 check((closed_at is null and closed_by is null) or (closed_at is not null and closed_by is not null))
);
create index mme_warranty_risk_investigation_queue_idx on public.mme_warranty_risk_investigations(status,priority,opened_at);
create table public.mme_warranty_risk_evidence (
 evidence_id uuid primary key default gen_random_uuid(),
 investigation_id uuid not null references public.mme_warranty_risk_investigations(investigation_id) on delete restrict,
 evidence_type text not null check(evidence_type in ('repair_record','provider_claim','inspection_photo','diagnostic_report','inventory_record','approval_record','other')),
 storage_reference text,
 source_reference text not null,
 description text not null,
 content_hash text,
 submitted_by uuid not null,
 submitted_at timestamptz not null default now(),
 verified_by uuid,
 verified_at timestamptz,
 verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected','unavailable')),
 check((verified_at is null and verified_by is null) or (verified_at is not null and verified_by is not null))
);
create index mme_warranty_risk_evidence_investigation_idx on public.mme_warranty_risk_evidence(investigation_id,submitted_at);
create table public.mme_warranty_risk_decisions (
 decision_id uuid primary key default gen_random_uuid(),
 investigation_id uuid not null references public.mme_warranty_risk_investigations(investigation_id) on delete restrict,
 decision text not null check(decision in ('no_action','request_more_evidence','escalate_to_compliance','refer_to_provider','confirm_duplicate','confirm_policy_abuse','process_correction')),
 decision_reason text not null check(length(btrim(decision_reason)) between 10 and 2000),
 decided_by uuid not null,
 second_approver uuid,
 decided_at timestamptz not null default now(),
 supersedes_decision_id uuid references public.mme_warranty_risk_decisions(decision_id) on delete restrict,
 check(second_approver is null or second_approver<>decided_by)
);
create index mme_warranty_risk_decisions_investigation_idx on public.mme_warranty_risk_decisions(investigation_id,decided_at desc);
create table public.mme_warranty_risk_audit_events (
 event_id bigint generated always as identity primary key,
 investigation_id uuid references public.mme_warranty_risk_investigations(investigation_id) on delete restrict,
 assessment_id uuid references public.mme_warranty_risk_assessments(assessment_id) on delete restrict,
 actor_id uuid not null,
 event_type text not null,
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
 created_at timestamptz not null default now(),
 check((investigation_id is not null)::int+(assessment_id is not null)::int=1)
);
alter table public.mme_warranty_risk_rules enable row level security;
alter table public.mme_warranty_risk_assessments enable row level security;
alter table public.mme_warranty_risk_signals enable row level security;
alter table public.mme_warranty_risk_investigations enable row level security;
alter table public.mme_warranty_risk_evidence enable row level security;
alter table public.mme_warranty_risk_decisions enable row level security;
alter table public.mme_warranty_risk_audit_events enable row level security;
revoke all on public.mme_warranty_risk_rules,public.mme_warranty_risk_assessments,public.mme_warranty_risk_signals,public.mme_warranty_risk_investigations,public.mme_warranty_risk_evidence,public.mme_warranty_risk_decisions,public.mme_warranty_risk_audit_events from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_risk_rules,public.mme_warranty_risk_assessments,public.mme_warranty_risk_signals,public.mme_warranty_risk_investigations,public.mme_warranty_risk_evidence,public.mme_warranty_risk_decisions to service_role;
grant select,insert on public.mme_warranty_risk_audit_events to service_role;
revoke update,delete,truncate on public.mme_warranty_risk_audit_events from public,anon,authenticated,service_role;

create or replace function public.mme_warranty_risk_assess(p_case uuid,p_actor uuid,p_model text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.mme_warranty_repair_cases%rowtype; v uuid; s integer:=0; n integer:=0; b text; rule public.mme_warranty_risk_rules%rowtype; source text;
begin
 if p_actor is null or length(trim(coalesce(p_model,'')))=0 then raise exception 'Actor and model version required' using errcode='22023'; end if;
 select * into r from public.mme_warranty_repair_cases where repair_case_id=p_case;
 if not found then raise exception 'Repair case not found' using errcode='P0002'; end if;
 insert into public.mme_warranty_risk_assessments(repair_case_id,score,band,model_version,generated_by,rationale)
 values(p_case,0,'low',p_model,p_actor,'Explainable rule-based screening; review signals are not findings of misconduct.')
 returning assessment_id into v;
 for rule in select * from public.mme_warranty_risk_rules where enabled and effective_from<=now() and (effective_to is null or effective_to>now()) order by rule_code loop
  source:=null;
  if rule.signal_category='repeat_repair' and (select count(*) from public.mme_warranty_repair_cases x where x.serialized_unit_id=r.serialized_unit_id and x.repair_case_id<>p_case and x.created_at>=now()-interval '180 days')>=2 then source:='serialized-unit-repeat-repair';
  elsif rule.signal_category='duplicate_claim' and exists(select 1 from public.mme_warranty_provider_claims c where c.repair_case_id=p_case and c.provider_claim_reference is not null and exists(select 1 from public.mme_warranty_provider_claims d where d.provider_claim_reference=c.provider_claim_reference and d.provider_claim_id<>c.provider_claim_id)) then source:='provider-claim-reference-collision';
  elsif rule.signal_category='evidence_gap' and not exists(select 1 from public.mme_warranty_repair_diagnostics d where d.repair_case_id=p_case) then source:='diagnostic-evidence-not-recorded';
  elsif rule.signal_category='employee_control_exception' and exists(select 1 from public.mme_warranty_repair_labor l where l.repair_case_id=p_case and l.approved_by is null) then source:='labor-entry-awaiting-independent-approval';
  end if;
  if source is not null then
   insert into public.mme_warranty_risk_signals(assessment_id,rule_code,signal_category,signal_weight,source_reference,explanation)
   values(v,rule.rule_code,rule.signal_category,rule.weight,source,rule.description);
   s:=least(100,s+rule.weight); n:=n+1;
  end if;
 end loop;
 b:=case when s>=75 then 'high' when s>=45 then 'elevated' when s>=20 then 'review' else 'low' end;
 update public.mme_warranty_risk_assessments set score=s,band=b,rationale='Rule-based signals: '||n||'. Score is triage guidance only; no automated denial, payment hold or adverse customer action.' where assessment_id=v;
 insert into public.mme_warranty_risk_audit_events(assessment_id,actor_id,event_type,event_data)
 values(v,p_actor,'risk_assessment_created',jsonb_build_object('score',s,'band',b,'signal_count',n,'model_version',p_model));
 return v;
end; $$;

create or replace function public.mme_warranty_risk_open_investigation(p_assessment uuid,p_actor uuid,p_priority text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare a public.mme_warranty_risk_assessments%rowtype; v uuid;
begin
 select * into a from public.mme_warranty_risk_assessments where assessment_id=p_assessment for update;
 if not found or p_actor is null or p_priority not in ('normal','high','urgent') then raise exception 'Assessment, actor and valid priority required' using errcode='22023'; end if;
 insert into public.mme_warranty_risk_investigations(assessment_id,repair_case_id,priority,opened_by)
 values(p_assessment,a.repair_case_id,p_priority,p_actor) returning investigation_id into v;
 update public.mme_warranty_risk_assessments set status='escalated' where assessment_id=p_assessment;
 insert into public.mme_warranty_risk_audit_events(investigation_id,actor_id,event_type,event_data)
 values(v,p_actor,'investigation_opened',jsonb_build_object('assessment_id',p_assessment,'priority',p_priority));
 return v;
end; $$;

create or replace function public.mme_warranty_risk_close_investigation(p_investigation uuid,p_actor uuid,p_resolution text,p_notes text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare i public.mme_warranty_risk_investigations%rowtype;
begin
 select * into i from public.mme_warranty_risk_investigations where investigation_id=p_investigation for update;
 if not found or p_actor is null or p_resolution not in ('valid_claim','duplicate_confirmed','policy_abuse_confirmed','process_error','insufficient_evidence','false_positive','other') then raise exception 'Investigation and valid resolution required' using errcode='22023'; end if;
 if i.status='closed' or length(btrim(coalesce(p_notes,'')))<10 then raise exception 'Open investigation and documented rationale required' using errcode='55000'; end if;
 update public.mme_warranty_risk_investigations set status=case when p_resolution in ('valid_claim','false_positive','process_error','insufficient_evidence') then 'unsubstantiated' else 'substantiated' end,closed_by=p_actor,closed_at=now(),resolution_code=p_resolution,resolution_notes=left(p_notes,2000) where investigation_id=p_investigation;
 insert into public.mme_warranty_risk_audit_events(investigation_id,actor_id,event_type,event_data)
 values(p_investigation,p_actor,'investigation_closed',jsonb_build_object('resolution',p_resolution,'notes',left(p_notes,500)));
end; $$;

revoke all on function public.mme_warranty_risk_assess(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_risk_open_investigation(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_risk_close_investigation(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_risk_assess(uuid,uuid,text) to service_role;
grant execute on function public.mme_warranty_risk_open_investigation(uuid,uuid,text) to service_role;
grant execute on function public.mme_warranty_risk_close_investigation(uuid,uuid,text,text) to service_role;
commit;