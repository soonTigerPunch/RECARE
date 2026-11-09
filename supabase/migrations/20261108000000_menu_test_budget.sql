-- Explicit operator approval: cumulative test limit raised to $1.
-- Preserve all prior pilot spending; hold $0.10 for earlier out-of-program tests.
begin;
drop trigger pilot_start_guard on recipe_private.pilot_program;
alter table recipe_private.pilot_program drop constraint pilot_program_budget_micro_check;
alter table recipe_private.pilot_program add constraint pilot_program_budget_micro_check check(budget_micro between 1 and 900000);
update recipe_private.pilot_program set budget_micro=900000,
 expires_at=least(started_at+interval '7 days',greatest(expires_at,clock_timestamp()+interval '24 hours')) where singleton;
update recipe_private.pilot_testers set expires_at=(select expires_at from recipe_private.pilot_program where singleton) where enabled;
update recipe_private.config set daily_budget_micro=900000,monthly_budget_micro=900000 where singleton;
create trigger pilot_start_guard before insert or update on recipe_private.pilot_program for each row execute function recipe_private.pilot_start_guard();
commit;
