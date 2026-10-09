-- ============================================================
--  migrate-fix-logins.sql
--
--  Problem this fixes:
--    Logins live in app_users.username and you sign in by picking a
--    player name. Renaming a player cascades to rosters / teams.captain /
--    matches (those FKs are ON UPDATE CASCADE), but NOT to app_users,
--    tournament_admins or umpires — so a renamed player's login and role
--    grants were orphaned (e.g. login "Rajeev" no longer matched captain
--    "Rajeev Wali", so they logged in with no admin rights).
--
--  What this script does:
--    (1) Adds ON UPDATE CASCADE to the tournament_admins & umpires FKs on
--        app_users(username), so grants follow a username change.
--    (2) Adds app_rename_user(old,new) to rename a login (PK change
--        cascades to the grant tables).
--    (3) Updates app_list_admins to report, per captain, whether they
--        already have a login (so the UI can offer "Enable login").
--    (4) One-time repair of the CURRENT stale logins (bottom of file).
--
--  Run this ONCE in the Supabase SQL editor AFTER migrate-roles.sql.
--  Self-contained & idempotent.
-- ============================================================

-- ---------- (1) FKs: add ON UPDATE CASCADE ----------
-- Drop whatever FK(s) currently point username -> app_users, then re-add
-- with ON UPDATE CASCADE (keeps the existing ON DELETE CASCADE behaviour).
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid='public.tournament_admins'::regclass and contype='f'
             and confrelid='public.app_users'::regclass
  loop execute format('alter table public.tournament_admins drop constraint %I', c); end loop;

  for c in select conname from pg_constraint
           where conrelid='public.umpires'::regclass and contype='f'
             and confrelid='public.app_users'::regclass
  loop execute format('alter table public.umpires drop constraint %I', c); end loop;
end $$;

alter table public.tournament_admins
  add constraint tournament_admins_username_fkey
  foreign key (username) references app_users(username) on update cascade on delete cascade;

alter table public.umpires
  add constraint umpires_username_fkey
  foreign key (username) references app_users(username) on update cascade on delete cascade;

-- ---------- (2) rename a login ----------
-- Renames the login in app_users; the PK change cascades to
-- tournament_admins / umpires via the ON UPDATE CASCADE FKs above.
-- No credential check (renaming players is already a public data write);
-- no-ops quietly when old_name has no login.
create or replace function public.app_rename_user(old_name text, new_name text) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  update app_users set username = new_name where lower(username) = lower(old_name);
  return jsonb_build_object('ok', true, 'renamed', found);
end $$;

-- ---------- (3) a tournament's admins (captains now report has_login) ----------
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
    'captains', (select coalesce(jsonb_agg(jsonb_build_object(
          'name', c.captain,
          'has_login', exists(select 1 from app_users u where lower(u.username)=lower(c.captain))
        ) order by c.captain),'[]'::jsonb)
        from (select distinct captain from teams
                where tournament_id=tid and captain is not null and captain <> '') c));
end $$;

-- ---------- grants ----------
grant execute on function public.app_rename_user(text,text)     to anon, authenticated;
grant execute on function public.app_list_admins(text,text,uuid) to anon, authenticated;

-- ============================================================
--  (4) ONE-TIME repair of the current stale logins.
--  Players were renamed in the app but their logins kept the old names.
--  Runs after app_rename_user is defined above. Re-verified live
--  2026-10-09 against app_admin_names vs players.name.
--  NOTE: "Ankit" is the bootstrap super-admin — after this he signs in
--  as "Ankit Garg" (same password). "Deepankar Waichal" already matches.
-- ============================================================
select app_rename_user('Ankit','Ankit Garg');
select app_rename_user('Ankur','Ankur Bharwal');
select app_rename_user('Gaurang','Gaurang Agarwal');
select app_rename_user('Rajeev','Rajeev Wali');
