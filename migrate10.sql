-- ============================================================
--  migrate10.sql — simple built-in login (no Supabase Auth, no hashing)
--
--  app_users holds usernames + plain passwords + roles. Login and
--  management run through SECURITY DEFINER functions, so the password
--  column is never readable by the browser (the table itself is locked).
--  The login gates editing in the app (a UI gate; the match data stays
--  open to the public key, same shared-sheet model as before).
--
--  Self-contained & idempotent. Replaces the Supabase-Auth lock
--  (migrate8/9). EDIT the bootstrap line at the very bottom first.
-- ============================================================

create table if not exists app_users (
  username   text primary key,
  password   text not null,
  is_admin   boolean not null default true,
  is_super   boolean not null default false,
  created_at timestamptz not null default now()
);
alter table app_users enable row level security;   -- no policies: no direct client access

-- verify credentials; returns {ok, username, is_admin, is_super}
create or replace function public.app_login(u text, p text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare r app_users;
begin
  select * into r from app_users where lower(username) = lower(u);
  if found and r.password = p then
    return jsonb_build_object('ok',true,'username',r.username,'is_admin',r.is_admin,'is_super',r.is_super);
  end if;
  return jsonb_build_object('ok',false);
end $$;

-- names of admins (for the login dropdown) — no secrets
create or replace function public.app_admin_names() returns jsonb
  language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(username order by username),'[]'::jsonb) from app_users where is_admin;
$$;

-- list users with roles (super only; no passwords)
create or replace function public.app_list_users(su text, sp text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'users',
    (select coalesce(jsonb_agg(jsonb_build_object('username',username,'is_admin',is_admin,'is_super',is_super) order by username),'[]'::jsonb) from app_users));
end $$;

-- create/update a user (super only). Empty pass = keep existing (just change roles).
create or replace function public.app_set_user(su text, sp text, target text, pass text, admin boolean, super boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false,'err','not a super-admin'); end if;
  if coalesce(length(pass),0) > 0 then
    insert into app_users(username,password,is_admin,is_super)
      values (target, pass, coalesce(admin,true), coalesce(super,false))
      on conflict (username) do update set password=excluded.password, is_admin=excluded.is_admin, is_super=excluded.is_super;
  else
    update app_users set is_admin=coalesce(admin,is_admin), is_super=coalesce(super,is_super) where lower(username)=lower(target);
    if not found then return jsonb_build_object('ok',false,'err','set a password to create this user'); end if;
  end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.app_remove_user(su text, sp text, target text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false); end if;
  delete from app_users where lower(username)=lower(target);
  return jsonb_build_object('ok',true);
end $$;

grant execute on function public.app_login(text,text)                               to anon, authenticated;
grant execute on function public.app_admin_names()                                  to anon, authenticated;
grant execute on function public.app_list_users(text,text)                          to anon, authenticated;
grant execute on function public.app_set_user(text,text,text,text,boolean,boolean)  to anon, authenticated;
grant execute on function public.app_remove_user(text,text,text)                    to anon, authenticated;

-- ---- public read+write on the data (login is now a UI gate) ----
do $$ declare t text; begin
  foreach t in array array['tournaments','matches','players','teams','rosters'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "public %1$s" on %1$s', t);
    execute format('drop policy if exists "read %1$s"   on %1$s', t);
    execute format('drop policy if exists "write %1$s"  on %1$s', t);
    execute format('create policy "public %1$s" on %1$s for all using (true) with check (true)', t);
  end loop;
end $$;

drop policy if exists "audit insert" on audit_log;
drop policy if exists "audit read"   on audit_log;
create policy "audit insert" on audit_log for insert with check (true);
create policy "audit read"   on audit_log for select using (true);

drop policy if exists "images write"  on storage.objects;
drop policy if exists "images update" on storage.objects;
drop policy if exists "images delete" on storage.objects;
create policy "images write"  on storage.objects for insert with check (bucket_id='images');
create policy "images update" on storage.objects for update using (bucket_id='images');
create policy "images delete" on storage.objects for delete using (bucket_id='images');

-- ============================================================
--  BOOTSTRAP the first super-admin — EDIT username + password.
-- ============================================================
insert into app_users(username, password, is_admin, is_super)
  values ('Ankit', 'changeme', true, true)
  on conflict (username) do update set password=excluded.password, is_admin=true, is_super=true;
