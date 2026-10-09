-- ============================================================
--  migrate13.sql — reintroduce GLOBAL ADMIN (edit & score any tournament)
--
--  Adds a global-admin tier on top of migrate12's per-tournament roles:
--   • super  (app_users.is_super): everything + manage access + activity log.
--   • global admin (app_users.is_admin = true): edit & score EVERY tournament
--     (but not manage-access / create-delete tournaments).
--   • admin OF a tournament (captains + tournament_admins): that tournament.
--   • umpire OF a tournament: scores for that tournament only.
--
--  Run AFTER migrate12.sql. Idempotent.
-- ============================================================

-- login now also returns is_global_admin (the app_users.is_admin column)
create or replace function public.app_login(u text, p text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare r app_users; adm jsonb; umps jsonb;
begin
  select * into r from app_users where lower(username)=lower(u);
  if found and r.password = p then
    adm := public.app_admin_of(r.username);
    select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) into umps from umpires where lower(username)=lower(r.username);
    return jsonb_build_object('ok',true,'username',r.username,'is_super',r.is_super,
      'is_global_admin', r.is_admin,
      'is_admin', (r.is_super or r.is_admin or jsonb_array_length(adm)>0),
      'admin_of', adm, 'umpire_of', umps);
  end if;
  return jsonb_build_object('ok',false);
end $$;

-- user list now carries is_admin (global) so super can see/toggle it
create or replace function public.app_list_users(su text, sp text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'users',
    (select coalesce(jsonb_agg(jsonb_build_object(
        'username', u.username, 'is_super', u.is_super, 'is_admin', u.is_admin,
        'admin_of',   (select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) from tournament_admins where lower(username)=lower(u.username)),
        'captain_of', (select coalesce(jsonb_agg(distinct tournament_id),'[]'::jsonb) from teams where lower(coalesce(captain,''))=lower(u.username)),
        'umpire_of',  (select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) from umpires where lower(username)=lower(u.username))
      ) order by u.username),'[]'::jsonb)
     from app_users u));
end $$;

-- create/update a login + set GLOBAL admin and/or super (super only). Blank pass = keep pass, just set flags.
drop function if exists public.app_set_user(text,text,text,text,boolean);
create or replace function public.app_set_user(su text, sp text, target text, pass text, admin boolean, super boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false,'err','not a super-admin'); end if;
  if coalesce(length(pass),0) > 0 then
    insert into app_users(username,password,is_admin,is_super) values (target, pass, coalesce(admin,false), coalesce(super,false))
      on conflict (username) do update set password=excluded.password, is_admin=excluded.is_admin, is_super=excluded.is_super;
  else
    update app_users set is_admin=coalesce(admin,is_admin), is_super=coalesce(super,is_super) where lower(username)=lower(target);
    if not found then return jsonb_build_object('ok',false,'err','set a password to create this user'); end if;
  end if;
  return jsonb_build_object('ok',true);
end $$;

-- umpire management: super OR global-admin OR an admin of that tournament
create or replace function public.app_list_umpires(su text, sp text, tid uuid) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) then return jsonb_build_object('ok',false); end if;
  if not (coalesce((ok->>'is_super')::boolean,false) or coalesce((ok->>'is_global_admin')::boolean,false) or public.app_is_admin_for(ok->>'username', tid)) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'umpires',
    (select coalesce(jsonb_agg(username order by username),'[]'::jsonb) from umpires where tournament_id=tid));
end $$;

create or replace function public.app_set_umpire(su text, sp text, target text, pass text, tid uuid, on_flag boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb; uname text;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) then return jsonb_build_object('ok',false,'err','login failed'); end if;
  if not (coalesce((ok->>'is_super')::boolean,false) or coalesce((ok->>'is_global_admin')::boolean,false) or public.app_is_admin_for(ok->>'username', tid)) then
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

grant execute on function public.app_login(text,text)                               to anon, authenticated;
grant execute on function public.app_list_users(text,text)                          to anon, authenticated;
grant execute on function public.app_set_user(text,text,text,text,boolean,boolean)  to anon, authenticated;
grant execute on function public.app_list_umpires(text,text,uuid)                   to anon, authenticated;
grant execute on function public.app_set_umpire(text,text,text,text,uuid,boolean)   to anon, authenticated;
