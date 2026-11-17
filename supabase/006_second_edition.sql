-- Independent second edition. No legacy table or function is changed.
begin isolation level repeatable read;
create temporary table edition1_guard on commit drop as select md5(jsonb_build_object(
 'participants',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participants x),
 'event',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.event x),
 'photos',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participant_directory x),
 'status',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participation_status x),
 'assignments',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_assignments x),
 'wishes',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_wishes x),
 'pins',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.profile_access x),
 'sessions',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_sessions x),
 'audit',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.admin_audit x),
 'legacy_assignments',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.assignments x),
 'legacy_wishes',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.wishes x),
 'legacy_invites',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.enrollment_invites x)
 )::text) as digest;
create table public.edition2_participant_directory(
 id uuid primary key default gen_random_uuid(),
 name text not null unique check(name in ('Samuel','Gabi','Carol','Nanda','Isa','Douglas')),
 photo text not null check(length(photo)<=400000),photo_updated boolean not null default false,updated_at timestamptz not null default now()
);
-- Copy Samuel/Gabi's current photographs, never their wishes, sessions or results.
insert into public.edition2_participant_directory(name,photo,photo_updated) select name,photo,photo_updated from public.participant_directory where name in ('Samuel','Gabi');
insert into public.edition2_participant_directory(name,photo) values('Carol','participants/carol.png'),('Nanda','participants/nanda.png'),('Isa','participants/isa.png'),('Douglas','participants/douglas.png');
create table public.edition2_event(id int primary key check(id=1),exchange_at timestamptz,location text not null default 'A combinar com a turma' check(length(location)<=200),min_value numeric check(min_value>=0),max_value numeric check(max_value>=0 and max_value>=min_value),message text not null default '' check(length(message)<=500),drawn boolean not null default false);
insert into public.edition2_event(id) values(1);
create table public.edition2_participation_status(name text primary key references public.edition2_participant_directory(name),revealed_at timestamptz,wishes_filled boolean not null default false);
insert into public.edition2_participation_status(name) select name from public.edition2_participant_directory;
create table private.edition2_access(name text primary key references public.edition2_participant_directory(name),code_hash bytea unique,failed_attempts int not null default 0,blocked_until timestamptz,session_hash bytea,session_expires_at timestamptz);
insert into private.edition2_access(name) select name from public.edition2_participant_directory;
create table private.edition2_sessions(token_hash bytea primary key,name text not null references public.edition2_participant_directory(name),expires_at timestamptz not null,created_at timestamptz not null default now());
create index edition2_sessions_name on private.edition2_sessions(name);
create table private.edition2_assignments(giver text primary key references public.edition2_participant_directory(name),recipient text not null unique references public.edition2_participant_directory(name),check(giver<>recipient));
create table private.edition2_audit(id bigint generated always as identity primary key,actor text not null,action text not null,target text,reason text,created_at timestamptz not null default now());
create function private.edition2_valid_wish_links(items text[]) returns boolean language sql immutable set search_path='' as $$
 select items is not null and coalesce(cardinality(items)<=3,false)
 and not exists(select 1 from unnest(items) v where v is null or length(v)>2048 or (v<>'' and v !~* '^https?://[^[:space:]<>]+$'))
