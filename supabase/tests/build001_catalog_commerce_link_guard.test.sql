begin;
select plan(16);

select has_column(
  'public','mme_products','catalog_product_id',
  'commerce products expose explicit catalog link'
);
select has_table(
  'public','mme_product_catalog_link_events',
  'catalog-commerce link audit table exists'
);
select has_index(
  'public','mme_products','mme_products_catalog_product_id_uidx',
  'catalog link is unique when populated'
);
select has_trigger(
  'public','mme_products','mme_products_validate_catalog_link',
  'catalog link and SKU validation trigger exists'
);
select has_trigger(
  'public','products','products_prevent_linked_sku_change',
  'catalog SKU cannot drift after commerce link'
);
select has_trigger(
  'public','mme_order_lines','mme_order_lines_require_published_catalog',
  'order-line sale guard exists'
);
select has_trigger(
  'public','mme_product_catalog_link_events','mme_product_catalog_link_events_immutable',
  'link audit rows cannot be updated or deleted'
);

select ok(
  (select c.confdeltype = 'r'
   from pg_constraint c
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=any(c.conkey)
   where c.conrelid='public.mme_products'::regclass
     and c.contype='f' and a.attname='catalog_product_id'
   limit 1),
  'catalog product deletion is restricted while linked'
);

select ok(
  (select relrowsecurity from pg_class where oid='public.mme_product_catalog_link_events'::regclass),
  'link audit table has row-level security enabled'
);
select ok(
  not has_table_privilege('anon','public.mme_product_catalog_link_events','select'),
  'anon cannot read link audit events'
);
select ok(
  not has_table_privilege('authenticated','public.mme_product_catalog_link_events','insert'),
  'authenticated cannot directly forge link audit events'
);
select ok(
  has_table_privilege('service_role','public.mme_product_catalog_link_events','insert'),
  'service role can record link audit events'
);

select ok(
  position('Cannot change catalog SKU while a commerce product is linked' in pg_get_functiondef('public.mme_prevent_linked_catalog_sku_change()'::regprocedure)) > 0,
  'catalog SKU mutation is blocked after a commerce link exists'
);
select ok(
  position('catalog_status' in pg_get_functiondef('public.mme_require_published_catalog_product()'::regprocedure)) > 0
  and position('published' in pg_get_functiondef('public.mme_require_published_catalog_product()'::regprocedure)) > 0,
  'sale guard checks published catalog state'
);
select ok(
  position('catalog_product_id' in pg_get_functiondef('public.mme_require_published_catalog_product()'::regprocedure)) > 0
  and position('active' in pg_get_functiondef('public.mme_require_published_catalog_product()'::regprocedure)) > 0,
  'sale guard requires explicit link and active commerce record'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.mme_require_published_catalog_product()',
    'execute'
  ),
  'authenticated users cannot directly execute trigger function'
);
select * from finish();
rollback;
