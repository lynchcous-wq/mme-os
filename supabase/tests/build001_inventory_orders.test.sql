-- Build 001 inventory/order schema smoke tests.
-- Run with Supabase CLI / pgTAP against a disposable database after migrations 001-006.
begin;
select plan(20);

select has_table('public','mme_store_locations','store locations table exists');
select has_table('public','mme_products','product catalog table exists');
select has_table('public','mme_inventory_balances','inventory balances table exists');
select has_table('public','mme_orders','orders table exists');
select has_table('public','mme_order_lines','order lines table exists');
select has_table('public','mme_inventory_reservations','reservations table exists');
select has_table('public','mme_inventory_reservation_lines','reservation lines table exists');
select has_table('public','mme_payment_events','payment event ledger exists');
select has_column('public','mme_order_lines','location_id','order line snapshots retain fulfillment location');
select has_function(
  'public',
  'mme_reserve_inventory',
  array['uuid','jsonb','timestamp with time zone'],
  'atomic inventory reservation function exists'
);

select ok(
  not has_table_privilege('anon','public.mme_orders','select'),
  'anon cannot read orders'
);
select ok(
  not has_table_privilege('authenticated','public.mme_orders','select'),
  'authenticated cannot directly read orders'
);
select ok(
  not has_table_privilege('anon','public.mme_inventory_balances','update'),
  'anon cannot update inventory balances'
);
select ok(
  not has_table_privilege('authenticated','public.mme_inventory_balances','update'),
  'authenticated cannot update inventory balances'
);
select ok(
  has_table_privilege('service_role','public.mme_orders','select'),
  'service_role can read orders'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.mme_reserve_inventory(uuid,jsonb,timestamp with time zone)',
    'execute'
  ),
  'service_role can execute reservation function'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.mme_reserve_inventory(uuid,jsonb,timestamp with time zone)',
    'execute'
  ),
  'authenticated cannot execute reservation function'
);

select has_function(
  'public',
  'mme_create_order_and_reserve',
  array['text','uuid','text','jsonb','bigint','bigint','bigint','jsonb','timestamp with time zone'],
  'atomic order creation and reservation function exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.mme_create_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamp with time zone)',
    'execute'
  ),
  'service_role can execute atomic order creation function'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.mme_create_order_and_reserve(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamp with time zone)',
    'execute'
  ),
  'authenticated cannot execute atomic order creation function'
);

select * from finish();
rollback;
