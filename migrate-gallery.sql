-- ============================================================
--  migrate-gallery.sql — per-tournament Gallery (photos + YouTube links)
--
--  ADDITIVE ONLY: creates one new table (`gallery`) and its RLS policy.
--  It does NOT touch tournaments / matches / players / teams / rosters /
--  app_users or any existing data. Safe to run on the live database.
--
--  Photos are stored in the existing `images` Storage bucket (only the
--  public URL is saved here). Videos store just the YouTube URL — no video
--  is uploaded, so storage stays well within the free tier.
--
--  Run once in the Supabase SQL editor.
-- ============================================================

create table if not exists gallery (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  kind          text not null check (kind in ('photo','video')),
  url           text not null,          -- photo: Storage public URL; video: the YouTube URL
  caption       text,
  added_by      text,
  created_at    timestamptz not null default now()
);
create index if not exists gallery_tournament_idx on gallery(tournament_id, created_at desc);

-- public read + write (same shared-sheet / UI-gated model as the app's other tables)
alter table gallery enable row level security;
drop policy if exists "public gallery" on gallery;
create policy "public gallery" on gallery for all using (true) with check (true);