$$;
create table private.edition2_wishes(name text primary key references public.edition2_participant_directory(name),suggestions text[] not null default array['','','']::text[] check(cardinality(suggestions)<=3 and length(array_to_string(suggestions,''))<=600),preferences text not null default '' check(length(preferences)<=500),colors text not null default '' check(length(colors)<=500),avoid text not null default '' check(length(avoid)<=500),sizes text not null default '' check(length(sizes)<=500),notes text not null default '' check(length(notes)<=500),links text[] not null default array['','','']::text[] check(private.edition2_valid_wish_links(links)));
alter table public.edition2_participant_directory enable row level security;
revoke all on public.edition2_participant_directory from public,anon,authenticated;
grant select on public.edition2_participant_directory to anon,authenticated;
create policy edition2_public_read on public.edition2_participant_directory for select using(true);
alter table public.edition2_participation_status enable row level security;
revoke all on public.edition2_participation_status from public,anon,authenticated;
grant select on public.edition2_participation_status to anon,authenticated;
create policy edition2_public_read on public.edition2_participation_status for select using(true);
alter table public.edition2_event enable row level security;
revoke all on public.edition2_event from public,anon,authenticated;
grant select on public.edition2_event to anon,authenticated;
create policy edition2_public_read on public.edition2_event for select using(true);
alter table private.edition2_access enable row level security;
revoke all on private.edition2_access from public,anon,authenticated;
alter table private.edition2_sessions enable row level security;
revoke all on private.edition2_sessions from public,anon,authenticated;
alter table private.edition2_assignments enable row level security;
revoke all on private.edition2_assignments from public,anon,authenticated;
alter table private.edition2_wishes enable row level security;
revoke all on private.edition2_wishes from public,anon,authenticated;
alter table private.edition2_audit enable row level security;
revoke all on private.edition2_audit from public,anon,authenticated;
create function private.edition2_session_name(access_token text) returns text language plpgsql security definer set search_path='' as $$
declare who text;
begin
 if access_token is null or access_token !~ '^[0-9a-f]{64}$' then raise exception 'Acesso inválido.';end if;
 select name into who from private.edition2_sessions where token_hash=extensions.digest(access_token,'sha256') and expires_at>now() for share;
 if who is null then raise exception 'Acesso inválido ou expirado. Confirme seu PIN novamente.';end if;
 return who;
