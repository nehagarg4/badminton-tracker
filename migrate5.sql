-- ============================================================
--  migrate5.sql — per-tournament teams/rosters/captains + edit attribution
--  Players stay GLOBAL (reused across tournaments); teams, team rosters
--  and captains become scoped to each tournament. Adds "last edited by".
--
--  Safe & idempotent: wrapped in a transaction. Run once in
--  Supabase → SQL Editor. Existing data is preserved and backfilled.
-- ============================================================
begin;

-- 1) drop the FKs that pin teams by their global name, so we can
--    re-key teams as (tournament_id, name).
alter table players drop constraint if exists players_team_fkey;
alter table matches drop constraint if exists matches_team1_fkey;
alter table matches drop constraint if exists matches_team2_fkey;
alter table teams   drop constraint if exists teams_captain_fkey;

-- 2) teams become per-tournament.
alter table teams add column if not exists tournament_id uuid;
update teams set tournament_id = (select id from tournaments order by created_at limit 1)
  where tournament_id is null;
alter table teams alter column tournament_id set not null;
alter table teams drop constraint if exists teams_pkey;
alter table teams add  constraint teams_pkey primary key (tournament_id, name);
alter table teams add  constraint teams_tournament_fkey
  foreign key (tournament_id) references tournaments(id) on delete cascade;
-- captain must be a real player; clears if that player is deleted
alter table teams add  constraint teams_captain_fkey
  foreign key (captain) references players(name) on update cascade on delete set null;

-- 3) rosters: one row per player per tournament (team may be null = unassigned).
create table if not exists rosters (
  tournament_id uuid not null references tournaments(id) on delete cascade,
  player        text not null references players(name)   on update cascade on delete cascade,
  team          text,
  primary key (tournament_id, player)
);
alter table rosters drop constraint if exists rosters_team_fkey;
alter table rosters add  constraint rosters_team_fkey
  foreign key (tournament_id, team) references teams(tournament_id, name)
  on update cascade on delete set null;

-- 4) backfill rosters for the existing tournament from players.team.
insert into rosters (tournament_id, player, team)
  select (select id from tournaments order by created_at limit 1), name, team
  from players
on conflict (tournament_id, player) do nothing;

-- 5) re-add matches ↔ teams as a per-tournament (composite) FK.
alter table matches add constraint matches_team1_fkey
  foreign key (tournament_id, team1) references teams(tournament_id, name)
  on update cascade on delete set null;
alter table matches add constraint matches_team2_fkey
  foreign key (tournament_id, team2) references teams(tournament_id, name)
  on update cascade on delete set null;

-- 6) edit attribution: who last recorded/edited a match, and when.
alter table matches add column if not exists updated_by text;
alter table matches add column if not exists updated_at timestamptz;

-- 7) RLS for the new rosters table (same shared-sheet model).
alter table rosters enable row level security;
drop policy if exists "public rosters" on rosters;
create policy "public rosters" on rosters for all using (true) with check (true);

commit;

-- Note: players.team is now unused (membership lives in rosters). It's kept
-- for back-compat; you may drop it later with:
--   alter table players drop column team;
