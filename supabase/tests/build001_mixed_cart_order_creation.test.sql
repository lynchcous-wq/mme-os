begin;
select plan(15);

-- The legacy 9-argument overload remains present for migration compatibility,
-- but only the quote-bound 10-argument overload may be executed by the trusted server.
select has_function(
 'public','mme_create_mixed_order_and_reserve',
 array['text','uuid','text','jsonb','bigint','bigint','bigint','jsonb','timestamp with time zone'],
 'legacy mixed-order overload remains identifiable'
);
select has_function(
 'public','mme_create_mixed_order_and_reserve',
 array['text','uuid','text','jsonb','bigint','bigint','bigint','jsonb','bigint','timestamp with time zone'],
 'quote-bound mixed-order RPC exists'
);
select ok(
 not has_function_privilege('authenticated','public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamptz)','execute'),
 'browser cannot execute legacy mixed-order overload'
);
select ok(
 not has_function_privilege('service_role','public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamptz)','execute'),
 'trusted server cannot bypass quote validation through legacy overload'
);
select ok(
 has_function_privilege('service_role','public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)','execute'),
 'trusted server role can create quote-bound mixed orders'
);
select ok(position('mme_serialized_unit_reservations' in pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure))>0,'serialized unit reservations are created');
select ok(position('mme_inventory_reservation_lines' in pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure))>0,'aggregate stock reservations are created');
select ok(position('mme_order_lines' in pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure))>0,'all cart items get order snapshots');
select ok(position('serialized_unit_id' in pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure))>0,'serialized units are individually identified');
select ok(position('request_fingerprint' in pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure))>0,'idempotency fingerprint is enforced');
select ok(position('for update' in lower(pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure)))>0,'inventory rows are locked during reservation');
select ok(position('p_customer_identity_id is null' in lower(pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure)))>0,'customer identity is mandatory');
select ok(position('group by x.serialized_unit_id having count(*)>1' in lower(pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure)))>0,'duplicate serialized units are rejected');
select ok(position($q$unit_status<>'in_stock'$q$ in lower(pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure)))>0,'only in-stock serialized units can be reserved');
select ok(position($q$where id=v_item.serialized_unit_id and unit_status='in_stock'$q$ in lower(pg_get_functiondef('public.mme_create_mixed_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz)'::regprocedure)))>0,'serialized unit state is rechecked at write time');
select * from finish();
rollback;
