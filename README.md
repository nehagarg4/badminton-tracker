# 🏸 Badminton Tracker

**Live:** https://jcc-badminton.netlify.app

Free match-score, standings & player-analytics website for the JCC Badminton Series
(and any future tournaments).

- **One file** — `index.html`, plain HTML/JS, no build step.
- **Supabase** (free tier) — shared database, so scores, photos & schedules sync across everyone's phones. **Already connected.**
- **Netlify** (free tier) — hosting, repo `nehagarg4/badminton-tracker`. Auto-deploys on every `git push` to `main`.

It's **live and connected** — everyone who opens the link sees the same shared data.

---

## What it does

- **Dashboard** — players, matches done/pending, current leader, recent results.
- **Matches** — the schedule grouped exactly like the poster; tap to record a score,
  edit teams, or add a match. Winner is highlighted automatically.
- **Players** — leaderboard (played / won / lost / win % / points for–against / diff),
  per-tournament or all-time. Tap a player for partners + match history. Export CSV.
- **Tournaments** — create future tournaments, switch between them, edit, delete.

The **JCC Badminton Series 2026 – Fall Edition** and all 14 matches from the poster
are pre-loaded.

---

## Setup (≈10 min, all free)

### 1. Create the database (Supabase)
1. Go to <https://supabase.com> → sign in → **New project** (free plan). Pick any name/password/region.
2. When it's ready: left sidebar → **SQL Editor** → **New query**.
3. Open `schema.sql` from this folder, paste all of it, click **Run**. (Creates the tables + loads the JCC schedule.)
4. Left sidebar → **Project Settings** (gear) → **API**. Copy:
   - **Project URL** (e.g. `https://abcd1234.supabase.co`)
   - **anon public** key (the long one under "Project API keys")

### 2. Paste the keys into the app
Open `index.html`, find the CONFIG block near the top of the `<script>`, and fill in:
```js
const SUPABASE_URL = 'https://abcd1234.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOi...your-anon-public-key...';
```
Save. The pill in the header now says **Live sync**.

### 3. Publish the change
Hosting is already set up on **GitHub Pages** (repo: `nehagarg4/badminton-tracker`).
After editing `index.html`, just push — the live site updates in ~1 minute:
```bash
cd /Users/ankitgarg/data/badminton
git add -A && git commit -m "Add Supabase keys"
git push
```
That's it. Live at https://nehagarg4.github.io/badminton-tracker/

> Prefer Netlify (like babaji) or a custom domain? Both still work — the repo can be
> imported into Netlify (**Add new site → Import from GitHub**, no build command,
> publish dir `/`), or a custom domain added under the repo's **Settings → Pages**.

---

## Notes
- **Cost:** $0. Supabase free tier and Netlify free tier are plenty for this.
- **Who can edit:** anyone with the link (anon key allows read+write — same as a shared
  sheet). Fine for a club group. The RLS policies in `schema.sql` are where you'd tighten it.
- **Rename / merge players:** the poster has `Rama`, `Ramana`, `Ram`, and both `Deepak` and
  `Deepankar` — kept as written. If any are the same person, just edit the match teams to
  use one spelling and the stats merge automatically.
- **New tournament:** Tournaments tab → **New tournament** → add its matches. All analytics
  work per-tournament and all-time.
