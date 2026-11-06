-- Build 009.68 — warranty provider registry, claim integration outbox and reconciliation.
begin;
create table public.mme_warranty_providers (
 provider_id uuid primary key default gen_random_uuid(),
 provider_code text not null unique,
 display_name text not null,
 provider_type text not null check(provider_type in ('manufacturer','administrator','insurer','service_network')),
 supported_regions text[] not null default '{}',
 supported_currencies text[] not null default '{}',
 status text not null default 'draft' check(status in ('draft','testing','active','suspended','retired')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.mme_warranty_provider_connections (
 connection_id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.mme_warranty_providers(provider_id) on delete restrict,
 environment text not null check(environment in ('sandbox','production')),
 endpoint_base_url text not null,
 secret_reference text not null,
 api_version text,
 enabled boolean not null default false,
 last_health_check_at timestamptz,
 last_health_status text check(last_health_status in ('healthy','degraded','unavailable','unknown')),
 created_by uuid not null,
 approved_by uuid,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 unique(provider_id,environment),
 check(approved_by is null or approved_by<>created_by),
 check(endpoint_base_url ~ '^https://')
);
create table public.mme_warranty_provider_programs (
 program_id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.mme_warranty_providers(provider_id) on delete restrict,
 program_code text not null,
 plan_code text not null,
 product_category text not null,
 region_code text not null,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 sla_response_minutes integer not null default 1440 check(sla_response_minutes>0),
 active_from date not null,
 active_to date,
 status text not null default 'draft' check(status in ('draft','active','paused','expired')),
 created_at timestamptz not null default now(),
 unique(provider_id,program_code),
 check(active_to is null or active_to>=active_from)
);
create table public.mme_warranty_provider_claim_submissions (
 submission_id uuid primary key default gen_random_uuid(),
 provider_claim_id uuid not null references public.mme_warranty_provider_claims(provider_claim_id) on delete restrict,
 provider_id uuid not null references public.mme_warranty_providers(provider_id) on delete restrict,
 connection_id uuid not null references public.mme_warranty_provider_connections(connection_id) on delete restrict,
 program_id uuid references public.mme_warranty_provider_programs(program_id) on delete restrict,
 operation text not null check(operation in ('eligibility_check','claim_submit','claim_status_poll','document_upload')),
 status text not null default 'queued' check(status in ('queued','processing','succeeded','retry','failed','dead_letter','cancelled')),
 request_reference text not null,
 idempotency_key text not null unique,
 request_payload jsonb not null default '{}'::jsonb check(jsonb_typeof(request_payload)='object'),
 response_payload jsonb not null default '{}'::jsonb check(jsonb_typeof(response_payload)='object'),
 attempts integer not null default 0 check(attempts>=0),
 available_at timestamptz not null default now(),
 provider_reference text,
 response_code text,
 last_error_code text,
 submitted_at timestamptz,
 responded_at timestamptz,
 created_by uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_warranty_provider_submission_queue_idx on public.mme_warranty_provider_claim_submissions(status,available_at) where status in ('queued','retry');
create index mme_warranty_provider_submission_claim_idx on public.mme_warranty_provider_claim_submissions(provider_claim_id,created_at desc);
create table public.mme_warranty_provider_webhook_events (
 webhook_event_id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.mme_warranty_providers(provider_id) on delete restrict,
 external_event_id text not null,
 event_type text not null,
 payload jsonb not null check(jsonb_typeof(payload)='object'),
 signature_verified boolean not null default false,
 processing_status text not null default 'received' check(processing_status in ('received','processing','processed','ignored','failed')),
 received_at timestamptz not null default now(),
 processed_at timestamptz,
 error_code text,
 unique(provider_id,external_event_id)
);
create index mme_warranty_provider_webhook_queue_idx on public.mme_warranty_provider_webhook_events(processing_status,received_at);
create table public.mme_warranty_provider_sla_events (
 sla_event_id bigint generated always as identity primary key,
 provider_id uuid not null references public.mme_warranty_providers(provider_id) on delete restrict,
 submission_id uuid references public.mme_warranty_provider_claim_submissions(submission_id) on delete restrict,
 event_type text not null check(event_type in ('response_received','response_late','provider_unavailable','claim_decision','reimbursement_confirmed')),
 occurred_at timestamptz not null default now(),
 elapsed_minutes integer check(elapsed_minutes is null or elapsed_minutes>=0),
 event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object')
);
create index mme_warranty_provider_sla_idx on public.mme_warranty_provider_sla_events(provider_id,occurred_at desc);
create table public.mme_warranty_provider_reconciliations (
 reconciliation_id uuid primary key default gen_random_uuid(),
 provider_claim_id uuid not null references public.mme_warranty_provider_claims(provider_claim_id) on delete restrict,
 provider_id uuid not null references public.mme_warranty_providers(provider_id) on delete restrict,
 provider_settlement_reference text not null,
 expected_amount numeric(14,2) not null check(expected_amount>=0),
 received_amount numeric(14,2) not null check(received_amount>=0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 settlement_date date not null,
 status text not null default 'pending' check(status in ('pending','matched','variance','disputed','approved')),
 variance_amount numeric(14,2) generated always as (received_amount-expected_amount) stored,
 approved_by uuid,
 approved_at timestamptz,
 source_reference text not null,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 check(approved_by is null or approved_at is not null),
 unique(provider_id,provider_settlement_reference,currency_code)
);
create index mme_warranty_provider_reconciliation_idx on public.mme_warranty_provider_reconciliations(status,settlement_date desc);

alter table public.mme_warranty_providers enable row level security;
alter table public.mme_warranty_provider_connections enable row level security;
alter table public.mme_warranty_provider_programs enable row level security;
alter table public.mme_warranty_provider_claim_submissions enable row level security;
alter table public.mme_warranty_provider_webhook_events enable row level security;
alter table public.mme_warranty_provider_sla_events enable row level security;
alter table public.mme_warranty_provider_reconciliations enable row level security;
revoke all on public.mme_warranty_providers,public.mme_warranty_provider_connections,public.mme_warranty_provider_programs,public.mme_warranty_provider_claim_submissions,public.mme_warranty_provider_webhook_events,public.mme_warranty_provider_sla_events,public.mme_warranty_provider_reconciliations from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_providers,public.mme_warranty_provider_connections,public.mme_warranty_provider_programs,public.mme_warranty_provider_claim_submissions,public.mme_warranty_provider_webhook_events,public.mme_warranty_provider_reconciliations to service_role;
grant select,insert on public.mme_warranty_provider_sla_events to service_role;

create or replace function public.mme_warranty_provider_enqueue_submission(
 p_claim uuid,p_provider uuid,p_connection uuid,p_program uuid,p_operation text,p_request_reference text,p_payload jsonb,p_actor uuid,p_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.mme_warranty_provider_claims%rowtype; conn public.mme_warranty_provider_connections%rowtype; v uuid; old public.mme_warranty_provider_claim_submissions%rowtype;
begin
 if p_actor is null or length(trim(coalesce(p_key,'')))<12 or length(trim(coalesce(p_request_reference,'')))=0 or jsonb_typeof(coalesce(p_payload,'{}'::jsonb))<>'object' then raise exception 'Actor, request reference, object payload and idempotency key required' using errcode='22023'; end if;
 select * into c from public.mme_warranty_provider_claims where provider_claim_id=p_claim for update;
 if not found then raise exception 'Provider claim not found' using errcode='P0002'; end if;
 select * into conn from public.mme_warranty_provider_connections where connection_id=p_connection and provider_id=p_provider and enabled and environment='production';
 if not found then raise exception 'Enabled production provider connection not found' using errcode='55000'; end if;
 if not exists(select 1 from public.mme_warranty_providers where provider_id=p_provider and status='active') then raise exception 'Provider is not active' using errcode='55000'; end if;
 if p_program is not null and not exists(select 1 from public.mme_warranty_provider_programs where program_id=p_program and provider_id=p_provider and status='active' and active_from<=current_date and (active_to is null or active_to>=current_date)) then raise exception 'Provider program is not active' using errcode='23514'; end if;
 insert into public.mme_warranty_provider_claim_submissions(provider_claim_id,provider_id,connection_id,program_id,operation,request_reference,idempotency_key,request_payload,created_by)
 values(p_claim,p_provider,p_connection,p_program,p_operation,p_request_reference,p_key,p_payload,p_actor)
 on conflict(idempotency_key) do nothing returning submission_id into v;
 if v is null then
  select * into old from public.mme_warranty_provider_claim_submissions where idempotency_key=p_key;
  if old.provider_claim_id<>p_claim or old.provider_id<>p_provider or old.operation<>p_operation or old.request_payload<>p_payload then raise exception 'Idempotency key reused with different provider request' using errcode='23505'; end if;
  return old.submission_id;
 end if;
 return v;
end; $$;

create or replace function public.mme_warranty_provider_record_reconciliation(
 p_claim uuid,p_provider uuid,p_reference text,p_expected numeric,p_received numeric,p_currency text,p_date date,p_source text,p_actor uuid,p_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.mme_warranty_provider_claims%rowtype; v uuid; st text;
begin
 if p_actor is null or p_expected<0 or p_received<0 or length(trim(coalesce(p_key,'')))<12 or length(trim(coalesce(p_reference,'')))=0 then raise exception 'Valid settlement facts, actor and idempotency key required' using errcode='22023'; end if;
 select * into c from public.mme_warranty_provider_claims where provider_claim_id=p_claim for update;
 if not found or c.provider_name is null then raise exception 'Provider claim not found' using errcode='P0002'; end if;
 if not exists(select 1 from public.mme_warranty_providers where provider_id=p_provider and display_name=c.provider_name) then raise exception 'Provider does not match claim' using errcode='23514'; end if;
 st:=case when p_expected=p_received then 'matched' else 'variance' end;
 insert into public.mme_warranty_provider_reconciliations(provider_claim_id,provider_id,provider_settlement_reference,expected_amount,received_amount,currency_code,settlement_date,status,source_reference,idempotency_key)
 values(p_claim,p_provider,p_reference,p_expected,p_received,p_currency,p_date,st,p_source,p_key)
 on conflict(idempotency_key) do nothing returning reconciliation_id into v;
 if v is null then select reconciliation_id into v from public.mme_warranty_provider_reconciliations where idempotency_key=p_key; end if;
 return v;
end; $$;

revoke all on function public.mme_warranty_provider_enqueue_submission(uuid,uuid,uuid,uuid,text,text,jsonb,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_warranty_provider_record_reconciliation(uuid,uuid,text,numeric,numeric,text,date,text,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_provider_enqueue_submission(uuid,uuid,uuid,uuid,text,text,jsonb,uuid,text) to service_role;
grant execute on function public.mme_warranty_provider_record_reconciliation(uuid,uuid,text,numeric,numeric,text,date,text,uuid,text) to service_role;
commit;