begin;
select plan(5);
select has_function('public','mme_approve_supplier_payment_schedule',array['uuid','uuid'],'independent AP schedule approval exists');
select ok(not has_function_privilege('authenticated','public.mme_approve_supplier_payment_schedule(uuid,uuid)','execute'),'browser cannot approve AP schedules');
select ok(has_function_privilege('service_role','public.mme_approve_supplier_payment_schedule(uuid,uuid)','execute'),'trusted service can approve AP schedules');
select ok(pg_get_functiondef('public.mme_guard_purchase_order_approval()'::regprocedure) like '%new.approved_by_identity_id=new.created_by_identity_id%','PO approval rejects creator self-approval at threshold');
select ok(pg_get_functiondef('public.mme_approve_supplier_payment_schedule(uuid,uuid)'::regprocedure) like '%v_requested%','AP release checks independent invoice approval');
select * from finish();
rollback;