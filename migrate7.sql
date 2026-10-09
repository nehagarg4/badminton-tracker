-- ============================================================
--  migrate7.sql — append-only audit log (backend only, no UI)
--  Records logins/signups and every data modification, with the
--  actor (logged-in name) and a timestamp. Read it in the Supabase
--  dashboard (Table editor / SQL); the app only writes to it.
--  Idempotent: safe to run more than once.
-- ============================================================

create extension if not exists "pgcrypto";

create table if not exists audit_log (
  id         uuid primary key default gen_random_uuid(),
  actor      text,                 -- who (the app's logged-in name), null if not set
  action     text not null,        -- e.g. login, signup, match.score, match.create, player.rename, team.captain, ...
  detail     jsonb,                -- context (sanitised args of the change)
  created_at timestamptz not null default now()
);
create index if not exists audit_log_created_idx on audit_log(created_at desc);
create index if not exists audit_log_action_idx  on audit_log(action);

-- Append-only for the public (anon) key: it may INSERT, but cannot read,
-- update or delete. View/export the log from the Supabase dashboard
-- (service role bypasses RLS).
alter table audit_log enable row level security;
drop policy if exists "audit insert" on audit_log;
create policy "audit insert" on audit_log for insert with check (true);
