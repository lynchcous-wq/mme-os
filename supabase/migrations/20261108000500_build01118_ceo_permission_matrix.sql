-- Build 011.18 — CEO permission matrix catalog. Templates are metadata only, not runtime grants.
create table if not exists public.mme_role_permission_templates (
 id uuid primary key default gen_random_uuid(),
 role_key text not null references public.mme_roles(role_key) on update restrict on delete restrict,
 resource_key text not null,
 action_key text not null,
 scope jsonb not null default '{}'::jsonb,
 requires_mfa boolean not null default true,
 requires_recent_auth boolean not null default true,
 approval_status text not null default 'pending_review' check (approval_status in ('pending_review','approved','rejected','retired')),
 version integer not null default 1 check (version > 0),
 created_at timestamptz not null default now(),
 unique (role_key,resource_key,action_key,version)
);
alter table public.mme_role_permission_templates enable row level security;
revoke all on public.mme_role_permission_templates from public, anon, authenticated;
grant select,insert,update,delete on public.mme_role_permission_templates to service_role;
insert into public.mme_role_permission_templates
(role_key,resource_key,action_key,scope,requires_mfa,requires_recent_auth,approval_status,version)
values
('ceo','executive.dashboard','read','{"organization":"MME"}',true,true,'pending_review',1),
('ceo','employees.directory','read','{"organization":"MME"}',true,true,'pending_review',1),
('ceo','employees.relationships','read','{"organization":"MME"}',true,true,'pending_review',1),
('ceo','employees.relationships','manage_status','{"organization":"MME","allowed_statuses":["active","temporarily_suspended","frozen","terminated"]}',true,true,'pending_review',1),
('ceo','identities.security','lock','{"organization":"MME","self_target_allowed":false}',true,true,'pending_review',1),
('ceo','identities.security','unlock','{"organization":"MME","requires_secondary_approval":true,"self_target_allowed":false}',true,true,'pending_review',1),
('ceo','roles.assignments','read','{"organization":"MME"}',true,true,'pending_review',1),
('ceo','permissions.grants','read','{"organization":"MME"}',true,true,'pending_review',1),
('ceo','audit.identity','read','{"organization":"MME","immutable":true}',true,true,'pending_review',1),
('ceo','finance.reports','read','{"organization":"MME","sensitive_data":"masked_by_default"}',true,true,'pending_review',1),
('ceo','inventory.catalog','read','{"organization":"MME"}',true,true,'pending_review',1),
('ceo','orders.sales','read','{"organization":"MME","customer_pii":"minimum_necessary"}',true,true,'pending_review',1)
on conflict (role_key,resource_key,action_key,version) do nothing;