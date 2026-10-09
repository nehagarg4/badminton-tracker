-- migrate4.sql — add team captains
-- Idempotent: safe to run on the live DB more than once.
-- Adds a nullable `captain` column to teams (stores the captain's player name).

alter table teams add column if not exists captain text;
