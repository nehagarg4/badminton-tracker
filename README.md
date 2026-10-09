# 🏸 Badminton Tracker

Free match-score, standings & player-analytics website for the JCC Badminton Series
(and any future tournaments). Same stack as the babaji expense tracker:

- **One file** — `index.html`, plain HTML/JS, no build step.
- **Supabase** (free tier) — shared database, so scores sync across everyone's phones.
- **Netlify** (free tier) — hosting.

It works **immediately** with no setup (data saves in your browser only). Wire up
Supabase when you want everyone to see the same live data.

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

### 3. Put it online (Netlify)
**Easiest — drag & drop:**
1. Go to <https://app.netlify.com/drop>.
2. Drag this whole `badminton` folder onto the page. Done — you get a live URL.
3. To update later, drag the folder again (or connect the GitHub repo below for auto-deploy).

**Or connect GitHub (auto-deploys on every push), like babaji:**
```bash
cd /Users/ankitgarg/data/badminton
git add -A && git commit -m "Badminton tracker"
# create an empty repo on github.com, then:
git remote add origin https://github.com/<you>/badminton-tracker.git
git push -u origin main
```
Then in Netlify → **Add new site → Import from GitHub** → pick the repo. No build command;
publish directory = `/` (repo root).

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
