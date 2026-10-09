-- migrate6.sql — team icons/logos
-- Idempotent: safe to run on the live DB more than once.
-- Adds a nullable `logo` column to teams (stores the icon's public URL).

alter table teams add column if not exists logo text;