end $$;
create function public.edition2_open_profile(participant_name text,secret_code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a private.edition2_access;token text;
begin
 select * into a from private.edition2_access where name=participant_name for update;
 if a.name is null then return jsonb_build_object('error','PIN inválido. Confira seu código individual.');end if;
 if a.blocked_until>now() then
  return jsonb_build_object('error','Muitas tentativas. Aguarde 15 minutos antes de tentar novamente.','retry_after',ceil(extract(epoch from a.blocked_until-now())));
 end if;
 if a.code_hash is null or secret_code is null or secret_code !~ '^[0-9a-f]{32}$' or a.code_hash<>extensions.digest(secret_code,'sha256') then
  if a.blocked_until is not null then a.failed_attempts:=0;end if;
  update private.edition2_access set failed_attempts=a.failed_attempts+1,
   blocked_until=case when a.failed_attempts+1>=5 then now()+interval '15 minutes' else null end where name=a.name;
  -- Return an error object, not an exception: the rate limit must COMMIT.
  return jsonb_build_object('error',case when a.failed_attempts+1>=5 then 'Muitas tentativas. Aguarde 15 minutos antes de tentar novamente.' else 'PIN inválido. Confira seu código individual.' end,'retry_after',case when a.failed_attempts+1>=5 then 900 else 0 end);
 end if;
 update private.edition2_access set failed_attempts=0,blocked_until=null where name=a.name;
 delete from private.edition2_sessions where name=a.name and expires_at<=now();
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into private.edition2_sessions(token_hash,name,expires_at) values(extensions.digest(token,'sha256'),a.name,now()+interval '90 days');
 return jsonb_build_object('name',a.name,'token',token);
end $$;
create function public.edition2_profile_state(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;answer jsonb;used boolean;
begin
 who:=private.edition2_session_name(access_token);
 select revealed_at is not null into used from public.edition2_participation_status where name=who;
 if used then
 select jsonb_build_object('name',a.recipient,'wish',coalesce(to_jsonb(w)-'name','{}'::jsonb)) into answer from private.edition2_assignments a left join private.edition2_wishes w on w.name=a.recipient where a.giver=who;
 end if;
 return jsonb_build_object('name',who,'id',(select id from public.edition2_participant_directory where name=who),'is_admin',who='Samuel','drawn',(select drawn from public.edition2_event where id=1),'revealed',used,'result',answer,'wish',coalesce((select to_jsonb(w)-'name' from private.edition2_wishes w where name=who),'{}'::jsonb));
end $$;
create function private.edition2_draw_once() returns void language plpgsql security definer set search_path='' as $$
declare who text;ids text[];perm text[];i int;j int;tmp text;good boolean;n bigint;bound bigint;bytes bytea;
begin
 -- All draw/reveal operations acquire the event lock before reading sessions.
 perform 1 from public.edition2_event where id=1 for update;
 who:='Samuel';
 if who<>'Samuel' then raise exception 'Somente o administrador pode inicializar o sorteio.';end if;
 if (select drawn from public.edition2_event where id=1) then raise exception 'O sorteio já foi inicializado e não pode ser refeito.';end if;
 if exists(select 1 from private.edition2_assignments) then raise exception 'Rodada inconsistente. Contate o administrador do banco.';end if;
 select array_agg(name order by name) into ids from public.edition2_participant_directory;
 if cardinality(ids)<>6 or (select count(*) from private.edition2_access)<>6 then raise exception 'Os seis perfis precisam estar configurados.';end if;
 loop
  perm:=ids;
  for i in reverse 6..2 loop
   bound:=4294967296-(4294967296 % i);
   loop
    bytes:=extensions.gen_random_bytes(4);
    n:=get_byte(bytes,0)::bigint*16777216+get_byte(bytes,1)::bigint*65536+get_byte(bytes,2)::bigint*256+get_byte(bytes,3);
    exit when n<bound;
   end loop;
   j:=(n%i)::int+1;tmp:=perm[i];perm[i]:=perm[j];perm[j]:=tmp;
  end loop;
  good:=true;
  for i in 1..6 loop if ids[i]=perm[i] then good:=false;exit;end if;end loop;
  exit when good;
 end loop;
 for i in 1..6 loop insert into private.edition2_assignments values(ids[i],perm[i]);end loop;
 update public.edition2_event set drawn=true where id=1;
 insert into private.edition2_audit(actor,action) values(who,'initialize_draw');
end $$;
create function public.edition2_initialize_code_draw(access_token text) returns void language plpgsql security definer set search_path='' as $$ begin if private.edition2_session_name(access_token)<>'Samuel' then raise exception 'Somente o administrador pode inicializar o sorteio.';end if;perform private.edition2_draw_once();end $$;
create function public.edition2_reveal_secret(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;answer jsonb;
begin
 perform 1 from public.edition2_event where id=1 for update;
 who:=private.edition2_session_name(access_token);
 if exists(select 1 from public.edition2_participation_status where name=who and revealed_at is not null) then raise exception 'Este perfil já participou. Consulte o resultado pelo Meu Perfil.';end if;
 if not (select drawn from public.edition2_event where id=1) then raise exception 'O administrador ainda não inicializou o sorteio. Sua lista de desejos já pode ser preenchida.';end if;
 if (select count(*) from private.edition2_assignments)<>6 then raise exception 'Rodada inconsistente. Contate o administrador.';end if;
 update public.edition2_participation_status set revealed_at=now() where name=who;
 select jsonb_build_object('name',a.recipient,'wish',coalesce(to_jsonb(w)-'name','{}'::jsonb)) into answer from private.edition2_assignments a left join private.edition2_wishes w on w.name=a.recipient where a.giver=who;
 return answer;
end $$;
create function public.edition2_save_code_event(access_token text,exchange_at timestamptz,location text,min_value numeric,max_value numeric,message text) returns void language plpgsql security definer set search_path='' as $$
declare who text;
begin
 perform 1 from public.edition2_event where id=1 for update;
 who:=private.edition2_session_name(access_token);
 if who<>'Samuel' then raise exception 'Somente o administrador pode alterar o encontro.';end if;
 update public.edition2_event set exchange_at=edition2_save_code_event.exchange_at,location=edition2_save_code_event.location,min_value=edition2_save_code_event.min_value,max_value=edition2_save_code_event.max_value,message=edition2_save_code_event.message where id=1;
 insert into private.edition2_audit(actor,action) values(who,'update_event');
end $$;
create function public.edition2_admin_dashboard(access_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if private.edition2_session_name(access_token)<>'Samuel' then raise exception 'Área exclusiva do administrador.';end if;
 return jsonb_build_object(
 'participants',(select jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'revealed_at',s.revealed_at,'wishes_filled',s.wishes_filled) order by d.name) from public.edition2_participant_directory d join public.edition2_participation_status s using(name)),
 'drawn',(select drawn from public.edition2_event where id=1),
 'assignment_count',(select count(*) from private.edition2_assignments),
 'audit',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select action,target,reason,created_at from private.edition2_audit order by id desc limit 20)x));
