-- Additive migration: preserves all codes, photos, wishes, sessions and pairings.
begin;
alter table public.event add column message text not null default '' check(length(message)<=500);
alter table public.participation_status add column wishes_filled boolean not null default false;
create table public.participant_directory(
 id uuid primary key default gen_random_uuid(),
 name text not null unique references public.participants(name),
 photo text not null check(length(photo)<=400000),
 photo_updated boolean not null default false,
 updated_at timestamptz not null default now()
);
insert into public.participant_directory(name,photo) select name,'participants/'||lower(name)||'.png' from public.participants;
alter table public.participant_directory enable row level security;
revoke all on public.participant_directory from public,anon,authenticated;
grant select on public.participant_directory to anon,authenticated;
create policy public_photos on public.participant_directory for select using(true);

alter table private.code_wishes add column sizes text not null default '' check(length(sizes)<=500);
alter table private.code_wishes add column notes text not null default '' check(length(notes)<=500);
alter table private.profile_access add column failed_attempts int not null default 0;
alter table private.profile_access add column blocked_until timestamptz;
create table private.code_sessions(
 token_hash bytea primary key,
 name text not null references public.participants(name),
 expires_at timestamptz not null,
 created_at timestamptz not null default now()
);
create index code_sessions_name on private.code_sessions(name);
insert into private.code_sessions(token_hash,name,expires_at)
 select session_hash,name,session_expires_at from private.profile_access where session_hash is not null and session_expires_at>now();
create table private.admin_audit(
 id bigint generated always as identity primary key,
 actor text not null,action text not null,target text,reason text,
 created_at timestamptz not null default now()
);
alter table private.code_sessions enable row level security;
alter table private.admin_audit enable row level security;
revoke all on private.code_sessions,private.admin_audit from public,anon,authenticated;

create or replace function private.session_name(access_token text) returns text language plpgsql security definer set search_path='' as $$
declare who text;
begin
 if access_token is null or access_token !~ '^[0-9a-f]{64}$' then raise exception 'Acesso inválido.';end if;
 select name into who from private.code_sessions where token_hash=extensions.digest(access_token,'sha256') and expires_at>now() for share;
 if who is null then raise exception 'Acesso inválido ou expirado. Confirme seu PIN novamente.';end if;
 return who;
end $$;

