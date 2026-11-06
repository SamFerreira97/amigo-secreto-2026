-- Execute once in a new Supabase project's SQL editor.
begin;
create extension if not exists pgcrypto with schema extensions;
create table public.participants(name text primary key check(name in ('Samuel','Gabi','Gabriel','Mirella','Vanessa')),user_id uuid unique references auth.users(id),is_admin boolean not null default false);
insert into public.participants(name) values ('Samuel'),('Gabi'),('Gabriel'),('Mirella'),('Vanessa');
create table public.event(id int primary key check(id=1),exchange_at timestamptz,location text not null default 'A combinar com a turma' check(length(location)<=200),min_value numeric check(min_value>=0),max_value numeric check(max_value>=0 and max_value>=min_value),drawn boolean not null default false);
insert into public.event(id) values(1);
create table public.wishes(user_id uuid primary key references public.participants(user_id),suggestions text[] not null default array['','','']::text[] check(cardinality(suggestions)<=3 and length(array_to_string(suggestions,''))<=600),preferences text not null default '' check(length(preferences)<=500),colors text not null default '' check(length(colors)<=500),avoid text not null default '' check(length(avoid)<=500));
create table public.assignments(giver uuid primary key references public.participants(user_id),recipient uuid not null unique references public.participants(user_id),check(giver<>recipient));
alter table public.participants enable row level security;
alter table public.event enable row level security;
alter table public.wishes enable row level security;
alter table public.assignments enable row level security;
revoke all on public.participants,public.event,public.wishes,public.assignments from anon,authenticated;
grant select(name,user_id,is_admin) on public.participants to authenticated;
create policy own_profile on public.participants for select to authenticated using(user_id=auth.uid());
grant select on public.event to anon,authenticated;
create policy read_event on public.event for select using(true);
grant update(exchange_at,location,min_value,max_value) on public.event to authenticated;
create policy admin_event on public.event for update to authenticated using(exists(select 1 from public.participants p where p.user_id=auth.uid() and p.is_admin)) with check(exists(select 1 from public.participants p where p.user_id=auth.uid() and p.is_admin));
grant select,insert,update on public.wishes to authenticated;
create policy own_wishes on public.wishes for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
-- No direct grants or read policies on assignments. Even the organizer cannot fetch the group.
create function public.draw_once() returns void language plpgsql security definer set search_path='' as $$
declare ids uuid[]; perm uuid[]; i int; j int; tmp uuid; good boolean; bytes bytea; n bigint; bound bigint;
begin
 if not exists(select 1 from public.participants where user_id=auth.uid() and is_admin) then raise exception 'Somente o organizador pode sortear.';end if;
 perform 1 from public.event where id=1 for update;
 if (select drawn from public.event where id=1) then raise exception 'O sorteio já foi realizado e não pode ser refeito.';end if;
 select array_agg(user_id order by name) into ids from public.participants;
 if cardinality(ids)<>5 or array_position(ids,null) is not null then raise exception 'Vincule os cinco participantes antes de sortear.';end if;
 -- Uniform Fisher-Yates using cryptographic bytes and rejection sampling.
 loop
  perm:=ids;
  for i in reverse 5..2 loop
   bound:=4294967296-(4294967296 % i);
   loop
    bytes:=extensions.gen_random_bytes(4);
    n:=get_byte(bytes,0)::bigint*16777216+get_byte(bytes,1)::bigint*65536+get_byte(bytes,2)::bigint*256+get_byte(bytes,3);
    exit when n<bound;
   end loop;
   j:=(n % i)::int+1;tmp:=perm[i];perm[i]:=perm[j];perm[j]:=tmp;
  end loop;
  good:=true;
  for i in 1..5 loop if ids[i]=perm[i] then good:=false;exit;end if;end loop;
  exit when good;
 end loop;
 for i in 1..5 loop insert into public.assignments values(ids[i],perm[i]);end loop;
 update public.event set drawn=true where id=1;
end $$;
create function public.my_result() returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória.';end if;
 select jsonb_build_object('name',p.name,'wish',coalesce(jsonb_build_object('suggestions',w.suggestions,'preferences',w.preferences,'colors',w.colors,'avoid',w.avoid),'{}'::jsonb)) into answer
 from public.assignments a join public.participants p on p.user_id=a.recipient left join public.wishes w on w.user_id=a.recipient where a.giver=auth.uid();
 return answer;
end $$;
revoke all on function public.draw_once(),public.my_result() from public,anon;
grant execute on function public.draw_once(),public.my_result() to authenticated;
commit;
