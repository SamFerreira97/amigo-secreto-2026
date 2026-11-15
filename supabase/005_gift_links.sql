-- Add gift URLs without changing any existing wish, PIN, photo or draw result.
begin;
create function private.valid_wish_links(items text[]) returns boolean language sql immutable set search_path='' as $$
 select items is not null and coalesce(cardinality(items)<=3,false)
 and not exists(select 1 from unnest(items) v where v is null or length(v)>2048 or (v<>'' and v !~* '^https?://[^[:space:]<>]+$'))
$$;
revoke all on function private.valid_wish_links(text[]) from public,anon,authenticated;
alter table private.code_wishes add column links text[] not null default array['','','']::text[] check(private.valid_wish_links(links));
drop function public.save_profile_wishes(text,text[],text,text,text,text,text);
create function public.save_profile_wishes(access_token text,suggestions text[],preferences text,colors text,avoid text,sizes text,notes text,links text[] default null) returns void language plpgsql security definer set search_path='' as $$
declare who text;safe_links text[];filled boolean;
begin
 who:=private.session_name(access_token);
 -- Old clients that omit links preserve any URLs already saved by a newer client.
 safe_links:=coalesce(links,(select w.links from private.code_wishes w where w.name=who),array['','','']::text[]);
 safe_links:=array(select btrim(v) from unnest(safe_links) v);
 if not private.valid_wish_links(safe_links) then raise exception 'Informe até três links válidos, começando com https:// ou http://, com até 2048 caracteres cada.';end if;
 insert into private.code_wishes(name,suggestions,preferences,colors,avoid,sizes,notes,links)
 values(who,suggestions,preferences,colors,avoid,sizes,notes,safe_links)
 on conflict(name) do update set suggestions=excluded.suggestions,preferences=excluded.preferences,colors=excluded.colors,avoid=excluded.avoid,sizes=excluded.sizes,notes=excluded.notes,links=excluded.links;
 filled:=length(btrim(array_to_string(suggestions,'')||preferences||colors||avoid||sizes||notes||array_to_string(safe_links,'')))>0;
 update public.participation_status set wishes_filled=filled where name=who;
end $$;
revoke all on function public.save_profile_wishes(text,text[],text,text,text,text,text,text[]) from public;
grant execute on function public.save_profile_wishes(text,text[],text,text,text,text,text,text[]) to anon,authenticated;
commit;
