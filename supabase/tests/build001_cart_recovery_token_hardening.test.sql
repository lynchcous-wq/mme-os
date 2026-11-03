begin;
select plan(5);
select has_column('public','mme_cart_sessions','recovery_attempt_count','cart recovery attempts are counted');
select has_column('public','mme_cart_sessions','recovery_max_attempts','cart recovery attempts have a cap');
select ok(position('recovery_attempt_count>=v_cart.recovery_max_attempts' in pg_get_functiondef('public.mme_restore_abandoned_cart(uuid,text)'::regprocedure))>0,'restore blocks after maximum attempts');
select ok(position('recovery_attempt_count=recovery_attempt_count+1' in pg_get_functiondef('public.mme_restore_abandoned_cart(uuid,text)'::regprocedure))>0,'each verification attempt is counted');
select ok(position('digest(' in pg_get_functiondef('public.mme_issue_cart_recovery_token(uuid,text,timestamp with time zone)'::regprocedure))=0,'token issue does not require pgcrypto digest extension');
select * from finish();
rollback;