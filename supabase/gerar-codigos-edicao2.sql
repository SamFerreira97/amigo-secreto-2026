-- Run privately as database owner after migration 006. Never publish the output.
-- Existing codes and results are never replaced. First run prepares the unique draw.
begin;
create temporary table edition2_new_codes on commit drop as
 select name,encode(extensions.gen_random_bytes(16),'hex') as codigo_individual from private.edition2_access where code_hash is null;
update private.edition2_access a set code_hash=extensions.digest(c.codigo_individual,'sha256') from edition2_new_codes c where a.name=c.name and a.code_hash is null;
do $$ begin if not (select drawn from public.edition2_event where id=1) then perform private.edition2_draw_once();end if;end $$;
select name,codigo_individual from edition2_new_codes order by name;
commit;
