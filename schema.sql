-- ============================================================
--  Badminton Tracker — Supabase schema + seed data
--  Run this once in Supabase → SQL Editor → New query → Run.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- tables ----------
create table if not exists tournaments (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  edition     text,
  start_date  date,
  status      text not null default 'active',   -- 'active' | 'completed'
  created_at  timestamptz not null default now()
);

create table if not exists matches (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  match_no      int,
  group_label   text,
  team1_p1      text,
  team1_p2      text,
  team2_p1      text,
  team2_p2      text,
  score1        int,
  score2        int,
  status        text not null default 'scheduled', -- 'scheduled' | 'completed'
  created_at    timestamptz not null default now()
);

create index if not exists matches_tournament_idx on matches(tournament_id);

-- ---------- row-level security ----------
-- Small trusted group app: allow the anon (public) key full access.
-- Anyone with your site link can read & edit. That's the same model
-- as a shared Google Sheet. Tighten later if you ever need to.
alter table tournaments enable row level security;
alter table matches     enable row level security;

drop policy if exists "public tournaments" on tournaments;
create policy "public tournaments" on tournaments for all using (true) with check (true);

drop policy if exists "public matches" on matches;
create policy "public matches" on matches for all using (true) with check (true);

-- ============================================================
--  Seed: JCC Badminton Series 2026 — Fall Edition (14 matches)
--  Safe to skip if you'd rather start empty, or to re-run: it
--  only seeds when that tournament name doesn't already exist.
-- ============================================================
do $$
declare tid uuid;
begin
  if not exists (select 1 from tournaments where name = 'JCC Badminton Series 2026') then
    insert into tournaments (name, edition, start_date, status)
      values ('JCC Badminton Series 2026', 'Fall Edition', '2026-10-10', 'active')
      returning id into tid;

    insert into matches (tournament_id, match_no, group_label, team1_p1, team1_p2, team2_p1, team2_p2) values
      (tid, 1,  'Matches 1–9',          'Rajeev',   'Prakash',  'Prateek', 'Ranjith'),
      (tid, 2,  'Matches 1–9',          'Deepak',   'Gunvansh', 'Jagdeep', 'Ankit'),
      (tid, 3,  'Matches 1–9',          'Gaurang',  'Sameer',   'Sasi',    'Prithvi'),
      (tid, 4,  'Matches 1–9',          'Prakash',  'Amogh',    'Prateek', 'Ankur'),
      (tid, 5,  'Matches 1–9',          'Gunvansh', 'Venky',    'Harsha',  'Rohith'),
      (tid, 6,  'Matches 1–9',          'Rajeev',   'Deepankar','Sasi',    'Ranjith'),
      (tid, 7,  'Matches 1–9',          'Mahesh',   'Prasad',   'Jagdeep', 'Ramana'),
      (tid, 8,  'Matches 1–9',          'Prasad',   'Venky',    'Ankit',   'Rohith'),
      (tid, 9,  'Matches 1–9',          'Deepankar','Amogh',    'Ranjith', 'Ankur'),
      (tid, 10, 'Sunday Matches',       'Ayas',     'Gunvansh', 'Jagdeep', 'Bhanu'),
      (tid, 11, 'Sunday Matches',       'Ayas',     'Deepak',   'Bhanu',   'Ramana'),
      (tid, 12, 'Sunday Matches',       'Mahesh',   'Ayas',     'Bhanu',   'Harsha'),
      (tid, 13, 'October 17th Weekend', 'Deepankar','Sameer',   'Prateek', 'Rama'),
      (tid, 14, 'October 17th Weekend', 'Rajeev',   'Gaurang',  'Ram',     'Prithvi');
  end if;
end $$;
