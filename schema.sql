-- Supabase > SQL Editor'a yapistirip Run de
create table public.profiles(
  id uuid primary key references auth.users on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_]{3,20}$'),
  bio text not null default '', avatar text not null default '',
  is_admin boolean not null default false, banned boolean not null default false,
  created timestamptz not null default now());
create table public.friend_codes(id uuid primary key references public.profiles on delete cascade, code text not null);
create table public.friendships(user_id uuid not null references public.profiles on delete cascade, friend_id uuid not null references public.profiles on delete cascade, primary key(user_id,friend_id));
create table public.servers(id uuid primary key default gen_random_uuid(), name text not null check (char_length(name)<=30), emoji text not null default '', owner uuid not null references public.profiles, created timestamptz not null default now());
create table public.channels(id uuid primary key default gen_random_uuid(), server_id uuid not null references public.servers on delete cascade, name text not null check (char_length(name)<=24), created timestamptz not null default now());
create table public.messages(id uuid primary key default gen_random_uuid(), room text not null, user_id uuid not null references public.profiles, body text not null default '' check (char_length(body)<=2000), kind text not null default 'text' check (kind in ('text','image','voice')), media text, created timestamptz not null default now());
create index on public.messages(room,created desc);

create function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select coalesce((select is_admin from profiles where id=auth.uid()),false) $$;
create function public.can_see(r text) returns boolean language sql stable security definer set search_path=public as $$ select r='global' or r like 'ch:%' or (r like 'dm:%' and position(auth.uid()::text in r)>0) $$;
create function public.not_banned() returns boolean language sql stable security definer set search_path=public as $$ select not coalesce((select banned from profiles where id=auth.uid()),true) $$;

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,username) values(new.id, lower(new.raw_user_meta_data->>'username'));
  insert into friend_codes(id,code) values(new.id, upper(substr(md5(random()::text||clock_timestamp()::text),1,6)));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.add_friend(uname text, fcode text) returns boolean language plpgsql security definer set search_path=public as $$
declare f uuid;
begin
  select p.id into f from profiles p join friend_codes c on c.id=p.id where p.username=lower(uname) and c.code=upper(fcode);
  if f is null or f=auth.uid() then return false; end if;
  insert into friendships values(auth.uid(),f),(f,auth.uid()) on conflict do nothing;
  return true;
end $$;

alter table profiles enable row level security; alter table friend_codes enable row level security; alter table friendships enable row level security;
alter table servers enable row level security; alter table channels enable row level security; alter table messages enable row level security;

create policy "p read" on profiles for select to authenticated using(true);
create policy "p upd" on profiles for update to authenticated using(id=auth.uid());
revoke update on profiles from authenticated; grant update(bio,avatar) on profiles to authenticated;
create policy "c own" on friend_codes for select to authenticated using(id=auth.uid());
create policy "f own" on friendships for select to authenticated using(user_id=auth.uid());
create policy "s read" on servers for select to authenticated using(true);
create policy "s ins" on servers for insert to authenticated with check(owner=auth.uid() and not_banned());
create policy "s del" on servers for delete to authenticated using(owner=auth.uid() or is_admin());
create policy "ch read" on channels for select to authenticated using(true);
create policy "ch ins" on channels for insert to authenticated with check(exists(select 1 from servers s where s.id=server_id and s.owner=auth.uid()) and not_banned());
create policy "ch del" on channels for delete to authenticated using(is_admin() or exists(select 1 from servers s where s.id=server_id and s.owner=auth.uid()));
create policy "m read" on messages for select to authenticated using(can_see(room));
create policy "m ins" on messages for insert to authenticated with check(user_id=auth.uid() and can_see(room) and not_banned());
create policy "m del" on messages for delete to authenticated using(user_id=auth.uid() or is_admin());

insert into storage.buckets(id,name,public,file_size_limit) values('media','media',true,5242880) on conflict do nothing;
create policy "media up" on storage.objects for insert to authenticated with check(bucket_id='media' and (storage.foldername(name))[1]=auth.uid()::text);

alter publication supabase_realtime add table messages, servers, channels;
