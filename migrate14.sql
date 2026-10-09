-- ============================================================
--  migrate14.sql — manage a tournament's admins & umpires from its edit page
--
--  • New app_list_admins(su,sp,tid): returns a tournament's explicit admins
--    and its captains (captains are admins automatically). Visible to super,
--    global admins, or an admin of that tournament.
--  • app_set_admin now allows super OR global admin OR an admin of that
--    tournament to grant/revoke per-tournament admins (was super-only), so
--    captains/admins can manage their own tournament.
--
--  Run AFTER migrate13.sql. Idempotent.
-- ============================================================

-- a tournament's admins: explicit grants + captains (both as name lists)
create or replace function public.app_list_admins(su text, sp text, tid uuid) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) then return jsonb_build_object('ok',false); end if;
  if not (coalesce((ok->>'is_super')::boolean,false) or coalesce((ok->>'is_global_admin')::boolean,false) or public.app_is_admin_for(ok->>'username', tid)) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,
    'explicit', (select coalesce(jsonb_agg(username order by username),'[]'::jsonb) from tournament_admins where tournament_id=tid),
    'captains', (select coalesce(jsonb_agg(distinct captain order by captain),'[]'::jsonb) from teams where tournament_id=tid and captain is not null and captain <> ''));
end $$;

-- grant/revoke per-tournament admin: super OR global admin OR an admin of that tournament
create or replace function public.app_set_admin(su text, sp text, target text, pass text, tid uuid, on_flag boolean) returns jsonb
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

grant execute on function public.app_list_admins(text,text,uuid)                   to anon, authenticated;
grant execute on function public.app_set_admin(text,text,text,text,uuid,boolean)   to anon, authenticated;
