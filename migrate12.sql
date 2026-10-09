-- ============================================================
--  migrate12.sql — per-tournament ADMINS (captains auto-admin) + umpires
--
--  Roles now:
--   • super-admin (global, app_users.is_super): full control, manage
--     access, activity log.
--   • admin OF a tournament: full edit of THAT tournament. A team's
--     captain is automatically an admin of that tournament (derived from
--     teams.captain — no row needed). Super can also grant admin explicitly
--     (tournament_admins). Admins can add umpires for their tournament.
--   • umpire OF a tournament: record scores for that tournament only.
--
--  Self-contained & idempotent. Run AFTER migrate10.sql. Supersedes
--  migrate11.sql (safe to run even if migrate11 was never run).
-- ============================================================

-- per-tournament explicit admin grants (captains are admins implicitly)
create table if not exists tournament_admins (
  username      text not null references app_users(username) on delete cascade,
  tournament_id uuid not null references tournaments(id)     on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (username, tournament_id)
);
alter table tournament_admins enable row level security;   -- no policies: SECURITY DEFINER funcs only

-- per-tournament umpire grants (created here too so migrate11 isn't required)
create table if not exists umpires (
  username      text not null references app_users(username) on delete cascade,
  tournament_id uuid not null references tournaments(id)     on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (username, tournament_id)
);
alter table umpires enable row level security;

-- tournaments a user may ADMIN = explicit grants ∪ teams they captain
create or replace function public.app_admin_of(uname text) returns jsonb
  language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(distinct tid),'[]'::jsonb) from (
    select tournament_id tid from tournament_admins where lower(username)=lower(uname)
    union
    select tournament_id tid from teams where lower(coalesce(captain,''))=lower(uname)
  ) q;
$$;

create or replace function public.app_is_admin_for(uname text, tid uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(select 1 from tournament_admins where lower(username)=lower(uname) and tournament_id=tid)
      or exists(select 1 from teams where tournament_id=tid and lower(coalesce(captain,''))=lower(uname));
$$;

-- login returns global super flag + the tournaments you may admin / umpire
create or replace function public.app_login(u text, p text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare r app_users; adm jsonb; umps jsonb;
begin
  select * into r from app_users where lower(username)=lower(u);
  if found and r.password = p then
    adm := public.app_admin_of(r.username);
    select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) into umps from umpires where lower(username)=lower(r.username);
    return jsonb_build_object('ok',true,'username',r.username,'is_super',r.is_super,
      'is_admin',(r.is_super or jsonb_array_length(adm)>0), 'admin_of',adm, 'umpire_of',umps);
  end if;
  return jsonb_build_object('ok',false);
end $$;

-- login dropdown = everyone who has a login
create or replace function public.app_admin_names() returns jsonb
  language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(username order by username),'[]'::jsonb) from app_users;
$$;

-- full user list with roles (super only; no passwords)
create or replace function public.app_list_users(su text, sp text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'users',
    (select coalesce(jsonb_agg(jsonb_build_object(
        'username', u.username, 'is_super', u.is_super,
        'admin_of',   (select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) from tournament_admins where lower(username)=lower(u.username)),
        'captain_of', (select coalesce(jsonb_agg(distinct tournament_id),'[]'::jsonb) from teams where lower(coalesce(captain,''))=lower(u.username)),
        'umpire_of',  (select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) from umpires where lower(username)=lower(u.username))
      ) order by u.username),'[]'::jsonb)
     from app_users u));
end $$;

-- umpires of one tournament (super OR an admin of that tournament)
create or replace function public.app_list_umpires(su text, sp text, tid uuid) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) then return jsonb_build_object('ok',false); end if;
  if not (coalesce((ok->>'is_super')::boolean,false) or public.app_is_admin_for(ok->>'username', tid)) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'umpires',
    (select coalesce(jsonb_agg(username order by username),'[]'::jsonb) from umpires where tournament_id=tid));
end $$;

