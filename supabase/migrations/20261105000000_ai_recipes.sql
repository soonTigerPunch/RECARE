begin;
create schema if not exists recipe_private;
revoke all on schema recipe_private from public,anon,authenticated;

create table recipe_private.config (
  singleton boolean primary key default true check(singleton), enabled boolean not null default false,
  daily_budget_micro bigint not null default 0 check(daily_budget_micro>=0),
  monthly_budget_micro bigint not null default 0 check(monthly_budget_micro>=0),
  request_reserve_micro bigint not null default 0 check(request_reserve_micro>=0),
  max_concurrent integer not null default 1 check(max_concurrent between 1 and 100)
);
insert into recipe_private.config(singleton) values(true);
create table recipe_private.jobs (
  session_hash text not null check(session_hash ~ '^[a-f0-9]{64}$'), request_id uuid not null,
  created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null default clock_timestamp()+interval '24 hours',
  state text not null default 'issued' check(state in('issued','running','complete','failed','expired')),
  request_hash text check(request_hash ~ '^[a-f0-9]{64}$'), lease uuid, lease_until timestamptz,
  quota_day date, budget_month date, reserved_micro bigint not null default 0 check(reserved_micro>=0),
  charged_micro bigint not null default 0 check(charged_micro>=0), ciphertext text check(octet_length(ciphertext)<=200000),
  error_code text, model text, prompt_version text,
  primary key(session_hash,request_id)
);
create index recipe_running_lease on recipe_private.jobs(lease_until) where state='running';
create index recipe_result_expiry on recipe_private.jobs(expires_at) where state<>'expired';
create table recipe_private.quotas (
  session_hash text not null, day date not null, used integer not null default 0 check(used>=0),
  reserved integer not null default 0 check(reserved>=0),primary key(session_hash,day)
);
create table recipe_private.budgets (
  kind text not null check(kind in('day','month')), period date not null,
  charged_micro bigint not null default 0 check(charged_micro>=0), reserved_micro bigint not null default 0 check(reserved_micro>=0),
  primary key(kind,period)
);
create table recipe_private.rate_windows (
  scope_hash text not null check(scope_hash ~ '^[a-f0-9]{64}$'), minute timestamptz not null,
  hits integer not null check(hits>0), primary key(scope_hash,minute)
);
alter table recipe_private.config enable row level security;
alter table recipe_private.jobs enable row level security;
alter table recipe_private.quotas enable row level security;
alter table recipe_private.budgets enable row level security;
alter table recipe_private.rate_windows enable row level security;
revoke all on all tables in schema recipe_private from public,anon,authenticated,service_role;

-- All state transitions use the same transaction advisory lock. This intentionally
-- favors simple, auditable reservation semantics over high-volume throughput.
create function recipe_private.recover() returns void language plpgsql set search_path=pg_catalog,recipe_private as $$
declare j recipe_private.jobs; n timestamptz:=clock_timestamp();
begin
  for j in select * from recipe_private.jobs where state='running' and (lease_until<=n or expires_at<=n) for update loop
    update recipe_private.quotas set reserved=reserved-1 where session_hash=j.session_hash and day=j.quota_day;
    update recipe_private.budgets set reserved_micro=reserved_micro-j.reserved_micro,charged_micro=charged_micro+j.reserved_micro
      where (kind='day' and period=j.quota_day) or (kind='month' and period=j.budget_month);
    update recipe_private.jobs set state=case when expires_at<=n then 'expired' else 'failed' end,
      charged_micro=reserved_micro,lease=null,lease_until=null,error_code='timeout',ciphertext=null
      where session_hash=j.session_hash and request_id=j.request_id;
  end loop;
  update recipe_private.jobs set state='expired',ciphertext=null,lease=null,lease_until=null where expires_at<=n and state<>'expired';
end $$;

create function public.recipe_maintenance() returns jsonb language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
begin
  perform pg_advisory_xact_lock(713406215);
  perform recipe_private.recover();
  delete from recipe_private.rate_windows where minute<clock_timestamp()-interval '2 minutes';
  delete from recipe_private.quotas where day<(clock_timestamp() at time zone 'Asia/Seoul')::date-31;
  delete from recipe_private.budgets where period<(clock_timestamp() at time zone 'Asia/Seoul')::date-62;
  -- Retain only immutable, pseudonymous expiry tombstones after 30 days.
  update recipe_private.jobs set request_hash=null,quota_day=null,budget_month=null,reserved_micro=0,charged_micro=0,error_code=null,model=null,prompt_version=null
    where state='expired' and created_at<clock_timestamp()-interval '30 days' and (request_hash is not null or model is not null);
  return jsonb_build_object('code','ok');
