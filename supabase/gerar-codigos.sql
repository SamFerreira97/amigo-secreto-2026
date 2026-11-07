-- Run privately in the Supabase SQL editor as the database owner, once.
-- Copy each returned code to its participant privately. Never publish this result.
-- Existing codes, sessions, draw results and participation statuses are preserved.
with generated as materialized (
 select name,encode(extensions.gen_random_bytes(16),'hex') as codigo_individual
 from public.participants p where not exists(select 1 from private.profile_access a where a.name=p.name)
), inserted as (
 insert into private.profile_access(name,code_hash)
 select name,extensions.digest(codigo_individual,'sha256') from generated returning name
)
select g.name,g.codigo_individual from generated g join inserted i using(name) order by name;
