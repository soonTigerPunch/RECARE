begin;
create or replace function public.recipe_reserve(p_session_hash text,p_request_id uuid,p_request_hash text,p_lease uuid,p_required_cost bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
declare p recipe_private.pilot_program; used bigint;
begin
 perform pg_advisory_xact_lock(713406215);
 select * into p from recipe_private.pilot_program where singleton;
 -- An installed pilot program is a cumulative hard guard, regardless of Edge flags.
 if found then
  if p.expires_at<=clock_timestamp() then return jsonb_build_object('code','disabled'); end if;
  if exists(select 1 from recipe_private.jobs where session_hash=p_session_hash and request_id=p_request_id and created_at<p.started_at) then
   return jsonb_build_object('code','expired');
  end if;
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

create function recipe_private.pilot_start_guard() returns trigger language plpgsql set search_path=pg_catalog,recipe_private as $$
begin
 perform pg_advisory_xact_lock(713406215);
 if exists(select 1 from recipe_private.jobs where state='running') then raise exception 'Stop and settle running jobs before starting a pilot'; end if;
 if TG_OP='UPDATE' and (new.started_at<>old.started_at or new.expires_at>old.expires_at or new.budget_micro>old.budget_micro) then raise exception 'Pilot lifetime and budget cannot be extended'; end if;
 return new;
end $$;
create trigger pilot_start_guard before insert or update on recipe_private.pilot_program for each row execute function recipe_private.pilot_start_guard();
revoke all on function recipe_private.pilot_start_guard() from public,anon,authenticated,service_role;
commit;
