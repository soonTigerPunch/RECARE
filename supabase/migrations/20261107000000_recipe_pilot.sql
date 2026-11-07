begin;
create table recipe_private.pilot_program (
 singleton boolean primary key default true check(singleton),
 started_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null,
 budget_micro bigint not null check(budget_micro between 1 and 490000),
 check(expires_at > started_at and expires_at <= started_at + interval '7 days')
);
create table recipe_private.pilot_testers (
 user_hash text primary key check(user_hash ~ '^[a-f0-9]{64}$'),
 expires_at timestamptz not null,
 enabled boolean not null default true
);
alter table recipe_private.pilot_program enable row level security;
alter table recipe_private.pilot_testers enable row level security;
revoke all on recipe_private.pilot_program,recipe_private.pilot_testers from public,anon,authenticated,service_role;

create function public.recipe_pilot_access(p_user_hash text) returns jsonb
language sql security definer set search_path=pg_catalog,recipe_private as $$
 select jsonb_build_object('code',case when exists(
 select 1 from recipe_private.pilot_testers t, recipe_private.pilot_program p
 where t.user_hash=p_user_hash and t.enabled and t.expires_at>clock_timestamp()
 and p.expires_at>clock_timestamp()) then 'ok' else 'not_enrolled' end)
$$;
revoke all on function public.recipe_pilot_access(text) from public,anon,authenticated;
grant execute on function public.recipe_pilot_access(text) to service_role;

alter function public.recipe_reserve(text,uuid,text,uuid,bigint) rename to recipe_reserve_base;
revoke all on function public.recipe_reserve_base(text,uuid,text,uuid,bigint) from public,anon,authenticated,service_role;
create function public.recipe_reserve(p_session_hash text,p_request_id uuid,p_request_hash text,p_lease uuid,p_required_cost bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
declare p recipe_private.pilot_program; used bigint;
begin
 perform pg_advisory_xact_lock(713406215);
 select * into p from recipe_private.pilot_program where singleton;
 -- An installed pilot program is a cumulative hard guard, regardless of Edge flags.
 if found then
  if p.expires_at<=clock_timestamp() then return jsonb_build_object('code','disabled'); end if;
  if exists(select 1 from recipe_private.jobs where session_hash=p_session_hash and request_id=p_request_id and state='issued') then
   perform recipe_private.recover();
   select coalesce(sum(case when state='running' then reserved_micro else charged_micro end),0) into used from recipe_private.jobs where created_at>=p.started_at;
   if used+(select request_reserve_micro from recipe_private.config where singleton)>p.budget_micro then
    return jsonb_build_object('code','budget_limit');
   end if;
  end if;
 end if;
 return public.recipe_reserve_base(p_session_hash,p_request_id,p_request_hash,p_lease,p_required_cost);
end $$;
revoke all on function public.recipe_reserve(text,uuid,text,uuid,bigint) from public,anon,authenticated;
grant execute on function public.recipe_reserve(text,uuid,text,uuid,bigint) to service_role;
commit;
