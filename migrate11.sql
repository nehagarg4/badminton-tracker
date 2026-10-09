-- ============================================================
--  migrate11.sql — add the UMPIRE role (per-tournament, scores only)
--
--  An umpire logs in like an admin but can ONLY record match scores,
--  and ONLY for the tournament(s) they're assigned to. Assignments live
--  in the `umpires` table; super-admins manage them from "Manage access".
--
--  Self-contained & idempotent. Run AFTER migrate10.sql.
-- ============================================================

-- who may umpire which tournament (a user can umpire several; a tournament several umpires)
create table if not exists umpires (
  username      text not null references app_users(username) on delete cascade,
  tournament_id uuid not null references tournaments(id)     on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (username, tournament_id)
);
alter table umpires enable row level security;   -- no policies: reached only via SECURITY DEFINER funcs

-- login now also returns the tournaments this user may umpire
create or replace function public.app_login(u text, p text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare r app_users; umps jsonb;
begin
  select * into r from app_users where lower(username) = lower(u);
  if found and r.password = p then
    select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) into umps
      from umpires where lower(username) = lower(r.username);
    return jsonb_build_object('ok',true,'username',r.username,'is_admin',r.is_admin,'is_super',r.is_super,'umpire_of',umps);
  end if;
  return jsonb_build_object('ok',false);
end $$;

-- login dropdown = everyone who can sign in (admins + umpires)
create or replace function public.app_admin_names() returns jsonb
  language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(username order by username),'[]'::jsonb)
  from (select username from app_users where is_admin
        union
        select username from umpires) q;
$$;

-- user list now carries each user's umpire tournaments (super only; no passwords)
create or replace function public.app_list_users(su text, sp text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'users',
    (select coalesce(jsonb_agg(jsonb_build_object(
        'username', u.username, 'is_admin', u.is_admin, 'is_super', u.is_super,
        'umpire_of', (select coalesce(jsonb_agg(tournament_id),'[]'::jsonb) from umpires where lower(username)=lower(u.username))
      ) order by u.username),'[]'::jsonb)
     from app_users u));
end $$;

-- assign / unassign an umpire for a tournament (super only).
-- on=true creates the login if needed (pass required for a new user; updates pass if given),
-- never changes an existing user's admin/super flags. on=false just removes that assignment.
create or replace function public.app_set_umpire(su text, sp text, target text, pass text, tid uuid, on_flag boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare ok jsonb; uname text;
begin
  ok := public.app_login(su, sp);
  if not coalesce((ok->>'ok')::boolean,false) or not coalesce((ok->>'is_super')::boolean,false) then
    return jsonb_build_object('ok',false,'err','not a super-admin'); end if;

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

-- activity log is super-admin only. Read it through this function (credentials
-- checked server-side); the table itself is no longer publicly readable.
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

-- keep public INSERT (so logins & actions keep recording), but drop public SELECT
drop policy if exists "audit read" on audit_log;

grant execute on function public.app_login(text,text)                                      to anon, authenticated;
grant execute on function public.app_admin_names()                                         to anon, authenticated;
grant execute on function public.app_list_users(text,text)                                 to anon, authenticated;
grant execute on function public.app_set_umpire(text,text,text,text,uuid,boolean)          to anon, authenticated;
grant execute on function public.app_audit(text,text,int)                                  to anon, authenticated;
