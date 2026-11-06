begin;
create table if not exists public.mme_financial_integration_events(
 event_id uuid primary key default gen_random_uuid(),
 source_module text not null check(source_module in ('pos','stripe','inventory','payroll','accounts_payable','accounts_receivable')),
 source_event_id text not null,
 event_type text not null,
 effective_date date not null,
 currency char(3) not null default 'USD',
 payload jsonb not null default '{}',
 journal_lines jsonb not null,
 processing_status text not null default 'queued' check(processing_status in ('queued','processing','posted','failed','ignored')),
 journal_entry_id uuid references public.mme_gl_journal_entries(entry_id),
 attempts integer not null default 0 check(attempts>=0),
 last_error text,
 received_by_auth_user_id uuid not null,
 received_at timestamptz not null default now(),
 processed_at timestamptz,
 unique(source_module,source_event_id)
);
create index if not exists mme_financial_events_queue_idx on public.mme_financial_integration_events(processing_status,received_at) where processing_status in ('queued','failed');
create index if not exists mme_financial_events_source_idx on public.mme_financial_integration_events(source_module,event_type,effective_date);
create table if not exists public.mme_financial_integration_audit(
 audit_id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.mme_financial_integration_events(event_id),
 actor_auth_user_id uuid not null,
 action text not null,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create or replace function public.mme_financial_enqueue_event(p_source text,p_source_event_id text,p_event_type text,p_effective_date date,p_currency text,p_payload jsonb,p_lines jsonb,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_existing public.mme_financial_integration_events%rowtype; v_count int; v_debit numeric(16,2);v_credit numeric(16,2);v_line jsonb;v_code text;
begin
 if p_source not in ('pos','stripe','inventory','payroll','accounts_payable','accounts_receivable') or coalesce(trim(p_source_event_id),'')='' or coalesce(trim(p_event_type),'')='' or p_effective_date is null then raise exception 'invalid_financial_event_header';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 or jsonb_array_length(p_lines)>200 then raise exception 'invalid_financial_event_lines';end if;
 select count(*),coalesce(sum((x->>'debit')::numeric),0),coalesce(sum((x->>'credit')::numeric),0) into v_count,v_debit,v_credit from jsonb_array_elements(p_lines)x;
 if v_count<2 or v_debit<=0 or round(v_debit,2)<>round(v_credit,2) then raise exception 'financial_event_not_balanced';end if;
 for v_line in select * from jsonb_array_elements(p_lines) loop
  v_code:=v_line->>'account_code';
  if coalesce(v_code,'')='' or not exists(select 1 from public.mme_gl_accounts where account_code=v_code and active) then raise exception 'unknown_or_inactive_account_code';end if;
  if coalesce((v_line->>'debit')::numeric,0)<0 or coalesce((v_line->>'credit')::numeric,0)<0 or ((coalesce((v_line->>'debit')::numeric,0)>0)=(coalesce((v_line->>'credit')::numeric,0)>0)) then raise exception 'invalid_financial_event_line';end if;
 end loop;
 select * into v_existing from public.mme_financial_integration_events where source_module=p_source and source_event_id=p_source_event_id;
 if found then
  if v_existing.event_type<>p_event_type or v_existing.effective_date<>p_effective_date or v_existing.journal_lines<>p_lines then raise exception 'idempotency_conflict';end if;
  return v_existing.event_id;
 end if;
 insert into public.mme_financial_integration_events(source_module,source_event_id,event_type,effective_date,currency,payload,journal_lines,received_by_auth_user_id) values(p_source,p_source_event_id,p_event_type,p_effective_date,upper(coalesce(p_currency,'USD')),coalesce(p_payload,'{}'),p_lines,p_actor) returning event_id into v_id;
 insert into public.mme_financial_integration_audit(event_id,actor_auth_user_id,action,details) values(v_id,p_actor,'event_enqueued',jsonb_build_object('source',p_source,'source_event_id',p_source_event_id,'event_type',p_event_type));
 return v_id;
end $$;
create or replace function public.mme_financial_process_event(p_event_id uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v public.mme_financial_integration_events%rowtype;v_lines jsonb;v_line jsonb;v_entry uuid;v_number text;v_total_debit numeric(16,2);v_total_credit numeric(16,2);
begin
 select * into v from public.mme_financial_integration_events where event_id=p_event_id for update;
 if not found then raise exception 'financial_event_not_found';end if;
 if v.processing_status='posted' then return v.journal_entry_id;end if;
 if v.processing_status not in ('queued','failed') then raise exception 'financial_event_not_processable';end if;
 update public.mme_financial_integration_events set processing_status='processing',attempts=attempts+1,last_error=null where event_id=p_event_id;
 select coalesce(sum((x->>'debit')::numeric),0),coalesce(sum((x->>'credit')::numeric),0) into v_total_debit,v_total_credit from jsonb_array_elements(v.journal_lines)x;
 if v_total_debit<=0 or round(v_total_debit,2)<>round(v_total_credit,2) then raise exception 'financial_event_not_balanced';end if;
 select jsonb_agg(jsonb_build_object('account_id',a.account_id,'debit',coalesce((x->>'debit')::numeric,0),'credit',coalesce((x->>'credit')::numeric,0),'description',coalesce(x->>'description',v.event_type))) into v_lines
 from jsonb_array_elements(v.journal_lines)x join public.mme_gl_accounts a on a.account_code=x->>'account_code' and a.active;
 if jsonb_array_length(v_lines)<>jsonb_array_length(v.journal_lines) then raise exception 'account_mapping_missing';end if;
 v_number:='INT-'||upper(substr(replace(p_event_id::text,'-',''),1,20));
 v_entry:=public.mme_gl_post_journal(v_number,v.effective_date,'Integrated '||v.source_module||' event: '||v.event_type,v.source_module,v.source_event_id,p_actor,v_lines);
 update public.mme_financial_integration_events set processing_status='posted',journal_entry_id=v_entry,processed_at=now(),last_error=null where event_id=p_event_id;
 insert into public.mme_financial_integration_audit(event_id,actor_auth_user_id,action,details) values(p_event_id,p_actor,'event_posted',jsonb_build_object('journal_entry_id',v_entry));
 return v_entry;
exception when others then
 update public.mme_financial_integration_events set processing_status='failed',last_error=left(sqlerrm,500),processed_at=now() where event_id=p_event_id;
 insert into public.mme_financial_integration_audit(event_id,actor_auth_user_id,action,details) values(p_event_id,p_actor,'event_failed',jsonb_build_object('error',left(sqlerrm,500)));
 raise;
end $$;
create or replace function public.mme_financial_process_batch(p_limit integer,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare v record;v_posted int:=0;v_failed int:=0;v_id uuid;
begin
 for v in select event_id from public.mme_financial_integration_events where processing_status in ('queued','failed') order by received_at for update skip locked limit greatest(1,least(coalesce(p_limit,25),100)) loop
  begin v_id:=public.mme_financial_process_event(v.event_id,p_actor);v_posted:=v_posted+1;
  exception when others then v_failed:=v_failed+1;
  end;
 end loop;
 return jsonb_build_object('posted',v_posted,'failed',v_failed);
end $$;
alter table public.mme_financial_integration_events enable row level security;
alter table public.mme_financial_integration_audit enable row level security;
revoke all on public.mme_financial_integration_events,public.mme_financial_integration_audit from public,anon,authenticated;
grant all on public.mme_financial_integration_events,public.mme_financial_integration_audit to service_role;
revoke all on function public.mme_financial_enqueue_event(text,text,text,date,text,jsonb,jsonb,uuid) from public,anon,authenticated;
revoke all on function public.mme_financial_process_event(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_financial_process_batch(integer,uuid) from public,anon,authenticated;
grant execute on function public.mme_financial_enqueue_event(text,text,text,date,text,jsonb,jsonb,uuid) to service_role;
grant execute on function public.mme_financial_process_event(uuid,uuid) to service_role;
grant execute on function public.mme_financial_process_batch(integer,uuid) to service_role;
commit;