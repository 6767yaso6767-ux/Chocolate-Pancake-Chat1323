-- Supabase > SQL Editor > Run (update1.sql'den SONRA, bir kez). Veriler silinmez.
alter table channels add column type text not null default 'text' check (type in ('text','announce','forum'));
alter table servers add column rules text not null default '' check (char_length(rules)<=3000), add column welcome text not null default '' check (char_length(welcome)<=500);
alter table messages add column reply_to uuid references messages on delete set null;
alter table profiles add column pro boolean not null default false, add column banner text not null default '#5865f2' check (banner ~ '^#[0-9a-fA-F]{6}$');
grant update(banner) on profiles to authenticated;
revoke update on servers from authenticated; grant update(rules,welcome) on servers to authenticated;
create policy "s upd" on servers for update to authenticated using(owner=auth.uid());
update storage.buckets set file_size_limit=26214400 where id='media';

create table threads(id uuid primary key default gen_random_uuid(), channel_id uuid not null references channels on delete cascade, title text not null check (char_length(title)<=80), owner uuid not null references profiles, created timestamptz not null default now());
create table reactions(message_id uuid not null references messages on delete cascade, user_id uuid not null references profiles, emoji text not null check (char_length(emoji)<=8), primary key(message_id,user_id,emoji));
create table server_members(server_id uuid not null references servers on delete cascade, user_id uuid not null references profiles on delete cascade, primary key(server_id,user_id));
create table nicks(server_id uuid not null references servers on delete cascade, user_id uuid not null references profiles on delete cascade, nick text not null check (char_length(nick)<=24), primary key(server_id,user_id));
create table roles(id uuid primary key default gen_random_uuid(), server_id uuid not null references servers on delete cascade, name text not null check (char_length(name)<=24), color text not null check (color ~ '^#[0-9a-fA-F]{6}$'));
create table member_roles(server_id uuid not null references servers on delete cascade, user_id uuid not null references profiles on delete cascade, role_id uuid not null references roles on delete cascade, primary key(server_id,user_id));
alter table threads enable row level security; alter table reactions enable row level security; alter table server_members enable row level security;
alter table nicks enable row level security; alter table roles enable row level security; alter table member_roles enable row level security;
create or replace function public.srv_owner(s uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from servers where id=s and owner=auth.uid()) or is_admin() $$;
create policy "t read" on threads for select to authenticated using(true);
create policy "t ins" on threads for insert to authenticated with check(owner=auth.uid() and not_banned());
create policy "t del" on threads for delete to authenticated using(owner=auth.uid() or is_admin());
create policy "r read" on reactions for select to authenticated using(exists(select 1 from messages m where m.id=message_id));
create policy "r ins" on reactions for insert to authenticated with check(user_id=auth.uid() and not_banned() and exists(select 1 from messages m where m.id=message_id));
create policy "r del" on reactions for delete to authenticated using(user_id=auth.uid());
create policy "sm read" on server_members for select to authenticated using(user_id=auth.uid() or srv_owner(server_id));
create policy "sm ins" on server_members for insert to authenticated with check(user_id=auth.uid());
create policy "n read" on nicks for select to authenticated using(true);
create policy "n ins" on nicks for insert to authenticated with check(user_id=auth.uid());
create policy "n upd" on nicks for update to authenticated using(user_id=auth.uid());
create policy "n del" on nicks for delete to authenticated using(user_id=auth.uid());
create policy "ro read" on roles for select to authenticated using(true);
create policy "ro all" on roles for all to authenticated using(srv_owner(server_id)) with check(srv_owner(server_id));
create policy "mr read" on member_roles for select to authenticated using(true);
create policy "mr all" on member_roles for all to authenticated using(srv_owner(server_id)) with check(srv_owner(server_id));

create or replace function public.can_see(r text) returns boolean language sql stable security definer set search_path=public as $$ select r='global' or r like 'ch:%' or r like 'th:%' or (r like 'dm:%' and position(auth.uid()::text in r)>0) $$;
create function public.can_post(r text) returns boolean language sql stable security definer set search_path=public as $$
 select case when r ~ '^ch:[0-9a-f-]{36}$' then coalesce((select c.type<>'announce' or srv_owner(c.server_id) from channels c where c.id=substr(r,4)::uuid),false) else true end $$;
drop policy "m ins" on messages;
create policy "m ins" on messages for insert to authenticated with check(user_id=auth.uid() and can_see(room) and can_post(room) and not_banned());
create function public.admin_pro(u uuid, b boolean) returns void language plpgsql security definer set search_path=public as $$
begin if not is_admin() then raise exception 'yetki yok'; end if; update profiles set pro=b where id=u; end $$;
revoke execute on function srv_owner(uuid), can_post(text), admin_pro(uuid,boolean) from public, anon;
grant execute on function srv_owner(uuid), can_post(text), admin_pro(uuid,boolean) to authenticated;
alter publication supabase_realtime add table reactions, threads;
