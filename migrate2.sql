-- ============================================================
--  Migration 2: explicit match↔team columns + foreign keys
--  Idempotent — safe to run on the existing database.
-- ============================================================

-- Each match records which two teams are playing (backfilled from players' teams)
alter table matches add column if not exists team1 text;
alter table matches add column if not exists team2 text;
update matches m set team1 = p.team from players p where p.name = m.team1_p1 and m.team1 is null;
update matches m set team2 = p.team from players p where p.name = m.team2_p1 and m.team2 is null;

-- ---------- foreign keys (drop-then-add = idempotent) ----------
-- a player's team must be a real team (clearing the team if that team is deleted)
alter table players drop constraint if exists players_team_fkey;
alter table players add  constraint players_team_fkey
  foreign key (team) references teams(name) on update cascade on delete set null;

-- a match's two sides must be real teams
alter table matches drop constraint if exists matches_team1_fkey;
alter table matches add  constraint matches_team1_fkey
  foreign key (team1) references teams(name) on update cascade on delete set null;
alter table matches drop constraint if exists matches_team2_fkey;
alter table matches add  constraint matches_team2_fkey
  foreign key (team2) references teams(name) on update cascade on delete set null;

-- every player named in a match must be a real player
-- (ON UPDATE CASCADE = renames flow through; ON DELETE RESTRICT = can't delete a player who's in a match)
alter table matches drop constraint if exists matches_t1p1_fkey;
alter table matches add  constraint matches_t1p1_fkey
  foreign key (team1_p1) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t1p2_fkey;
alter table matches add  constraint matches_t1p2_fkey
  foreign key (team1_p2) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t2p1_fkey;
alter table matches add  constraint matches_t2p1_fkey
  foreign key (team2_p1) references players(name) on update cascade on delete restrict;
alter table matches drop constraint if exists matches_t2p2_fkey;
alter table matches add  constraint matches_t2p2_fkey
  foreign key (team2_p2) references players(name) on update cascade on delete restrict;
