-- Email-free access. All secrets and pairings stay in the private schema.
begin;
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create table if not exists public.participation_status(
 name text primary key references public.participants(name), revealed_at timestamptz
);
insert into public.participation_status(name) select name from public.participants on conflict do nothing;
alter table public.participation_status enable row level security;
revoke all on public.participation_status from public,anon,authenticated;
grant select on public.participation_status to anon,authenticated;
create policy public_availability on public.participation_status for select using(true);
create table private.profile_access(
 name text primary key references public.participants(name),
 code_hash bytea not null unique, session_hash bytea unique, session_expires_at timestamptz
);
create table private.code_assignments(
 giver text primary key references public.participants(name),
 recipient text not null unique references public.participants(name),check(giver<>recipient)
);
create table private.code_wishes(
 name text primary key references public.participants(name),
 suggestions text[] not null default array['','','']::text[] check(cardinality(suggestions)<=3 and length(array_to_string(suggestions,''))<=600),
 preferences text not null default '' check(length(preferences)<=500),
 colors text not null default '' check(length(colors)<=500),
 avoid text not null default '' check(length(avoid)<=500)
);
alter table private.profile_access enable row level security;
alter table private.code_assignments enable row level security;
alter table private.code_wishes enable row level security;
revoke all on private.profile_access,private.code_assignments,private.code_wishes from public,anon,authenticated;
-- Preserve any existing draw and wishes; never generate a second mapping.
insert into private.code_assignments select g.name,r.name from public.assignments a join public.participants g on g.user_id=a.giver join public.participants r on r.user_id=a.recipient;
insert into private.code_wishes select p.name,w.suggestions,w.preferences,w.colors,w.avoid from public.wishes w join public.participants p on p.user_id=w.user_id;
revoke execute on function public.draw_once(),public.my_result(),public.claim_profile(text),public.create_participant_invite(text) from public,anon,authenticated;

create function private.session_name(access_token text) returns text language plpgsql security definer set search_path='' as $$
declare who text;
begin
 if access_token is null or access_token !~ '^[0-9a-f]{64}$' then raise exception 'Acesso inválido.';end if;
 select name into who from private.profile_access where session_hash=extensions.digest(access_token,'sha256') and session_expires_at>now() for update;
 if who is null then raise exception 'Acesso inválido ou expirado.';end if;
 return who;
end $$;
revoke all on function private.session_name(text) from public,anon,authenticated;

create function public.open_profile(participant_name text,secret_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare token text;who text;
begin
 if secret_code is null or secret_code !~ '^[0-9a-f]{32}$' then raise exception 'Código inválido ou perfil indisponível.';end if;
 select a.name into who from private.profile_access a join public.participation_status s using(name)
 where a.name=participant_name and a.code_hash=extensions.digest(secret_code,'sha256') and s.revealed_at is null for update of a,s;
 if who is null then raise exception 'Código inválido ou perfil indisponível.';end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 update private.profile_access set session_hash=extensions.digest(token,'sha256'),session_expires_at=now()+interval '90 days' where name=who;
 return jsonb_build_object('name',who,'token',token);
end $$;

create function public.profile_state(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;answer jsonb;used boolean;
begin
 who:=private.session_name(access_token);
 select revealed_at is not null into used from public.participation_status where name=who;
 if used then
 select jsonb_build_object('name',a.recipient,'wish',coalesce(to_jsonb(w)-'name','{}'::jsonb)) into answer from private.code_assignments a left join private.code_wishes w on w.name=a.recipient where a.giver=who;
 end if;
 return jsonb_build_object('name',who,'revealed',used,'result',answer,'wish',coalesce((select to_jsonb(w)-'name' from private.code_wishes w where name=who),'{}'::jsonb));
end $$;

create function public.reveal_secret(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;ids text[];perm text[];i int;j int;tmp text;good boolean;n bigint;bound bigint;bytes bytea;answer jsonb;
begin
 -- Every reveal and the initial draw serialize on the same durable row.
 perform 1 from public.event where id=1 for update;
 who:=private.session_name(access_token);
 if exists(select 1 from public.participation_status where name=who and revealed_at is not null) then raise exception 'Este perfil já participou.';end if;
 if not (select drawn from public.event where id=1) then
  if exists(select 1 from private.code_assignments) then raise exception 'Sorteio inconsistente. Contate o organizador.';end if;
  select array_agg(name order by name) into ids from public.participants;
  if cardinality(ids)<>5 then raise exception 'O grupo deve ter cinco participantes.';end if;
  loop
   perm:=ids;
   for i in reverse 5..2 loop
    bound:=4294967296-(4294967296 % i);
    loop
     bytes:=extensions.gen_random_bytes(4);
     n:=get_byte(bytes,0)::bigint*16777216+get_byte(bytes,1)::bigint*65536+get_byte(bytes,2)::bigint*256+get_byte(bytes,3);
     exit when n<bound;
    end loop;
    j:=(n%i)::int+1;tmp:=perm[i];perm[i]:=perm[j];perm[j]:=tmp;
   end loop;
   good:=true;
   for i in 1..5 loop if ids[i]=perm[i] then good:=false;exit;end if;end loop;
   exit when good;
  end loop;
  for i in 1..5 loop insert into private.code_assignments values(ids[i],perm[i]);end loop;
  update public.event set drawn=true where id=1;
 end if;
 if (select count(*) from private.code_assignments)<>5 then raise exception 'Sorteio incompleto. Contate o organizador.';end if;
 update public.participation_status set revealed_at=now() where name=who;
 select jsonb_build_object('name',a.recipient,'wish',coalesce(to_jsonb(w)-'name','{}'::jsonb)) into answer from private.code_assignments a left join private.code_wishes w on w.name=a.recipient where a.giver=who;
 return answer;
end $$;

create function public.save_profile_wishes(access_token text,suggestions text[],preferences text,colors text,avoid text) returns void language plpgsql security definer set search_path='' as $$
declare who text;
begin
 who:=private.session_name(access_token);
 insert into private.code_wishes values(who,suggestions,preferences,colors,avoid)
 on conflict(name) do update set suggestions=excluded.suggestions,preferences=excluded.preferences,colors=excluded.colors,avoid=excluded.avoid;
end $$;

create function public.save_code_event(access_token text,exchange_at timestamptz,location text,min_value numeric,max_value numeric) returns void language plpgsql security definer set search_path='' as $$
begin
 if private.session_name(access_token)<>'Samuel' then raise exception 'Somente o organizador pode alterar o encontro.';end if;
 update public.event set exchange_at=save_code_event.exchange_at,location=save_code_event.location,min_value=save_code_event.min_value,max_value=save_code_event.max_value where id=1;
end $$;
revoke all on function public.save_code_event(text,timestamptz,text,numeric,numeric) from public;
grant execute on function public.save_code_event(text,timestamptz,text,numeric,numeric) to anon,authenticated;

revoke all on function public.open_profile(text,text),public.profile_state(text),public.reveal_secret(text),public.save_profile_wishes(text,text[],text,text,text) from public;
grant execute on function public.open_profile(text,text),public.profile_state(text),public.reveal_secret(text),public.save_profile_wishes(text,text[],text,text,text) to anon,authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='participation_status') then
  alter publication supabase_realtime add table public.participation_status;
 end if;
end $$;
commit;
