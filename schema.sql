-- ============================================================
--  Badminton Tracker — Supabase schema + seed data
--  Run this once in Supabase → SQL Editor → New query → Run.
--
--  Model: PLAYERS are global (reused across tournaments). TEAMS,
--  team ROSTERS and captains are per-tournament. Matches carry a
--  "last edited by" stamp.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- tables ----------
create table if not exists tournaments (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  edition      text,
  start_date   date,
  status       text not null default 'active',   -- 'active' | 'completed'
  banner_url   text,
  schedule_url text,
  stage_config jsonb not null default '{}'::jsonb, -- per-stage {best_of, points}
  created_at   timestamptz not null default now()
);

-- players: global identity + optional profile photo. Reused across tournaments.
create table if not exists players (
  name       text primary key,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- teams (franchises): per-tournament. Same name can exist in different tournaments.
create table if not exists teams (
  tournament_id uuid not null references tournaments(id) on delete cascade,
  name          text not null,
  color         text,
  captain       text,          -- player name of the team captain (optional)
  created_at    timestamptz not null default now(),
  primary key (tournament_id, name)
);

-- rosters: which team a player is on, per tournament (one row per player per tournament).
create table if not exists rosters (
  tournament_id uuid not null references tournaments(id) on delete cascade,
  player        text not null references players(name) on update cascade on delete cascade,
  team          text,
  primary key (tournament_id, player)
);

create table if not exists matches (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  match_no      int,
  group_label   text,
  stage         text not null default 'League',   -- League | Quarter-final | Semi-final | Final | 3rd place
  best_of       int  not null default 3,          -- 3 or 5 games
  points        int  not null default 21,         -- 15 or 21 points per game
  games         jsonb not null default '[]'::jsonb, -- [{"s1":21,"s2":18}, ...]
  team1         text,   -- franchise on side 1 (FK added at the end, after seed)
  team2         text,   -- franchise on side 2
  team1_p1      text,
  team1_p2      text,
  team2_p1      text,
  team2_p2      text,
  score1        int,   -- legacy single-game score (kept for back-compat)
  score2        int,
  status        text not null default 'scheduled', -- 'scheduled' | 'completed'
  updated_by    text,  -- who last recorded/edited this match
  updated_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists matches_tournament_idx on matches(tournament_id);

-- ---------- row-level security ----------
-- Small trusted group app: allow the anon (public) key full access.
-- Anyone with your site link can read & edit — same model as a shared Google Sheet.
alter table tournaments enable row level security;
alter table matches     enable row level security;
alter table players     enable row level security;
alter table teams       enable row level security;
alter table rosters     enable row level security;

drop policy if exists "public tournaments" on tournaments;
create policy "public tournaments" on tournaments for all using (true) with check (true);
drop policy if exists "public matches" on matches;
create policy "public matches" on matches for all using (true) with check (true);
drop policy if exists "public players" on players;
create policy "public players" on players for all using (true) with check (true);
drop policy if exists "public teams" on teams;
create policy "public teams" on teams for all using (true) with check (true);
drop policy if exists "public rosters" on rosters;
create policy "public rosters" on rosters for all using (true) with check (true);

-- ---------- storage: profile pics, banners, schedule images ----------
insert into storage.buckets (id, name, public)
  values ('images', 'images', true)
  on conflict (id) do nothing;

drop policy if exists "images read"   on storage.objects;
drop policy if exists "images write"  on storage.objects;
drop policy if exists "images update" on storage.objects;
drop policy if exists "images delete" on storage.objects;
create policy "images read"   on storage.objects for select using (bucket_id = 'images');
create policy "images write"  on storage.objects for insert with check (bucket_id = 'images');
create policy "images update" on storage.objects for update using (bucket_id = 'images');
create policy "images delete" on storage.objects for delete using (bucket_id = 'images');

-- ============================================================
--  Seed: global players, then JCC Badminton Series 2026 — Fall Edition
--  (teams, rosters and 14 matches scoped to that tournament)
-- ============================================================
insert into players (name) values
  ('Rajeev'),('Prakash'),('Gaurang'),('Sameer'),('Amogh'),('Deepankar'),
  ('Prateek'),('Ranjith'),('Sasi'),('Prithvi'),('Ankur'),('Rama'),('Ram'),
  ('Deepak'),('Gunvansh'),('Venky'),('Prasad'),('Ayas'),('Mahesh'),
  ('Jagdeep'),('Ankit'),('Harsha'),('Rohith'),('Bhanu'),('Ramana')
on conflict (name) do nothing;

do $$
declare tid uuid;
begin
  if not exists (select 1 from tournaments where name = 'JCC Badminton Series 2026') then
    insert into tournaments (name, edition, start_date, status, schedule_url)
      values ('JCC Badminton Series 2026', 'Fall Edition', '2026-10-10', 'active', 'assets/jcc-fall-2026-schedule.webp')
      returning id into tid;

    insert into teams (tournament_id, name, color) values
      (tid, 'Hera Pheri Smashers',       '#2f6fed'),
      (tid, 'Team D',                    '#d6454f'),
      (tid, 'DRS-Drops Rallies Smashes', '#f2822f'),
      (tid, 'Team C',                    '#8b5cf6');

    insert into rosters (tournament_id, player, team) values
      (tid,'Rajeev','Hera Pheri Smashers'),(tid,'Prakash','Hera Pheri Smashers'),(tid,'Gaurang','Hera Pheri Smashers'),
      (tid,'Sameer','Hera Pheri Smashers'),(tid,'Amogh','Hera Pheri Smashers'),(tid,'Deepankar','Hera Pheri Smashers'),
      (tid,'Prateek','Team D'),(tid,'Ranjith','Team D'),(tid,'Sasi','Team D'),(tid,'Prithvi','Team D'),(tid,'Ankur','Team D'),(tid,'Rama','Team D'),(tid,'Ram','Team D'),
      (tid,'Deepak','DRS-Drops Rallies Smashes'),(tid,'Gunvansh','DRS-Drops Rallies Smashes'),(tid,'Venky','DRS-Drops Rallies Smashes'),
      (tid,'Prasad','DRS-Drops Rallies Smashes'),(tid,'Ayas','DRS-Drops Rallies Smashes'),(tid,'Mahesh','DRS-Drops Rallies Smashes'),
      (tid,'Jagdeep','Team C'),(tid,'Ankit','Team C'),(tid,'Harsha','Team C'),(tid,'Rohith','Team C'),(tid,'Bhanu','Team C'),(tid,'Ramana','Team C');

    insert into matches (tournament_id, match_no, stage, team1, team2, team1_p1, team1_p2, team2_p1, team2_p2) values
      (tid, 1,  'League', 'Hera Pheri Smashers','Team D', 'Rajeev',   'Prakash',  'Prateek', 'Ranjith'),
      (tid, 2,  'League', 'DRS-Drops Rallies Smashes','Team C', 'Deepak',   'Gunvansh', 'Jagdeep', 'Ankit'),
      (tid, 3,  'League', 'Hera Pheri Smashers','Team D', 'Gaurang',  'Sameer',   'Sasi',    'Prithvi'),
      (tid, 4,  'League', 'Hera Pheri Smashers','Team D', 'Prakash',  'Amogh',    'Prateek', 'Ankur'),
      (tid, 5,  'League', 'DRS-Drops Rallies Smashes','Team C', 'Gunvansh', 'Venky',    'Harsha',  'Rohith'),
      (tid, 6,  'League', 'Hera Pheri Smashers','Team D', 'Rajeev',   'Deepankar','Sasi',    'Ranjith'),
      (tid, 7,  'League', 'DRS-Drops Rallies Smashes','Team C', 'Mahesh',   'Prasad',   'Jagdeep', 'Ramana'),
      (tid, 8,  'League', 'DRS-Drops Rallies Smashes','Team C', 'Prasad',   'Venky',    'Ankit',   'Rohith'),
      (tid, 9,  'League', 'Hera Pheri Smashers','Team D', 'Deepankar','Amogh',    'Ranjith', 'Ankur'),
      (tid, 10, 'League', 'DRS-Drops Rallies Smashes','Team C', 'Ayas',     'Gunvansh', 'Jagdeep', 'Bhanu'),
      (tid, 11, 'League', 'DRS-Drops Rallies Smashes','Team C', 'Ayas',     'Deepak',   'Bhanu',   'Ramana'),
      (tid, 12, 'League', 'DRS-Drops Rallies Smashes','Team C', 'Mahesh',   'Ayas',     'Bhanu',   'Harsha'),
      (tid, 13, 'League', 'Hera Pheri Smashers','Team D', 'Deepankar','Sameer',   'Prateek', 'Rama'),
      (tid, 14, 'League', 'Hera Pheri Smashers','Team D', 'Rajeev',   'Gaurang',  'Ram',     'Prithvi');
  end if;
end $$;

-- ============================================================
--  Foreign keys (added after seed; drop-then-add = idempotent)
-- ============================================================
alter table rosters drop constraint if exists rosters_team_fkey;
alter table rosters add  constraint rosters_team_fkey foreign key (tournament_id, team) references teams(tournament_id, name) on update cascade on delete set null;

alter table teams drop constraint if exists teams_captain_fkey;
alter table teams add  constraint teams_captain_fkey foreign key (captain) references players(name) on update cascade on delete set null;

alter table matches drop constraint if exists matches_team1_fkey;
alter table matches add  constraint matches_team1_fkey foreign key (tournament_id, team1) references teams(tournament_id, name) on update cascade on delete set null;
alter table matches drop constraint if exists matches_team2_fkey;
alter table matches add  constraint matches_team2_fkey foreign key (tournament_id, team2) references teams(tournament_id, name) on update cascade on delete set null;
alter table matches drop constraint if exists matches_t1p1_fkey;
alter table matches add  constraint matches_t1p1_fkey foreign key (team1_p1) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t1p2_fkey;
alter table matches add  constraint matches_t1p2_fkey foreign key (team1_p2) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t2p1_fkey;
alter table matches add  constraint matches_t2p1_fkey foreign key (team2_p1) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t2p2_fkey;
alter table matches add  constraint matches_t2p2_fkey foreign key (team2_p2) references players(name) on update cascade on delete restrict;
