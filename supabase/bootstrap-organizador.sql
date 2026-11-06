-- Owner-only SQL console operation, once before first enrollment.
-- Output is a private one-time invite for Samuel. Never commit/share it publicly.
begin;
update public.participants set is_admin=true where name='Samuel';
with code as (select encode(extensions.gen_random_bytes(16),'hex') as token),
saved as (
  insert into private.enrollment_invites(participant_name,token_hash,expires_at)
  select 'Samuel',extensions.digest(code.token,'sha256'),now()+interval '30 days' from code
    where exists(select 1 from public.participants where name='Samuel' and user_id is null)
  on conflict(participant_name) do update
    set token_hash=excluded.token_hash,expires_at=excluded.expires_at
    where private.enrollment_invites.claimed_by is null
  returning participant_name
)
select code.token as convite_privado_de_samuel from code where exists(select 1 from saved);
commit;
