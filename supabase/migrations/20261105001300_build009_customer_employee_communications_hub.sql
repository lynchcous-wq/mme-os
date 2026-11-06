-- Build 009.50 — customer and employee communications hub.
-- Consent-first marketing; transactional messages require a documented business trigger.
begin;

create table public.mme_communications_contact_consent (
 id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 channel text not null check(channel in ('email','sms','push')),
 purpose text not null check(purpose in ('marketing','transactional','employee_operational')),
 consent_status text not null check(consent_status in ('opted_in','opted_out','unknown')),
 source text not null check(source in ('checkout','account_settings','employee_portal','signed_form','support','import')),
 evidence_reference text,
 captured_at timestamptz not null default now(),
 captured_by_person_id uuid,
 revoked_at timestamptz,
 created_at timestamptz not null default now(),
 check((consent_status='opted_out')=(revoked_at is not null) or consent_status<>'opted_out')
);
create index mme_communications_consent_lookup_idx
 on public.mme_communications_contact_consent(person_id,purpose,channel,captured_at desc);

create table public.mme_communications_campaigns (
 id uuid primary key default gen_random_uuid(),
 campaign_key text not null unique,
 title text not null check(length(btrim(title)) between 3 and 180),
 purpose text not null check(purpose in ('marketing','transactional','employee_operational','executive_announcement')),
 audience_type text not null check(audience_type in ('customers','employees','all_employees','selected_recipients')),
 channel text not null check(channel in ('email','sms','push','in_app')),
 template_key text not null,
 locale text not null default 'en-US',
 source_reference text,
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','dispatching','completed','cancelled')),
 created_by_person_id uuid not null,
 approved_by_person_id uuid,
 approved_at timestamptz,
 scheduled_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((approved_by_person_id is null)=(approved_at is null))
);
create index mme_communications_campaigns_queue_idx
 on public.mme_communications_campaigns(status,scheduled_at,created_at);

create table public.mme_communications_campaign_recipients (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.mme_communications_campaigns(id) on delete restrict,
 person_id uuid not null,
 eligibility_status text not null default 'eligible' check(eligibility_status in ('eligible','suppressed_no_consent','suppressed_preference','suppressed_inactive','queued')),
 delivery_job_id uuid references public.mme_notification_delivery_jobs(id) on delete restrict,
 idempotency_key text not null unique,
 created_at timestamptz not null default now(),
 unique(campaign_id,person_id)
);
create index mme_communications_campaign_recipient_idx
 on public.mme_communications_campaign_recipients(campaign_id,eligibility_status);

create table public.mme_communications_interaction_history (
 id uuid primary key default gen_random_uuid(),
 person_id uuid not null,
 campaign_id uuid references public.mme_communications_campaigns(id) on delete restrict,
 delivery_job_id uuid references public.mme_notification_delivery_jobs(id) on delete restrict,
 interaction_type text not null check(interaction_type in ('queued','sent','delivered','opened','clicked','replied','bounced','unsubscribed','failed')),
 channel text not null check(channel in ('email','sms','push','in_app')),
 source_reference text,
 occurred_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object')
);
create index mme_communications_interaction_person_idx
 on public.mme_communications_interaction_history(person_id,occurred_at desc);
create index mme_communications_interaction_campaign_idx
 on public.mme_communications_interaction_history(campaign_id,interaction_type,occurred_at desc);

alter table public.mme_communications_contact_consent enable row level security;
alter table public.mme_communications_campaigns enable row level security;
alter table public.mme_communications_campaign_recipients enable row level security;
alter table public.mme_communications_interaction_history enable row level security;
revoke all on public.mme_communications_contact_consent,public.mme_communications_campaigns,
 public.mme_communications_campaign_recipients,public.mme_communications_interaction_history
 from public,anon,authenticated;
grant select,insert,update on public.mme_communications_contact_consent to service_role;
grant select,insert,update on public.mme_communications_campaigns,
 public.mme_communications_campaign_recipients to service_role;
grant select,insert on public.mme_communications_interaction_history to service_role;
revoke update,delete,truncate on public.mme_communications_interaction_history from public,anon,authenticated;

