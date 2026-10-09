-- ============================================================
--  Badminton Tracker — Supabase schema + seed data
--  Run this once in Supabase → SQL Editor → New query → Run.
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
-- add newer columns if the table already existed from an earlier run:
alter table tournaments add column if not exists banner_url   text;
alter table tournaments add column if not exists schedule_url text;
alter table tournaments add column if not exists stage_config jsonb not null default '{}'::jsonb;

-- players: name, optional profile photo, and the team (franchise) they belong to.
-- Analytics are derived from matches; this table stores avatar + team, keyed by name.
create table if not exists players (
  name       text primary key,
  avatar_url text,
  team       text,
  created_at timestamptz not null default now()
);
alter table players add column if not exists team text;

-- teams (franchises)
create table if not exists teams (
  name       text primary key,
  color      text,
  captain    text,          -- player name of the team captain (optional)
  created_at timestamptz not null default now()
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
  created_at    timestamptz not null default now()
);
-- add the newer columns if the table already existed from an earlier run:
alter table matches add column if not exists stage   text  not null default 'League';
alter table matches add column if not exists best_of int   not null default 3;
alter table matches add column if not exists points  int   not null default 21;
alter table matches add column if not exists games   jsonb not null default '[]'::jsonb;

create index if not exists matches_tournament_idx on matches(tournament_id);

-- ---------- row-level security ----------
-- Small trusted group app: allow the anon (public) key full access.
-- Anyone with your site link can read & edit. That's the same model
-- as a shared Google Sheet. Tighten later if you ever need to.
alter table tournaments enable row level security;
alter table matches     enable row level security;
alter table players     enable row level security;
alter table teams       enable row level security;

drop policy if exists "public tournaments" on tournaments;
create policy "public tournaments" on tournaments for all using (true) with check (true);

drop policy if exists "public matches" on matches;
create policy "public matches" on matches for all using (true) with check (true);

drop policy if exists "public players" on players;
create policy "public players" on players for all using (true) with check (true);

drop policy if exists "public teams" on teams;
create policy "public teams" on teams for all using (true) with check (true);

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
--  Seed: teams + players FIRST (so matches can reference them)
-- ============================================================
insert into teams (name, color) values
  ('Hera Pheri Smashers',       '#2f6fed'),
  ('Team D',                    '#d6454f'),
  ('DRS-Drops Rallies Smashes', '#f2822f'),
  ('Team C',                    '#8b5cf6')
on conflict (name) do nothing;

insert into players (name, team) values
  ('Rajeev','Hera Pheri Smashers'),('Prakash','Hera Pheri Smashers'),('Gaurang','Hera Pheri Smashers'),
  ('Sameer','Hera Pheri Smashers'),('Amogh','Hera Pheri Smashers'),('Deepankar','Hera Pheri Smashers'),
  ('Prateek','Team D'),('Ranjith','Team D'),('Sasi','Team D'),('Prithvi','Team D'),('Ankur','Team D'),('Rama','Team D'),('Ram','Team D'),
  ('Deepak','DRS-Drops Rallies Smashes'),('Gunvansh','DRS-Drops Rallies Smashes'),('Venky','DRS-Drops Rallies Smashes'),
  ('Prasad','DRS-Drops Rallies Smashes'),('Ayas','DRS-Drops Rallies Smashes'),('Mahesh','DRS-Drops Rallies Smashes'),
  ('Jagdeep','Team C'),('Ankit','Team C'),('Harsha','Team C'),('Rohith','Team C'),('Bhanu','Team C'),('Ramana','Team C')
on conflict (name) do update set team = excluded.team;

-- ============================================================
--  Seed: JCC Badminton Series 2026 — Fall Edition (14 matches)
--  Only seeds when that tournament name doesn't already exist.
-- ============================================================
do $$
declare tid uuid;
begin
  if not exists (select 1 from tournaments where name = 'JCC Badminton Series 2026') then
    insert into tournaments (name, edition, start_date, status, schedule_url)
      values ('JCC Badminton Series 2026', 'Fall Edition', '2026-10-10', 'active', 'assets/jcc-fall-2026-schedule.webp')
      returning id into tid;

    insert into matches (tournament_id, match_no, stage, team1_p1, team1_p2, team2_p1, team2_p2) values
      (tid, 1,  'League', 'Rajeev',   'Prakash',  'Prateek', 'Ranjith'),
      (tid, 2,  'League', 'Deepak',   'Gunvansh', 'Jagdeep', 'Ankit'),
      (tid, 3,  'League', 'Gaurang',  'Sameer',   'Sasi',    'Prithvi'),
      (tid, 4,  'League', 'Prakash',  'Amogh',    'Prateek', 'Ankur'),
      (tid, 5,  'League', 'Gunvansh', 'Venky',    'Harsha',  'Rohith'),
      (tid, 6,  'League', 'Rajeev',   'Deepankar','Sasi',    'Ranjith'),
      (tid, 7,  'League', 'Mahesh',   'Prasad',   'Jagdeep', 'Ramana'),
      (tid, 8,  'League', 'Prasad',   'Venky',    'Ankit',   'Rohith'),
      (tid, 9,  'League', 'Deepankar','Amogh',    'Ranjith', 'Ankur'),
      (tid, 10, 'League', 'Ayas',     'Gunvansh', 'Jagdeep', 'Bhanu'),
      (tid, 11, 'League', 'Ayas',     'Deepak',   'Bhanu',   'Ramana'),
      (tid, 12, 'League', 'Mahesh',   'Ayas',     'Bhanu',   'Harsha'),
      (tid, 13, 'League', 'Deepankar','Sameer',   'Prateek', 'Rama'),
      (tid, 14, 'League', 'Rajeev',   'Gaurang',  'Ram',     'Prithvi');
  end if;
end $$;

-- backfill each match's two franchises from its players' teams
update matches m set team1 = p.team from players p where p.name = m.team1_p1 and m.team1 is null;
update matches m set team2 = p.team from players p where p.name = m.team2_p1 and m.team2 is null;

-- ============================================================
--  Foreign keys (added after seed; drop-then-add = idempotent)
-- ============================================================
alter table players drop constraint if exists players_team_fkey;
alter table players add  constraint players_team_fkey foreign key (team) references teams(name) on update cascade on delete set null;

alter table matches drop constraint if exists matches_team1_fkey;
alter table matches add  constraint matches_team1_fkey foreign key (team1) references teams(name)   on update cascade on delete set null;
alter table matches drop constraint if exists matches_team2_fkey;
alter table matches add  constraint matches_team2_fkey foreign key (team2) references teams(name)   on update cascade on delete set null;
alter table matches drop constraint if exists matches_t1p1_fkey;
alter table matches add  constraint matches_t1p1_fkey foreign key (team1_p1) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t1p2_fkey;
alter table matches add  constraint matches_t1p2_fkey foreign key (team1_p2) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t2p1_fkey;
alter table matches add  constraint matches_t2p1_fkey foreign key (team2_p1) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t2p2_fkey;
alter table matches add  constraint matches_t2p2_fkey foreign key (team2_p2) references players(name) on update cascade on delete restrict;
