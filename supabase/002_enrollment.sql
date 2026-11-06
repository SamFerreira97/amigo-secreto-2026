-- Run after schema.sql. No draw is performed and no assignments are changed.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table private.enrollment_invites (
  participant_name text primary key references public.participants(name),
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  claimed_by uuid unique references auth.users(id),
  claimed_at timestamptz
);
alter table private.enrollment_invites enable row level security;
revoke all on private.enrollment_invites from public,anon,authenticated;

create function public.claim_profile(invitation_code text) returns text
language plpgsql security definer set search_path='' as $$
declare caller uuid:=auth.uid(); code text; invite private.enrollment_invites%rowtype; bound_name text; target_user uuid;
begin
  if caller is null or not exists(select 1 from auth.users where id=caller and email_confirmed_at is not null) then
    raise exception 'Confirme o e-mail pelo link de acesso antes de usar o convite.';
  end if;
  select name into bound_name from public.participants where user_id=caller;
  if bound_name is not null then return bound_name;end if;
  code:=lower(regexp_replace(coalesce(invitation_code,''),'\s','','g'));
  if code !~ '^[0-9a-f]{32}$' then raise exception 'Convite inválido ou expirado.';end if;
  select * into invite from private.enrollment_invites
    where token_hash=extensions.digest(code,'sha256') for update;
  if not found or invite.expires_at<=now() or invite.claimed_by is not null then
    raise exception 'Convite inválido ou expirado.';
  end if;
  select user_id into target_user from public.participants where name=invite.participant_name for update;
  if target_user is not null then raise exception 'Este perfil já tem uma conta vinculada.';end if;
  update public.participants set user_id=caller where name=invite.participant_name and user_id is null;
  update private.enrollment_invites set claimed_by=caller,claimed_at=now()
    where participant_name=invite.participant_name;
  return invite.participant_name;
exception when unique_violation then
  raise exception 'Esta conta já está vinculada a um perfil.';
end $$;

create function public.create_participant_invite(participant_name text) returns text
language plpgsql security definer set search_path='' as $$
declare code text; target_user uuid;
begin
  if not exists(select 1 from public.participants where user_id=auth.uid() and is_admin) then
    raise exception 'Somente o organizador pode gerar convites.';
  end if;
  select p.user_id into target_user from public.participants p where p.name=participant_name for update;
  if not found then raise exception 'Participante inexistente.';end if;
  if target_user is not null then raise exception 'Este perfil já tem uma conta vinculada.';end if;
  code:=encode(extensions.gen_random_bytes(16),'hex');
  insert into private.enrollment_invites(participant_name,token_hash,expires_at)
    values(participant_name,extensions.digest(code,'sha256'),now()+interval '30 days')
  on conflict on constraint enrollment_invites_pkey do update
    set token_hash=excluded.token_hash,expires_at=excluded.expires_at
    where private.enrollment_invites.claimed_by is null;
  if not found then raise exception 'Este convite já foi utilizado.';end if;
  return code;
end $$;
revoke all on function public.claim_profile(text),public.create_participant_invite(text) from public,anon;
grant execute on function public.claim_profile(text),public.create_participant_invite(text) to authenticated;
commit;
