-- Per-session test quota override; default and financial limits are unchanged.
begin;
create table recipe_private.quota_overrides (
 session_hash text primary key check(session_hash ~ '^[a-f0-9]{64}$'),
 daily_limit integer not null check(daily_limit between 1 and 100),
 expires_at timestamptz not null
);
alter table recipe_private.quota_overrides enable row level security;
revoke all on recipe_private.quota_overrides from public,anon,authenticated,service_role;
do $$
declare definition text; needle text:='if q.used+q.reserved>=5 then';
begin
 definition:=pg_get_functiondef('public.recipe_reserve_base(text,uuid,text,uuid,bigint)'::regprocedure);
 if (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 then
  raise exception 'Unexpected quota function: migration must be reviewed';
 end if;
 definition:=replace(definition,needle,'if q.used+q.reserved>=coalesce((select daily_limit from recipe_private.quota_overrides where session_hash=p_session_hash and expires_at>clock_timestamp()),5) then');
 execute definition;
end $$;
commit;
