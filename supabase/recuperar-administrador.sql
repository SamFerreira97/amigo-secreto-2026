-- Emergency recovery ONLY in the owner's private Supabase SQL Editor.
-- This rotates Samuel's PIN, revokes his sessions and records the action.
-- It does not change draw results, wishes, IDs or participation status.
-- Do not run as part of normal deployment. Keep the returned PIN private.
begin;
with generated as materialized(select encode(extensions.gen_random_bytes(16),'hex') as code),
changed as (
 update private.profile_access a set code_hash=extensions.digest(g.code,'sha256'),failed_attempts=0,blocked_until=null,session_hash=null,session_expires_at=null
 from generated g where a.name='Samuel' returning g.code
), revoked as (delete from private.code_sessions where name='Samuel' returning name),
audited as (
 insert into private.admin_audit(actor,action,target,reason)
 select 'database_owner','recover_access','Samuel','Recuperação excepcional pelo proprietário no SQL Editor privado' where exists(select 1 from changed) returning id
)
select code as novo_pin_privado_de_samuel from changed where exists(select 1 from audited);
commit;
