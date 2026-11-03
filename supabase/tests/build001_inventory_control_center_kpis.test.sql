begin;
select plan(4);
select has_function('public','mme_get_inventory_control_summary',array['uuid'],'inventory control KPIs RPC exists');
select has_function('public','mme_get_inventory_movement_feed',array['uuid','uuid','text','timestamp with time zone','timestamp with time zone','integer','integer'],'movement feed RPC exists');
select ok(not has_function_privilege('anon','public.mme_get_inventory_control_summary(uuid)','execute'),'anon cannot execute summary RPC');
select ok(not has_function_privilege('authenticated','public.mme_get_inventory_movement_feed(uuid,uuid,text,timestamptz,timestamptz,integer,integer)','execute'),'authenticated cannot execute movement feed RPC');
select * from finish();
rollback;