-- create/update a login + set super flag (super only). Blank pass = keep pass, just set super.
drop function if exists public.app_set_user(text,text,text,text,boolean,boolean);
create or replace function public.app_set_user(su text, sp text, target text, pass text, super boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false,'err','not a super-admin'); end if;
  if coalesce(length(pass),0) > 0 then
    insert into app_users(username,password,is_admin,is_super) values (target, pass, false, coalesce(super,false))
      on conflict (username) do update set password=excluded.password, is_super=excluded.is_super;
  else
    update app_users set is_super=coalesce(super,is_super) where lower(username)=lower(target);
    if not found then return jsonb_build_object('ok',false,'err','set a password to create this user'); end if;
  end if;
  return jsonb_build_object('ok',true);
end $$;

-- grant/revoke per-tournament admin (super only). Creates the login if needed.
create or replace function public.app_set_admin(su text, sp text, target text, pass text, tid uuid, on_flag boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb; uname text;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false,'err','not a super-admin'); end if;
  if coalesce(on_flag,true) then
    select username into uname from app_users where lower(username)=lower(target);
    if uname is null then
      if coalesce(length(pass),0)=0 then return jsonb_build_object('ok',false,'err','set a password to create this admin'); end if;
      insert into app_users(username,password,is_admin,is_super) values (target, pass, false, false);
      uname := target;
    elsif coalesce(length(pass),0)>0 then
      update app_users set password=pass where lower(username)=lower(target);
    end if;
    insert into tournament_admins(username, tournament_id) values (uname, tid) on conflict do nothing;
  else
    delete from tournament_admins where lower(username)=lower(target) and tournament_id=tid;
  end if;
  return jsonb_build_object('ok',true);
end $$;

-- grant/revoke per-tournament umpire (super OR an admin of that tournament). Creates the login if needed.
create or replace function public.app_set_umpire(su text, sp text, target text, pass text, tid uuid, on_flag boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb; uname text;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) then return jsonb_build_object('ok',false,'err','login failed'); end if;
  if not (coalesce((ok->>'is_super')::boolean,false) or public.app_is_admin_for(ok->>'username', tid)) then
    return jsonb_build_object('ok',false,'err','not an admin for this tournament'); end if;
  if coalesce(on_flag,true) then
    select username into uname from app_users where lower(username)=lower(target);
    if uname is null then
      if coalesce(length(pass),0)=0 then return jsonb_build_object('ok',false,'err','set a password to create this umpire'); end if;
      insert into app_users(username,password,is_admin,is_super) values (target, pass, false, false);
      uname := target;
    elsif coalesce(length(pass),0)>0 then
      update app_users set password=pass where lower(username)=lower(target);
    end if;
    insert into umpires(username, tournament_id) values (uname, tid) on conflict do nothing;
  else
    delete from umpires where lower(username)=lower(target) and tournament_id=tid;
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
  delete from app_users where lower(username)=lower(target);   -- cascades to admin/umpire grants
  return jsonb_build_object('ok',true);
end $$;

-- activity log stays super-only (read via function; table not publicly readable)
create or replace function public.app_audit(su text, sp text, lim int default 150) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'rows', coalesce(
    (select jsonb_agg(jsonb_build_object('actor',actor,'action',action,'detail',detail,'created_at',created_at) order by created_at desc)
       from (select * from audit_log order by created_at desc limit coalesce(lim,150)) t), '[]'::jsonb));
end $$;
drop policy if exists "audit read" on audit_log;   -- keep public INSERT, revoke public SELECT

grant execute on function public.app_admin_of(text)                                        to anon, authenticated;
grant execute on function public.app_is_admin_for(text,uuid)                               to anon, authenticated;
grant execute on function public.app_login(text,text)                                      to anon, authenticated;
grant execute on function public.app_admin_names()                                         to anon, authenticated;
grant execute on function public.app_list_users(text,text)                                 to anon, authenticated;
grant execute on function public.app_list_umpires(text,text,uuid)                          to anon, authenticated;
grant execute on function public.app_set_user(text,text,text,text,boolean)                 to anon, authenticated;
grant execute on function public.app_set_admin(text,text,text,text,uuid,boolean)           to anon, authenticated;
grant execute on function public.app_set_umpire(text,text,text,text,uuid,boolean)          to anon, authenticated;
grant execute on function public.app_remove_user(text,text,text)                           to anon, authenticated;
grant execute on function public.app_audit(text,text,int)                                  to anon, authenticated;