end $$;

create function public.recipe_rate_gate(p_scope_hash text,p_limit integer default 60) returns jsonb language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
declare n timestamptz:=date_trunc('minute',clock_timestamp()); count_hits integer;
begin
  if p_scope_hash !~ '^[a-f0-9]{64}$' or p_limit<1 or p_limit>120 then return jsonb_build_object('code','configuration'); end if;
  insert into recipe_private.rate_windows(scope_hash,minute,hits) values(p_scope_hash,n,1)
    on conflict(scope_hash,minute) do update set hits=recipe_private.rate_windows.hits+1 returning hits into count_hits;
  return jsonb_build_object('code',case when count_hits>p_limit then 'rate_limited' else 'ok' end,'retry_at',n+interval '1 minute');
end $$;

create function public.recipe_issue(p_session_hash text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
declare j recipe_private.jobs;
begin
  if p_session_hash !~ '^[a-f0-9]{64}$' then return jsonb_build_object('code','configuration'); end if;
  perform pg_advisory_xact_lock(713406215); perform recipe_private.recover();
  if not (select enabled from recipe_private.config where singleton) then return jsonb_build_object('code','disabled'); end if;
  insert into recipe_private.jobs(session_hash,request_id) values(p_session_hash,p_request_id) on conflict do nothing;
  select * into strict j from recipe_private.jobs where session_hash=p_session_hash and request_id=p_request_id;
  return jsonb_build_object('code',case when j.state='expired' then 'expired' else 'issued' end,'request_id',j.request_id,'expires_at',j.expires_at);
end $$;

create function public.recipe_lookup(p_session_hash text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
declare j recipe_private.jobs;
begin
  perform pg_advisory_xact_lock(713406215); perform recipe_private.recover();
  select * into j from recipe_private.jobs where session_hash=p_session_hash and request_id=p_request_id;
  if not found then return jsonb_build_object('code','not_found'); end if;
  return jsonb_build_object('code',case j.state when 'running' then 'in_progress' when 'failed' then coalesce(j.error_code,'unavailable') else j.state end,
    'ciphertext',j.ciphertext,'expires_at',j.expires_at,'retry_at',j.lease_until);
end $$;

create function public.recipe_reserve(p_session_hash text,p_request_id uuid,p_request_hash text,p_lease uuid,p_required_cost bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
declare j recipe_private.jobs; cfg recipe_private.config; q recipe_private.quotas; day_budget recipe_private.budgets; month_budget recipe_private.budgets;
  d date:=(clock_timestamp() at time zone 'Asia/Seoul')::date; m date:=date_trunc('month',clock_timestamp() at time zone 'Asia/Seoul')::date;
begin
  if p_session_hash !~ '^[a-f0-9]{64}$' or p_request_hash !~ '^[a-f0-9]{64}$' or p_required_cost<1 then return jsonb_build_object('code','configuration'); end if;
  perform pg_advisory_xact_lock(713406215); perform recipe_private.recover();
  select * into j from recipe_private.jobs where session_hash=p_session_hash and request_id=p_request_id for update;
  if not found then return jsonb_build_object('code','not_found'); end if;
  if j.state='expired' then return jsonb_build_object('code','expired'); end if;
  if j.request_hash is not null and j.request_hash<>p_request_hash then return jsonb_build_object('code','conflict'); end if;
  if j.state<>'issued' then return public.recipe_lookup(p_session_hash,p_request_id); end if;
  select * into strict cfg from recipe_private.config where singleton;
  if not cfg.enabled then return jsonb_build_object('code','disabled'); end if;
  if cfg.request_reserve_micro<p_required_cost or cfg.daily_budget_micro<cfg.request_reserve_micro or cfg.monthly_budget_micro<cfg.request_reserve_micro then return jsonb_build_object('code','configuration'); end if;
  insert into recipe_private.quotas(session_hash,day) values(p_session_hash,d) on conflict do nothing;
  select * into strict q from recipe_private.quotas where session_hash=p_session_hash and day=d;
  if q.used+q.reserved>=5 then return jsonb_build_object('code','daily_limit','retry_at',(d+1)::timestamp at time zone 'Asia/Seoul'); end if;
  if exists(select 1 from recipe_private.jobs where session_hash=p_session_hash and state='running') then return jsonb_build_object('code','in_progress'); end if;
  if (select count(*) from recipe_private.jobs where state='running')>=cfg.max_concurrent then return jsonb_build_object('code','rate_limited'); end if;
  insert into recipe_private.budgets(kind,period) values('day',d),('month',m) on conflict do nothing;
  select * into strict day_budget from recipe_private.budgets where kind='day' and period=d;
  select * into strict month_budget from recipe_private.budgets where kind='month' and period=m;
  if day_budget.charged_micro+day_budget.reserved_micro+cfg.request_reserve_micro>cfg.daily_budget_micro or month_budget.charged_micro+month_budget.reserved_micro+cfg.request_reserve_micro>cfg.monthly_budget_micro then return jsonb_build_object('code','budget_limit'); end if;
  update recipe_private.quotas set reserved=reserved+1 where session_hash=p_session_hash and day=d;
  update recipe_private.budgets set reserved_micro=reserved_micro+cfg.request_reserve_micro where (kind='day' and period=d) or (kind='month' and period=m);
  update recipe_private.jobs set state='running',request_hash=p_request_hash,lease=p_lease,lease_until=clock_timestamp()+interval '35 seconds',quota_day=d,budget_month=m,reserved_micro=cfg.request_reserve_micro,prompt_version='recare_recipe_v1' where session_hash=p_session_hash and request_id=p_request_id;
  return jsonb_build_object('code','reserved','reserved_micro',cfg.request_reserve_micro,'expires_at',j.expires_at);
end $$;

create function public.recipe_finish(p_session_hash text,p_request_id uuid,p_lease uuid,p_success boolean,p_ciphertext text,p_cost_micro bigint,p_error_code text,p_model text) returns jsonb language plpgsql security definer set search_path=pg_catalog,recipe_private as $$
declare j recipe_private.jobs; charge bigint;
begin
  perform pg_advisory_xact_lock(713406215); perform recipe_private.recover();
  select * into j from recipe_private.jobs where session_hash=p_session_hash and request_id=p_request_id for update;
  if not found then return jsonb_build_object('code','not_found'); end if;
  if j.state<>'running' then return public.recipe_lookup(p_session_hash,p_request_id); end if;
  if j.lease<>p_lease then return jsonb_build_object('code','conflict'); end if;
  if p_ciphertext is null or octet_length(p_ciphertext)>200000 or (p_cost_micro is not null and (p_cost_micro<0 or p_cost_micro>j.reserved_micro)) then return jsonb_build_object('code','configuration'); end if;
  if not p_success and p_error_code not in('timeout','unavailable','configuration','rate_limited','invalid_output') then return jsonb_build_object('code','configuration'); end if;
  charge:=coalesce(p_cost_micro,j.reserved_micro);
  update recipe_private.quotas set reserved=reserved-1,used=used+case when p_success then 1 else 0 end where session_hash=p_session_hash and day=j.quota_day;
  update recipe_private.budgets set reserved_micro=reserved_micro-j.reserved_micro,charged_micro=charged_micro+charge where (kind='day' and period=j.quota_day) or (kind='month' and period=j.budget_month);
  update recipe_private.jobs set state=case when p_success then 'complete' else 'failed' end,ciphertext=p_ciphertext,error_code=p_error_code,charged_micro=charge,lease=null,lease_until=null,model=left(p_model,100) where session_hash=p_session_hash and request_id=p_request_id;
  return jsonb_build_object('code',case when p_success then 'complete' else p_error_code end,'ciphertext',p_ciphertext,'expires_at',j.expires_at);
end $$;

revoke all on all functions in schema recipe_private from public,anon,authenticated,service_role;
revoke all on function public.recipe_maintenance(),public.recipe_rate_gate(text,integer),public.recipe_issue(text,uuid),public.recipe_lookup(text,uuid),public.recipe_reserve(text,uuid,text,uuid,bigint),public.recipe_finish(text,uuid,uuid,boolean,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.recipe_maintenance(),public.recipe_rate_gate(text,integer),public.recipe_issue(text,uuid),public.recipe_lookup(text,uuid),public.recipe_reserve(text,uuid,text,uuid,bigint),public.recipe_finish(text,uuid,uuid,boolean,text,bigint,text,text) to service_role;
-- pg_cron is optional locally. Supabase projects must install/enable it or arrange
-- an equivalent service-only scheduler before activation; retention is mandatory.
do $outer$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    execute $cron$select cron.schedule('recare-recipe-retention','* * * * *','select public.recipe_maintenance()')$cron$;
  end if;
end $outer$;
commit;
