\set ON_ERROR_STOP on
-- Run only in a disposable database after applying the migration.
do $$ begin
  if has_table_privilege('anon','recipe_private.jobs','select') then raise exception 'anon table leak'; end if;
  if has_function_privilege('authenticated','public.recipe_reserve(text,uuid,text,uuid,bigint)','execute') then raise exception 'client RPC leak'; end if;
  if not has_function_privilege('service_role','public.recipe_reserve(text,uuid,text,uuid,bigint)','execute') then raise exception 'service RPC unavailable'; end if;
end $$;
create function pg_temp.check_code(value jsonb, expected text) returns void language plpgsql as $$ begin if value->>'code' is distinct from expected then raise exception 'expected %, got %',expected,value; end if; end $$;
select pg_temp.check_code(public.recipe_issue(repeat('a',64),'11111111-1111-4111-8111-111111111111'),'disabled');
update recipe_private.config set enabled=true,daily_budget_micro=1000000,monthly_budget_micro=10000000,request_reserve_micro=70000,max_concurrent=10;
select pg_temp.check_code(public.recipe_reserve(repeat('a',64),'11111111-1111-4111-8111-111111111111',repeat('b',64),'22222222-2222-4222-8222-222222222222',70000),'not_found');
select pg_temp.check_code(public.recipe_issue(repeat('a',64),'11111111-1111-4111-8111-111111111111'),'issued');
select pg_temp.check_code(public.recipe_issue(repeat('a',64),'11111111-1111-4111-8111-111111111111'),'issued');
select pg_temp.check_code(public.recipe_reserve(repeat('a',64),'11111111-1111-4111-8111-111111111111',repeat('b',64),'22222222-2222-4222-8222-222222222222',70000),'reserved');
select pg_temp.check_code(public.recipe_reserve(repeat('a',64),'11111111-1111-4111-8111-111111111111',repeat('b',64),'33333333-3333-4333-8333-333333333333',70000),'in_progress');
select pg_temp.check_code(public.recipe_reserve(repeat('a',64),'11111111-1111-4111-8111-111111111111',repeat('c',64),'33333333-3333-4333-8333-333333333333',70000),'conflict');
select pg_temp.check_code(public.recipe_lookup(repeat('d',64),'11111111-1111-4111-8111-111111111111'),'not_found');
select pg_temp.check_code(public.recipe_finish(repeat('a',64),'11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',true,'cipher',1000,null,'mock'),'conflict');
select pg_temp.check_code(public.recipe_finish(repeat('a',64),'11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',true,'cipher',1000,null,'mock'),'complete');
select pg_temp.check_code(public.recipe_reserve(repeat('a',64),'11111111-1111-4111-8111-111111111111',repeat('b',64),'33333333-3333-4333-8333-333333333333',70000),'complete');
do $$ begin if (select charged_micro from recipe_private.budgets where kind='day')<>1000 then raise exception 'budget not settled'; end if; if (select used from recipe_private.quotas where session_hash=repeat('a',64))<>1 then raise exception 'quota not charged'; end if; end $$;
-- Server-issued validity cannot be refreshed, and expired jobs never generate again.
update recipe_private.jobs set expires_at=now()-interval '1 second' where request_id='11111111-1111-4111-8111-111111111111';
select pg_temp.check_code(public.recipe_issue(repeat('a',64),'11111111-1111-4111-8111-111111111111'),'expired');
select pg_temp.check_code(public.recipe_reserve(repeat('a',64),'11111111-1111-4111-8111-111111111111',repeat('b',64),'33333333-3333-4333-8333-333333333333',70000),'expired');
do $$ begin if (select ciphertext from recipe_private.jobs where request_id='11111111-1111-4111-8111-111111111111') is not null then raise exception 'expired payload retained'; end if; end $$;
-- Recovering an ambiguous timeout refunds user quota but conservatively charges cost.
select public.recipe_issue(repeat('a',64),'44444444-4444-4444-8444-444444444444');
select public.recipe_reserve(repeat('a',64),'44444444-4444-4444-8444-444444444444',repeat('b',64),'55555555-5555-4555-8555-555555555555',70000);
update recipe_private.jobs set lease_until=now()-interval '1 second' where request_id='44444444-4444-4444-8444-444444444444';
select pg_temp.check_code(public.recipe_lookup(repeat('a',64),'44444444-4444-4444-8444-444444444444'),'timeout');
do $$ begin if (select reserved from recipe_private.quotas where session_hash=repeat('a',64))<>0 then raise exception 'quota reserved after recovery'; end if; if (select charged_micro from recipe_private.budgets where kind='day')<>71000 then raise exception 'unknown cost not retained'; end if; end $$;
-- Generation failures release daily quota but retain measured provider costs.
select public.recipe_issue(repeat('e',64),'66666666-6666-4666-8666-666666666666');
select public.recipe_reserve(repeat('e',64),'66666666-6666-4666-8666-666666666666',repeat('b',64),'77777777-7777-4777-8777-777777777777',70000);
select public.recipe_finish(repeat('e',64),'66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777',false,'failure-cipher',2000,'unavailable','mock');
do $$ begin if (select used+reserved from recipe_private.quotas where session_hash=repeat('e',64))<>0 then raise exception 'service failure charged daily user quota'; end if; end $$;
-- KST boundaries are derived on the server.
do $$ begin if ('2026-11-04T15:00:00Z'::timestamptz at time zone 'Asia/Seoul')::date<>'2026-11-05'::date then raise exception 'KST day'; end if; end $$;
select pg_temp.check_code(public.recipe_rate_gate(repeat('f',64),1),'ok');
select pg_temp.check_code(public.recipe_rate_gate(repeat('f',64),1),'rate_limited');
-- Retained compact tombstones survive metadata cleanup.
update recipe_private.jobs set created_at=now()-interval '40 days',expires_at=now()-interval '39 days' where request_id='11111111-1111-4111-8111-111111111111';
select public.recipe_maintenance();
do $$ begin if not exists(select 1 from recipe_private.jobs where request_id='11111111-1111-4111-8111-111111111111' and state='expired' and request_hash is null and ciphertext is null) then raise exception 'tombstone missing'; end if; end $$;
select 'SQL behavior checks passed' as result;
