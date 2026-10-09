-- ============================================================
--  Migration 3: per-stage match format config on the tournament
--  Idempotent — safe to run on the existing database.
-- ============================================================
-- { "League": {"best_of":3,"points":21}, "Final": {"best_of":5,"points":21}, ... }
alter table tournaments add column if not exists stage_config jsonb not null default '{}'::jsonb;
