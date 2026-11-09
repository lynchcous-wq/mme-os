-- Build 010.83 — verified customer identity-link requests.
-- Requests are not identity links. Only a separately authorized operator may review
-- the evidence and invoke the existing service-role-only provisioning workflow.
begin;

create table public.mme_customer_identity_link_requests (
 request_id uuid primary key default gen_random_uuid(),
 auth_user_id uuid not null references auth.users(id) on delete restrict,
 verified_email text not null,
 email_verified_at timestamptz not null,
 customer_reference text,
 contact_phone_last4 text,
 customer_note text,
 request_status text not null default 'pending'
  check(request_status in ('pending','under_review','approved','rejected','withdrawn')),
 requested_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by_auth_user_id uuid references auth.users(id) on delete restrict,
 review_note text,
 linked_person_id uuid references public.mme_person_identities(person_id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(length(verified_email) between 3 and 320),
 check(customer_reference is null or length(customer_reference) between 1 and 80),
 check(contact_phone_last4 is null or contact_phone_last4 ~ '^[0-9]{4}$'),
 check(customer_note is null or length(customer_note)<=1000),
 check(review_note is null or length(review_note)<=1000),
 check((request_status='approved' and reviewed_at is not null and reviewed_by_auth_user_id is not null and linked_person_id is not null)
    or request_status<>'approved')
);
create unique index mme_customer_identity_link_one_pending_uidx
 on public.mme_customer_identity_link_requests(auth_user_id)
 where request_status in ('pending','under_review');
create index mme_customer_identity_link_review_idx
 on public.mme_customer_identity_link_requests(request_status,requested_at);

create table public.mme_customer_identity_link_request_audit (
 audit_id bigint generated always as identity primary key,
 request_id uuid not null references public.mme_customer_identity_link_requests(request_id) on delete restrict,
 action text not null check(action in ('submitted','review_started','approved','rejected','withdrawn')),
 actor_auth_user_id uuid,
 actor_kind text not null check(actor_kind in ('customer','staff','system')),
 detail jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index mme_customer_identity_link_audit_request_idx
 on public.mme_customer_identity_link_request_audit(request_id,created_at);

create function public.mme_customer_identity_link_request_audit_fn()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_action text;
begin
 if tg_op='INSERT' then
  insert into public.mme_customer_identity_link_request_audit(request_id,action,actor_auth_user_id,actor_kind)
  values(new.request_id,'submitted',new.auth_user_id,'customer');
  return new;
 end if;
 if new.request_status is distinct from old.request_status then
  v_action := case new.request_status
   when 'under_review' then 'review_started'
   when 'approved' then 'approved'
   when 'rejected' then 'rejected'
   when 'withdrawn' then 'withdrawn'
   else null end;
  if v_action is not null then
   insert into public.mme_customer_identity_link_request_audit(request_id,action,actor_auth_user_id,actor_kind,detail)
   values(new.request_id,v_action,new.reviewed_by_auth_user_id,
    case when new.request_status='withdrawn' then 'customer' else 'staff' end,
    jsonb_build_object('previous_status',old.request_status,'linked_person_id',new.linked_person_id));
  end if;
 end if;
 return new;
end;
$$;
create trigger mme_customer_identity_link_request_audit_trg
 after insert or update on public.mme_customer_identity_link_requests
 for each row execute function public.mme_customer_identity_link_request_audit_fn();

alter table public.mme_customer_identity_link_requests enable row level security;
alter table public.mme_customer_identity_link_request_audit enable row level security;
revoke all on public.mme_customer_identity_link_requests,public.mme_customer_identity_link_request_audit from public,anon,authenticated;
grant select,insert,update on public.mme_customer_identity_link_requests to service_role;
grant select,insert on public.mme_customer_identity_link_request_audit to service_role;
grant usage,select on sequence public.mme_customer_identity_link_request_audit_audit_id_seq to service_role;
revoke all on function public.mme_customer_identity_link_request_audit_fn() from public,anon,authenticated,service_role;

comment on table public.mme_customer_identity_link_requests is
 'Build 010.83 customer-submitted request queue. A request is not proof of identity and never grants account access.';
comment on table public.mme_customer_identity_link_request_audit is
 'Append-only audit trail for customer identity-link request lifecycle events.';
commit;
