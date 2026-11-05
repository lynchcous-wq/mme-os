begin;
select plan(2);

select ok(
  lower(pg_get_functiondef('public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)'::regprocedure))
    like '%mme_finish_workflow_execution%',
  'final step completion delegates to the authoritative execution completion gate'
);

select ok(
  lower(pg_get_functiondef('public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)'::regprocedure))
    not like '%set execution_status=''succeeded''%',
  'step completion cannot directly mark the parent execution succeeded'
);

select * from finish();
rollback;