create or replace function public.open_profile(participant_name text,secret_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.profile_access;token text;
begin
 select * into a from private.profile_access where name=participant_name for update;
 if a.name is null then return jsonb_build_object('error','PIN inválido. Confira seu código individual.');end if;
 if a.blocked_until>now() then
  return jsonb_build_object('error','Muitas tentativas. Aguarde 15 minutos antes de tentar novamente.','retry_after',ceil(extract(epoch from a.blocked_until-now())));
 end if;
 if secret_code is null or secret_code !~ '^[0-9a-f]{32}$' or a.code_hash<>extensions.digest(secret_code,'sha256') then
  if a.blocked_until is not null then a.failed_attempts:=0;end if;
  update private.profile_access set failed_attempts=a.failed_attempts+1,
   blocked_until=case when a.failed_attempts+1>=5 then now()+interval '15 minutes' else null end where name=a.name;
  -- Return an error object, not an exception: the rate limit must COMMIT.
  return jsonb_build_object('error',case when a.failed_attempts+1>=5 then 'Muitas tentativas. Aguarde 15 minutos antes de tentar novamente.' else 'PIN inválido. Confira seu código individual.' end,'retry_after',case when a.failed_attempts+1>=5 then 900 else 0 end);
 end if;
 update private.profile_access set failed_attempts=0,blocked_until=null where name=a.name;
 delete from private.code_sessions where name=a.name and expires_at<=now();
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into private.code_sessions(token_hash,name,expires_at) values(extensions.digest(token,'sha256'),a.name,now()+interval '90 days');
 return jsonb_build_object('name',a.name,'token',token);
end $$;

create or replace function public.profile_state(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;answer jsonb;used boolean;
begin
 who:=private.session_name(access_token);
 select revealed_at is not null into used from public.participation_status where name=who;
 if used then
 select jsonb_build_object('name',a.recipient,'wish',coalesce(to_jsonb(w)-'name','{}'::jsonb)) into answer from private.code_assignments a left join private.code_wishes w on w.name=a.recipient where a.giver=who;
 end if;
 return jsonb_build_object('name',who,'id',(select id from public.participant_directory where name=who),'is_admin',who='Samuel','drawn',(select drawn from public.event where id=1),'revealed',used,'result',answer,'wish',coalesce((select to_jsonb(w)-'name' from private.code_wishes w where name=who),'{}'::jsonb));
end $$;

create function public.initialize_code_draw(access_token text) returns void language plpgsql security definer set search_path='' as $$
declare who text;ids text[];perm text[];i int;j int;tmp text;good boolean;n bigint;bound bigint;bytes bytea;
begin
 -- All draw/reveal operations acquire the event lock before reading sessions.
 perform 1 from public.event where id=1 for update;
 who:=private.session_name(access_token);
 if who<>'Samuel' then raise exception 'Somente o administrador pode inicializar o sorteio.';end if;
 if (select drawn from public.event where id=1) then raise exception 'O sorteio já foi inicializado e não pode ser refeito.';end if;
 if exists(select 1 from private.code_assignments) then raise exception 'Rodada inconsistente. Contate o administrador do banco.';end if;
 select array_agg(name order by name) into ids from public.participants;
 if cardinality(ids)<>5 or (select count(*) from private.profile_access)<>5 then raise exception 'Os cinco perfis precisam estar configurados.';end if;
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
 insert into private.admin_audit(actor,action) values(who,'initialize_draw');
end $$;

create or replace function public.reveal_secret(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;answer jsonb;
begin
 perform 1 from public.event where id=1 for update;
 who:=private.session_name(access_token);
 if exists(select 1 from public.participation_status where name=who and revealed_at is not null) then raise exception 'Este perfil já participou. Consulte o resultado pelo Meu Perfil.';end if;
 if not (select drawn from public.event where id=1) then raise exception 'O administrador ainda não inicializou o sorteio. Sua lista de desejos já pode ser preenchida.';end if;
 if (select count(*) from private.code_assignments)<>5 then raise exception 'Rodada inconsistente. Contate o administrador.';end if;
 update public.participation_status set revealed_at=now() where name=who;
 select jsonb_build_object('name',a.recipient,'wish',coalesce(to_jsonb(w)-'name','{}'::jsonb)) into answer from private.code_assignments a left join private.code_wishes w on w.name=a.recipient where a.giver=who;
 return answer;
end $$;

-- Replace legacy signatures, avoiding ambiguous PostgREST overloads.
drop function public.save_profile_wishes(text,text[],text,text,text);
create function public.save_profile_wishes(access_token text,suggestions text[],preferences text,colors text,avoid text,sizes text,notes text) returns void language plpgsql security definer set search_path='' as $$
declare who text;filled boolean;
begin
 who:=private.session_name(access_token);
 insert into private.code_wishes(name,suggestions,preferences,colors,avoid,sizes,notes) values(who,suggestions,preferences,colors,avoid,sizes,notes)
 on conflict(name) do update set suggestions=excluded.suggestions,preferences=excluded.preferences,colors=excluded.colors,avoid=excluded.avoid,sizes=excluded.sizes,notes=excluded.notes;
 filled:=length(btrim(array_to_string(suggestions,'')||preferences||colors||avoid||sizes||notes))>0;
 update public.participation_status set wishes_filled=filled where name=who;
end $$;
update public.participation_status s set wishes_filled=length(btrim(array_to_string(w.suggestions,'')||w.preferences||w.colors||w.avoid||w.sizes||w.notes))>0 from private.code_wishes w where s.name=w.name;

drop function public.save_code_event(text,timestamptz,text,numeric,numeric);
create function public.save_code_event(access_token text,exchange_at timestamptz,location text,min_value numeric,max_value numeric,message text) returns void language plpgsql security definer set search_path='' as $$
declare who text;
begin
 perform 1 from public.event where id=1 for update;
 who:=private.session_name(access_token);
 if who<>'Samuel' then raise exception 'Somente o administrador pode alterar o encontro.';end if;
 update public.event set exchange_at=save_code_event.exchange_at,location=save_code_event.location,min_value=save_code_event.min_value,max_value=save_code_event.max_value,message=save_code_event.message where id=1;
 insert into private.admin_audit(actor,action) values(who,'update_event');
end $$;

create function public.admin_dashboard(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if private.session_name(access_token)<>'Samuel' then raise exception 'Área exclusiva do administrador.';end if;
 return jsonb_build_object(
 'participants',(select jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'revealed_at',s.revealed_at,'wishes_filled',s.wishes_filled) order by d.name) from public.participant_directory d join public.participation_status s using(name)),
 'drawn',(select drawn from public.event where id=1),
 'assignment_count',(select count(*) from private.code_assignments),
 'audit',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select action,target,reason,created_at from private.admin_audit order by id desc limit 20)x));
