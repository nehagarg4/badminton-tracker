-- ============================================================
--  migrate9.sql — admin roles (super-admins manage admins)
--
--  Model: Supabase Auth = login; the `admins` table = who may edit.
--  You can edit only if your signed-in email is in `admins`.
--  Super-admins (is_super) can add/remove admins from inside the app.
--
--  Self-contained & idempotent. Supersedes migrate7/migrate8 (it also
--  creates the audit_log table and sets all RLS). Run it once, AFTER
--  editing the bootstrap line at the bottom to your email.
--
--  Also do this in the dashboard: Authentication → Providers → Email →
--  keep "Confirm email" ON (or OFF if you want instant self-signup), and
--  decide whether to allow sign-ups (needed if new admins self-register).
-- ============================================================
create extension if not exists "pgcrypto";

-- ---- audit log (append-only) ----
create table if not exists audit_log (
  id uuid primary key default gen_random_uuid(),
  actor text, action text not null, detail jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_log_created_idx on audit_log(created_at desc);
alter table audit_log enable row level security;

-- ---- admins (authorisation list) ----
create table if not exists admins (
  email      text primary key,
  is_super   boolean not null default false,
  added_by   text,
  created_at timestamptz not null default now()
);
alter table admins enable row level security;

-- role helpers (security definer so they can read admins under RLS)
create or replace function public.is_app_admin() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where lower(email) = lower(coalesce(auth.jwt()->>'email','')));
$$;
create or replace function public.is_app_super() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where lower(email) = lower(coalesce(auth.jwt()->>'email','')) and is_super);
$$;

-- admins table: only admins may read the list; only super-admins change it.
drop policy if exists "admins read"   on admins;
drop policy if exists "admins manage" on admins;
create policy "admins read"   on admins for select to authenticated using (public.is_app_admin());
create policy "admins manage" on admins for all to authenticated using (public.is_app_super()) with check (public.is_app_super());

-- ---- data: public read, admin-only write ----
do $$ declare t text;
begin
  foreach t in array array['tournaments','matches','players','teams','rosters'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "public %1$s" on %1$s', t);
    execute format('drop policy if exists "read %1$s"   on %1$s', t);
    execute format('drop policy if exists "write %1$s"  on %1$s', t);
    execute format('create policy "read %1$s"  on %1$s for select using (true)', t);
    execute format('create policy "write %1$s" on %1$s for all to authenticated using (public.is_app_admin()) with check (public.is_app_admin())', t);
  end loop;
end $$;

-- audit: anyone may INSERT (so logins are recorded); only admins may READ.
drop policy if exists "audit insert" on audit_log;
drop policy if exists "audit read"   on audit_log;
create policy "audit insert" on audit_log for insert with check (true);
create policy "audit read"   on audit_log for select to authenticated using (public.is_app_admin());

-- storage (team logos, photos, schedule): public read, admin write.
drop policy if exists "images write"  on storage.objects;
drop policy if exists "images update" on storage.objects;
drop policy if exists "images delete" on storage.objects;
create policy "images write"  on storage.objects for insert to authenticated with check (bucket_id='images' and public.is_app_admin());
create policy "images update" on storage.objects for update to authenticated using (bucket_id='images' and public.is_app_admin());
create policy "images delete" on storage.objects for delete to authenticated using (bucket_id='images' and public.is_app_admin());

-- ============================================================
--  BOOTSTRAP — make yourself the first super-admin. EDIT THE EMAIL.
--  (Use the same email you'll sign in with.)
-- ============================================================
insert into admins (email, is_super) values ('YOUR_EMAIL@example.com', true)
  on conflict (email) do update set is_super = true;
