-- ============================================================
--  Migration: teams + stages + multi-game scoring
--  Idempotent — safe to run on the existing database.
-- ============================================================

-- matches: best-of-N games, points target, game scores, tournament stage
alter table matches add column if not exists best_of int  not null default 3;
alter table matches add column if not exists points  int  not null default 21;
alter table matches add column if not exists games   jsonb not null default '[]'::jsonb;
alter table matches add column if not exists stage   text not null default 'League';

-- players: franchise/team they belong to
alter table players add column if not exists team text;

-- teams (franchises)
create table if not exists teams (
  name       text primary key,
  color      text,
  created_at timestamptz not null default now()
);
alter table teams enable row level security;
drop policy if exists "public teams" on teams;
create policy "public teams" on teams for all using (true) with check (true);

-- seed the 4 JCC franchises
insert into teams (name, color) values
  ('Hera Pheri Smashers',       '#2f6fed'),
  ('Team D',                    '#d6454f'),
  ('DRS-Drops Rallies Smashes', '#f2822f'),
  ('Team C',                    '#8b5cf6')
on conflict (name) do nothing;

-- assign players to their teams (updates team without touching avatars)
insert into players (name, team) values
  ('Rajeev','Hera Pheri Smashers'),('Prakash','Hera Pheri Smashers'),('Gaurang','Hera Pheri Smashers'),
  ('Sameer','Hera Pheri Smashers'),('Amogh','Hera Pheri Smashers'),('Deepankar','Hera Pheri Smashers'),
  ('Prateek','Team D'),('Ranjith','Team D'),('Sasi','Team D'),('Prithvi','Team D'),('Ankur','Team D'),('Rama','Team D'),('Ram','Team D'),
  ('Deepak','DRS-Drops Rallies Smashes'),('Gunvansh','DRS-Drops Rallies Smashes'),('Venky','DRS-Drops Rallies Smashes'),
  ('Prasad','DRS-Drops Rallies Smashes'),('Ayas','DRS-Drops Rallies Smashes'),('Mahesh','DRS-Drops Rallies Smashes'),
  ('Jagdeep','Team C'),('Ankit','Team C'),('Harsha','Team C'),('Rohith','Team C'),('Bhanu','Team C'),('Ramana','Team C')
on conflict (name) do update set team = excluded.team;

-- existing 14 matches are all League (the ADD COLUMN default already set this)
update matches set stage = 'League' where stage is null;