end $$;

create function public.save_participant_photo(access_token text,participant_id uuid,photo_data text) returns void language plpgsql security definer set search_path='' as $$
declare who text;target_name text;
begin
 who:=private.session_name(access_token);
 if who<>'Samuel' then raise exception 'Somente o administrador pode alterar fotografias.';end if;
 if photo_data is null or length(photo_data)>400000 or photo_data !~ '^data:image/webp;base64,[A-Za-z0-9+/]+=*$' or substring(decode(substring(photo_data from 24),'base64') from 1 for 4)<>decode('52494646','hex') or substring(decode(substring(photo_data from 24),'base64') from 9 for 4)<>decode('57454250','hex') then raise exception 'Envie uma fotografia WebP válida de até 300 KB.';end if;
 update public.participant_directory set photo=photo_data,photo_updated=true,updated_at=now() where id=participant_id returning name into target_name;
 if target_name is null then raise exception 'Participante não encontrado.';end if;
 insert into private.admin_audit(actor,action,target) values(who,'update_photo',target_name);
end $$;

create function public.recover_participant_code(access_token text,participant_id uuid,recovery_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;target_name text;code text;
begin
 who:=private.session_name(access_token);
 if who<>'Samuel' then raise exception 'Somente o administrador pode recuperar acessos.';end if;
 if recovery_reason is null or length(btrim(recovery_reason))<10 or length(recovery_reason)>500 then raise exception 'Registre como confirmou a identidade da pessoa (10 a 500 caracteres).';end if;
 select name into target_name from public.participant_directory where id=participant_id;
 if target_name is null then raise exception 'Participante não encontrado.';end if;
 if target_name=who then raise exception 'O acesso do administrador deve ser recuperado pelo proprietário no SQL Editor privado.';end if;
 perform 1 from private.profile_access where name=target_name for update;
 code:=encode(extensions.gen_random_bytes(16),'hex');
 update private.profile_access set code_hash=extensions.digest(code,'sha256'),failed_attempts=0,blocked_until=null,session_hash=null,session_expires_at=null where name=target_name;
 delete from private.code_sessions where name=target_name;
 insert into private.admin_audit(actor,action,target,reason) values(who,'recover_access',target_name,btrim(recovery_reason));
 return jsonb_build_object('name',target_name,'code',code);
end $$;

create function public.close_profile(access_token text) returns void language plpgsql security definer set search_path='' as $$
begin delete from private.code_sessions where token_hash=extensions.digest(access_token,'sha256');end $$;

revoke all on function public.initialize_code_draw(text),public.save_profile_wishes(text,text[],text,text,text,text,text),public.save_code_event(text,timestamptz,text,numeric,numeric,text),public.admin_dashboard(text),public.save_participant_photo(text,uuid,text),public.recover_participant_code(text,uuid,text),public.close_profile(text) from public;
grant execute on function public.initialize_code_draw(text),public.save_profile_wishes(text,text[],text,text,text,text,text),public.save_code_event(text,timestamptz,text,numeric,numeric,text),public.admin_dashboard(text),public.save_participant_photo(text,uuid,text),public.recover_participant_code(text,uuid,text),public.close_profile(text) to anon,authenticated;
revoke all on function private.session_name(text) from public,anon,authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then alter publication supabase_realtime add table public.participant_directory,public.event;end if;
end $$;
commit;