end $$;
create function public.edition2_save_participant_photo(access_token text,participant_id uuid,photo_data text) returns void language plpgsql security definer set search_path='' as $$
declare who text;target_name text;
begin
 who:=private.edition2_session_name(access_token);
 if who<>'Samuel' then raise exception 'Somente o administrador pode alterar fotografias.';end if;
 if photo_data is null or length(photo_data)>400000 or photo_data !~ '^data:image/webp;base64,[A-Za-z0-9+/]+=*$' or substring(decode(substring(photo_data from 24),'base64') from 1 for 4)<>decode('52494646','hex') or substring(decode(substring(photo_data from 24),'base64') from 9 for 4)<>decode('57454250','hex') then raise exception 'Envie uma fotografia WebP válida de até 300 KB.';end if;
 update public.edition2_participant_directory set photo=photo_data,photo_updated=true,updated_at=now() where id=participant_id returning name into target_name;
 if target_name is null then raise exception 'Participante não encontrado.';end if;
 insert into private.edition2_audit(actor,action,target) values(who,'update_photo',target_name);
end $$;
create function public.edition2_recover_participant_code(access_token text,participant_id uuid,recovery_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare who text;target_name text;code text;
begin
 who:=private.edition2_session_name(access_token);
 if who<>'Samuel' then raise exception 'Somente o administrador pode recuperar acessos.';end if;
 if recovery_reason is null or length(btrim(recovery_reason))<10 or length(recovery_reason)>500 then raise exception 'Registre como confirmou a identidade da pessoa (10 a 500 caracteres).';end if;
 select name into target_name from public.edition2_participant_directory where id=participant_id;
 if target_name is null then raise exception 'Participante não encontrado.';end if;
 if target_name=who then raise exception 'O acesso do administrador deve ser recuperado pelo proprietário no SQL Editor privado.';end if;
 perform 1 from private.edition2_access where name=target_name for update;
 code:=encode(extensions.gen_random_bytes(16),'hex');
 update private.edition2_access set code_hash=extensions.digest(code,'sha256'),failed_attempts=0,blocked_until=null,session_hash=null,session_expires_at=null where name=target_name;
 delete from private.edition2_sessions where name=target_name;
 insert into private.edition2_audit(actor,action,target,reason) values(who,'recover_access',target_name,btrim(recovery_reason));
 return jsonb_build_object('name',target_name,'code',code);
end $$;
create function public.edition2_close_profile(access_token text) returns void language plpgsql security definer set search_path='' as $$
begin delete from private.edition2_sessions where token_hash=extensions.digest(access_token,'sha256');end $$;
create function public.edition2_save_profile_wishes(access_token text,suggestions text[],preferences text,colors text,avoid text,sizes text,notes text,links text[] default null) returns void language plpgsql security definer set search_path='' as $$
declare who text;safe_links text[];filled boolean;
begin
 who:=private.edition2_session_name(access_token);
 -- Old clients that omit links preserve any URLs already saved by a newer client.
 safe_links:=coalesce(links,(select w.links from private.edition2_wishes w where w.name=who),array['','','']::text[]);
 safe_links:=array(select btrim(v) from unnest(safe_links) v);
 if not private.edition2_valid_wish_links(safe_links) then raise exception 'Informe até três links válidos, começando com https:// ou http://, com até 2048 caracteres cada.';end if;
 insert into private.edition2_wishes(name,suggestions,preferences,colors,avoid,sizes,notes,links)
 values(who,suggestions,preferences,colors,avoid,sizes,notes,safe_links)
 on conflict(name) do update set suggestions=excluded.suggestions,preferences=excluded.preferences,colors=excluded.colors,avoid=excluded.avoid,sizes=excluded.sizes,notes=excluded.notes,links=excluded.links;
 filled:=length(btrim(array_to_string(suggestions,'')||preferences||colors||avoid||sizes||notes||array_to_string(safe_links,'')))>0;
 update public.edition2_participation_status set wishes_filled=filled where name=who;
end $$;
revoke all on function private.edition2_session_name(text) from public,anon,authenticated;
revoke all on function private.edition2_valid_wish_links(text[]) from public,anon,authenticated;
revoke all on function private.edition2_draw_once() from public,anon,authenticated;
revoke all on function public.edition2_open_profile(text,text) from public,anon,authenticated;
grant execute on function public.edition2_open_profile(text,text) to anon,authenticated;
revoke all on function public.edition2_profile_state(text) from public,anon,authenticated;
grant execute on function public.edition2_profile_state(text) to anon,authenticated;
revoke all on function public.edition2_initialize_code_draw(text) from public,anon,authenticated;
grant execute on function public.edition2_initialize_code_draw(text) to anon,authenticated;
revoke all on function public.edition2_reveal_secret(text) from public,anon,authenticated;
grant execute on function public.edition2_reveal_secret(text) to anon,authenticated;
revoke all on function public.edition2_save_profile_wishes(text,text[],text,text,text,text,text,text[]) from public,anon,authenticated;
grant execute on function public.edition2_save_profile_wishes(text,text[],text,text,text,text,text,text[]) to anon,authenticated;
revoke all on function public.edition2_save_code_event(text,timestamptz,text,numeric,numeric,text) from public,anon,authenticated;
grant execute on function public.edition2_save_code_event(text,timestamptz,text,numeric,numeric,text) to anon,authenticated;
revoke all on function public.edition2_admin_dashboard(text) from public,anon,authenticated;
grant execute on function public.edition2_admin_dashboard(text) to anon,authenticated;
revoke all on function public.edition2_save_participant_photo(text,uuid,text) from public,anon,authenticated;
grant execute on function public.edition2_save_participant_photo(text,uuid,text) to anon,authenticated;
revoke all on function public.edition2_recover_participant_code(text,uuid,text) from public,anon,authenticated;
grant execute on function public.edition2_recover_participant_code(text,uuid,text) to anon,authenticated;
revoke all on function public.edition2_close_profile(text) from public,anon,authenticated;
grant execute on function public.edition2_close_profile(text) to anon,authenticated;
do $$ begin if exists(select 1 from pg_publication where pubname='supabase_realtime') then alter publication supabase_realtime add table public.edition2_event,public.edition2_participant_directory,public.edition2_participation_status;end if;end $$;
create temporary table edition1_after on commit drop as select md5(jsonb_build_object(
 'participants',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participants x),
 'event',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.event x),
 'photos',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participant_directory x),
 'status',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participation_status x),
 'assignments',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_assignments x),
 'wishes',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_wishes x),
 'pins',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.profile_access x),
 'sessions',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_sessions x),
 'audit',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.admin_audit x),
 'legacy_assignments',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.assignments x),
 'legacy_wishes',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.wishes x),
 'legacy_invites',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.enrollment_invites x)
 )::text) as digest;
do $$ begin if (select digest from edition1_guard) is distinct from (select digest from edition1_after) then raise exception 'Preservação da primeira edição falhou. Migração cancelada.';end if;end $$;
commit;