create or replace function public.mme_communications_record_consent(
 p_person_id uuid,p_actor_person_id uuid,p_channel text,p_purpose text,p_status text,
 p_source text,p_evidence_reference text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if p_person_id is null or p_actor_person_id is null or p_channel is null
  or p_channel not in ('email','sms','push') or p_purpose not in ('marketing','transactional','employee_operational')
  or p_status not in ('opted_in','opted_out','unknown')
  or p_source not in ('checkout','account_settings','employee_portal','signed_form','support','import') then
  raise exception 'Invalid consent record' using errcode='22023';
 end if;
 if p_person_id<>p_actor_person_id and not exists(
  select 1 from public.mme_person_identities i where i.person_id=p_actor_person_id and i.lifecycle_status='active'
 ) then raise exception 'Active authorized actor required' using errcode='42501'; end if;
 insert into public.mme_communications_contact_consent(person_id,channel,purpose,consent_status,
  source,evidence_reference,captured_by_person_id,revoked_at)
 values(p_person_id,p_channel,p_purpose,p_status,p_source,left(p_evidence_reference,240),p_actor_person_id,
  case when p_status='opted_out' then now() else null end)
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_communications_create_campaign(
 p_campaign_key text,p_title text,p_purpose text,p_audience_type text,p_channel text,
 p_template_key text,p_locale text,p_source_reference text,p_actor_person_id uuid,p_scheduled_at timestamptz default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_permission text;
begin
 if p_actor_person_id is null or p_campaign_key is null or p_title is null
  or p_purpose not in ('marketing','transactional','employee_operational','executive_announcement')
  or p_audience_type not in ('customers','employees','all_employees','selected_recipients')
  or p_channel not in ('email','sms','push','in_app') or p_template_key is null
  or p_locale is null then raise exception 'Invalid campaign details' using errcode='22023'; end if;
 v_permission:=case when p_purpose='executive_announcement' then 'pos.financial.executive.alerts'
  when p_purpose='marketing' then 'crm.campaign.manage' else 'communications.manage' end;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,
   coalesce((select id from public.mme_store_locations order by id limit 1),gen_random_uuid()),v_permission) then
  raise exception 'Campaign creation permission denied' using errcode='42501';
 end if;
 insert into public.mme_communications_campaigns(campaign_key,title,purpose,audience_type,channel,
  template_key,locale,source_reference,created_by_person_id,scheduled_at,status)
 values(p_campaign_key,p_title,p_purpose,p_audience_type,p_channel,p_template_key,p_locale,
  left(p_source_reference,240),p_actor_person_id,p_scheduled_at,'pending_approval')
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_communications_approve_campaign(
 p_campaign_id uuid,p_actor_person_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_campaign public.mme_communications_campaigns%rowtype; v_permission text;
begin
 select * into v_campaign from public.mme_communications_campaigns where id=p_campaign_id for update;
 if not found then raise exception 'Campaign not found' using errcode='P0002'; end if;
 if v_campaign.status<>'pending_approval' then raise exception 'Campaign is not awaiting approval' using errcode='55000'; end if;
 if v_campaign.created_by_person_id=p_actor_person_id then
  raise exception 'Campaign creator cannot approve their own campaign' using errcode='42501';
 end if;
 v_permission:=case when v_campaign.purpose='executive_announcement' then 'pos.financial.executive.alerts'
  else 'communications.approve' end;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,
   coalesce((select id from public.mme_store_locations order by id limit 1),gen_random_uuid()),v_permission) then
  raise exception 'Campaign approval permission denied' using errcode='42501';
 end if;
 update public.mme_communications_campaigns set status='approved',
  approved_by_person_id=p_actor_person_id,approved_at=now(),updated_at=now() where id=p_campaign_id;
 return p_campaign_id;
end;
$$;

create or replace function public.mme_communications_dispatch_recipient(
 p_campaign_id uuid,p_recipient_person_id uuid,p_actor_person_id uuid,p_payload jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_campaign public.mme_communications_campaigns%rowtype;
 v_id uuid; v_status text:='eligible'; v_consent boolean:=false; v_job uuid;
begin
 select * into v_campaign from public.mme_communications_campaigns where id=p_campaign_id for update;
 if not found then raise exception 'Campaign not found' using errcode='P0002'; end if;
 if v_campaign.status not in ('approved','dispatching') then raise exception 'Campaign is not approved for dispatch' using errcode='55000'; end if;
 if not public.mme_pos_authorize_settlement_action(p_actor_person_id,
   coalesce((select id from public.mme_store_locations order by id limit 1),gen_random_uuid()),'communications.dispatch') then
  raise exception 'Campaign dispatch permission denied' using errcode='42501';
 end if;
 if not exists(select 1 from public.mme_person_identities i
  where i.person_id=p_recipient_person_id and i.lifecycle_status='active') then
  v_status:='suppressed_inactive';
 elsif v_campaign.purpose='marketing' and v_campaign.channel in ('email','sms','push') then
  select exists(select 1 from public.mme_communications_contact_consent c
   where c.person_id=p_recipient_person_id and c.channel=v_campaign.channel
    and c.purpose='marketing' and c.consent_status='opted_in'
    and c.captured_at>coalesce((select max(x.captured_at) from public.mme_communications_contact_consent x
     where x.person_id=c.person_id and x.channel=c.channel and x.purpose=c.purpose
      and x.consent_status='opted_out'),'-infinity'::timestamptz)) into v_consent;
  if not v_consent then v_status:='suppressed_no_consent'; end if;
 end if;
 insert into public.mme_communications_campaign_recipients(campaign_id,person_id,eligibility_status,idempotency_key)
 values(p_campaign_id,p_recipient_person_id,v_status,
  'campaign:'||p_campaign_id::text||':recipient:'||p_recipient_person_id::text)
 on conflict(campaign_id,person_id) do update set eligibility_status=excluded.eligibility_status
 returning id into v_id;
 if v_status<>'eligible' then return v_id; end if;
 v_job:=public.mme_notification_enqueue_delivery(null,p_recipient_person_id,v_campaign.channel,
  v_campaign.template_key,v_campaign.locale,coalesce(p_payload,'{}'::jsonb),
  'campaign:'||p_campaign_id::text||':recipient:'||p_recipient_person_id::text);
 update public.mme_communications_campaign_recipients set eligibility_status='queued',delivery_job_id=v_job
 where id=v_id;
 insert into public.mme_communications_interaction_history(person_id,campaign_id,delivery_job_id,
  interaction_type,channel,source_reference)
 values(p_recipient_person_id,p_campaign_id,v_job,'queued',v_campaign.channel,v_campaign.source_reference);
 update public.mme_communications_campaigns set status='dispatching',updated_at=now() where id=p_campaign_id;
 return v_job;
end;
$$;

create or replace function public.mme_communications_record_interaction(
 p_person_id uuid,p_campaign_id uuid,p_delivery_job_id uuid,p_interaction_type text,
 p_channel text,p_source_reference text,p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if p_person_id is null or p_interaction_type not in ('sent','delivered','opened','clicked','replied','bounced','unsubscribed','failed')
  or p_channel not in ('email','sms','push','in_app') or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
  raise exception 'Invalid communication interaction' using errcode='22023';
 end if;
 insert into public.mme_communications_interaction_history(person_id,campaign_id,delivery_job_id,
  interaction_type,channel,source_reference,metadata)
 values(p_person_id,p_campaign_id,p_delivery_job_id,p_interaction_type,p_channel,
  left(p_source_reference,240),p_metadata) returning id into v_id;
 if p_interaction_type='unsubscribed' and p_channel in ('email','sms','push') then
  perform public.mme_communications_record_consent(p_person_id,p_person_id,p_channel,'marketing',
   'opted_out','account_settings',p_source_reference);
 end if;
 return v_id;
end;
$$;

create or replace view public.mme_communications_campaign_analytics
with (security_invoker=true) as
select c.id campaign_id,c.campaign_key,c.title,c.purpose,c.audience_type,c.channel,c.status,
 count(distinct r.id)::integer recipients,
 count(distinct r.id) filter(where r.eligibility_status='suppressed_no_consent')::integer suppressed_no_consent,
 count(distinct r.id) filter(where r.eligibility_status='queued')::integer queued,
 count(distinct h.id) filter(where h.interaction_type='sent')::integer sent,
 count(distinct h.id) filter(where h.interaction_type='delivered')::integer delivered,
 count(distinct h.id) filter(where h.interaction_type='opened')::integer opened,
 count(distinct h.id) filter(where h.interaction_type='clicked')::integer clicked,
 count(distinct h.id) filter(where h.interaction_type='unsubscribed')::integer unsubscribed
from public.mme_communications_campaigns c
left join public.mme_communications_campaign_recipients r on r.campaign_id=c.id
left join public.mme_communications_interaction_history h on h.campaign_id=c.id
group by c.id;

revoke all on function public.mme_communications_record_consent(uuid,uuid,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_communications_create_campaign(text,text,text,text,text,text,text,text,uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_communications_approve_campaign(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_communications_dispatch_recipient(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.mme_communications_record_interaction(uuid,uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on public.mme_communications_campaign_analytics from public,anon,authenticated;
grant execute on function public.mme_communications_record_consent(uuid,uuid,text,text,text,text,text) to service_role;
grant execute on function public.mme_communications_create_campaign(text,text,text,text,text,text,text,text,uuid,timestamptz) to service_role;
grant execute on function public.mme_communications_approve_campaign(uuid,uuid) to service_role;
grant execute on function public.mme_communications_dispatch_recipient(uuid,uuid,uuid,jsonb) to service_role;
grant execute on function public.mme_communications_record_interaction(uuid,uuid,uuid,text,text,text,jsonb) to service_role;
grant select on public.mme_communications_campaign_analytics to service_role;

comment on table public.mme_communications_contact_consent is
 'Append-only evidence of channel and purpose-specific consent and revocation for customer and employee communications.';
comment on table public.mme_communications_campaigns is
 'Approval-gated communications campaigns and employee announcements.';
comment on view public.mme_communications_campaign_analytics is
 'Campaign reach, suppression, delivery and engagement metrics.';

commit;
