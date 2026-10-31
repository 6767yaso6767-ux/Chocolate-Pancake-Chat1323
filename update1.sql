-- Supabase > SQL Editor > Run (bir kez calistir). Mevcut hesaplar ve mesajlar silinmez.
alter table profiles add constraint bio_len check (char_length(bio)<=160);
alter table profiles add constraint av_ok check (avatar='' or (avatar like 'data:image/%' and char_length(avatar)<40000));
alter table messages add constraint media_ok check (media is null or media like 'https://olnkpxxuzhxdjyuecpsn.supabase.co/storage/v1/object/public/media/%');

create table config(key text primary key, value text not null default '');
alter table config enable row level security;
create policy "cfg read" on config for select to authenticated using(key<>'invite');
create table friend_attempts(user_id uuid not null, at timestamptz not null default now());
alter table friend_attempts enable row level security;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare inv text;
begin
  select value into inv from config where key='invite';
  if coalesce(inv,'')<>'' and (new.raw_user_meta_data->>'invite') is distinct from inv then raise exception 'Davet kodu yanlis'; end if;
  insert into profiles(id,username) values(new.id, lower(new.raw_user_meta_data->>'username'));
  insert into friend_codes(id,code) values(new.id, upper(substr(md5(random()::text||clock_timestamp()::text),1,6)));
  return new;
end $$;

create or replace function public.add_friend(uname text, fcode text) returns boolean language plpgsql security definer set search_path=public as $$
declare f uuid;
begin
  if (select count(*) from friend_attempts where user_id=auth.uid() and at>now()-interval '10 minutes')>=10 then return false; end if;
  insert into friend_attempts(user_id) values(auth.uid());
  select p.id into f from profiles p join friend_codes c on c.id=p.id where p.username=lower(uname) and c.code=upper(fcode);
  if f is null or f=auth.uid() then return false; end if;
  insert into friendships values(auth.uid(),f),(f,auth.uid()) on conflict do nothing;
  return true;
end $$;

create function public.rl_messages() returns trigger language plpgsql as $$
begin
  if (select count(*) from messages where user_id=new.user_id and created>now()-interval '10 seconds')>=8 then raise exception 'Cok hizli yaziyorsun'; end if;
  return new;
end $$;
create trigger rl_messages before insert on messages for each row execute function rl_messages();
create function public.rl_servers() returns trigger language plpgsql as $$
begin
  if (select count(*) from servers where owner=new.owner)>=5 then raise exception 'En fazla 5 sunucu'; end if;
  return new;
end $$;
create trigger rl_servers before insert on servers for each row execute function rl_servers();

create function public.admin_announce(t text) returns void language plpgsql security definer set search_path=public as $$
begin if not is_admin() then raise exception 'yetki yok'; end if;
  insert into config(key,value) values('announce',left(t,200)) on conflict(key) do update set value=excluded.value; end $$;
create function public.admin_ban(u uuid, b boolean) returns void language plpgsql security definer set search_path=public as $$
begin if not is_admin() then raise exception 'yetki yok'; end if; update profiles set banned=b where id=u and not is_admin; end $$;
create function public.admin_clear_global() returns void language plpgsql security definer set search_path=public as $$
begin if not is_admin() then raise exception 'yetki yok'; end if; delete from messages where room='global'; end $$;

revoke execute on function is_admin(), can_see(text), not_banned(), add_friend(text,text), admin_announce(text), admin_ban(uuid,boolean), admin_clear_global() from public, anon;
grant execute on function is_admin(), can_see(text), not_banned(), add_friend(text,text), admin_announce(text), admin_ban(uuid,boolean), admin_clear_global() to authenticated;
alter publication supabase_realtime add table config;
-- Istege bagli: kayit icin davet kodu zorunlu olsun (KODUN yerine kendi kodunu yaz):
-- insert into config(key,value) values('invite','KODUN');
