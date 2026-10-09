-- ============================================================
--  migrate8.sql — lock edits to signed-in admins (reads stay public)
--
--  BEFORE running this, do two things in the Supabase dashboard:
--   1. Authentication → Users → "Add user" → create your admin
--      account (email + password; tick "Auto Confirm User").
--   2. Authentication → Providers → Email → turn OFF
--      "Allow new users to sign up"   ← important, or anyone could
--      self-register and gain edit access.
--
--  After this runs: anyone with the link can VIEW; only signed-in
--  admins can insert/update/delete. Idempotent.
-- ============================================================

-- tournaments
drop policy if exists "public tournaments" on tournaments;
drop policy if exists "read tournaments"  on tournaments;
drop policy if exists "write tournaments" on tournaments;
create policy "read tournaments"  on tournaments for select using (true);
create policy "write tournaments" on tournaments for all to authenticated using (true) with check (true);

-- matches
drop policy if exists "public matches" on matches;
drop policy if exists "read matches"  on matches;
drop policy if exists "write matches" on matches;
create policy "read matches"  on matches for select using (true);
create policy "write matches" on matches for all to authenticated using (true) with check (true);

-- players
drop policy if exists "public players" on players;
drop policy if exists "read players"  on players;
drop policy if exists "write players" on players;
create policy "read players"  on players for select using (true);
create policy "write players" on players for all to authenticated using (true) with check (true);

-- teams
drop policy if exists "public teams" on teams;
drop policy if exists "read teams"  on teams;
drop policy if exists "write teams" on teams;
create policy "read teams"  on teams for select using (true);
create policy "write teams" on teams for all to authenticated using (true) with check (true);

-- rosters
drop policy if exists "public rosters" on rosters;
drop policy if exists "read rosters"  on rosters;
drop policy if exists "write rosters" on rosters;
create policy "read rosters"  on rosters for select using (true);
create policy "write rosters" on rosters for all to authenticated using (true) with check (true);

-- audit log: anyone may INSERT (so logins are recorded); only admins may READ.
drop policy if exists "audit insert" on audit_log;
drop policy if exists "audit read"   on audit_log;
create policy "audit insert" on audit_log for insert with check (true);
create policy "audit read"   on audit_log for select to authenticated using (true);

-- storage (team logos, player photos, schedule): public read, admin write.
drop policy if exists "images write"  on storage.objects;
drop policy if exists "images update" on storage.objects;
drop policy if exists "images delete" on storage.objects;
create policy "images write"  on storage.objects for insert to authenticated with check (bucket_id = 'images');
create policy "images update" on storage.objects for update to authenticated using (bucket_id = 'images');
create policy "images delete" on storage.objects for delete to authenticated using (bucket_id = 'images');
