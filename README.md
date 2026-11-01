# CCE Talent Network

A curated network of project-based professionals who bring specialized expertise to CCE client work. **Develop People. Build Better Systems.**

This app has two halves:

- **Public site** (`talent.partnerwithcce.com`): the "Apply to the CCE Talent Network" application, with resume upload and auto-fill.
- **Admin backend** (`/admin`): where CCE admins review applicants, move them through statuses, and search the talent pool.

Build progress and the plan live in [`docs/PLAN.md`](docs/PLAN.md). Choices and the reasons behind them live in [`DECISIONS.md`](DECISIONS.md).

## Stack

| Piece | What it does | Cost |
|---|---|---|
| Next.js + TypeScript + Tailwind | The website and admin screens | Free |
| Supabase | Database, logins, private file storage, access rules | Free tier (keep-alive job prevents pausing) |
| Netlify | Hosting | Free tier |
| Claude API (Haiku) | Reads resumes and fills in the form | About $0.35 per 100 applicants |
| Resend | Confirmation emails | Free tier (100/day, 3,000/month) |
| Slack webhooks | New-application pings and failure alerts | Free |

---

## Run it on your computer

You need **Node.js 22 or newer** ([download](https://nodejs.org)).

1. **Install packages**
   ```bash
   npm install
   ```
2. **Create a Supabase project** at [supabase.com](https://supabase.com) (free tier). Pick a region near Houston (for example, US East).
3. **Connect this code to it and create the tables**
   ```bash
   npx supabase login
   npx supabase link --project-ref YOUR-PROJECT-REF   # the ref is in your project URL
   npx supabase db push                              # creates every table and access rule
   ```
4. **Fill in your settings.** Copy `.env.example` to `.env.local` and paste in the values (each line says where to find it).
5. **Load the catalog** (practices, roles, skills, certifications, dropdown lists, your admin login):
   ```bash
   npm run seed:apply
   ```
6. **Optional: load the 10 sample applicants** for testing filters:
   ```bash
   npm run sample:load
   ```
7. **Start the site**
   ```bash
   npm run dev
   ```
   Open http://localhost:3000.

---

## Edit roles, skills, certifications, and dropdowns

Everything you'll change often lives in one file: **`supabase/seed-data/catalog.yaml`**. Nothing is hard-coded in the screens.

1. Open `supabase/seed-data/catalog.yaml` and edit. The comments at the top explain the rules. The short version:
   - Change a `name` freely. Leave the `slug` alone once people have used it.
   - Removing an item hides it from the form. It doesn't erase it from people who already picked it.
   - Certifications: when you've confirmed one, set `needs_verification: false` and add `last_verified: 2026-11-15`.
2. Rebuild and apply:
   ```bash
   npm run seed:build    # checks your edits and regenerates the SQL
   npm run seed:apply    # pushes the changes to the database
   ```
   `seed:build` stops with a plain message if something doesn't line up (for example, a sample person using a skill that no longer exists).
3. `docs/SEED-REVIEW.md` is regenerated as a readable list of the full catalog.

## Sample data

The 10 sample applicants and 1 sample firm are fictional. Every name ends in "(Sample)" and every record is flagged `is_sample`. **Before launch**, remove them all:

```bash
npm run sample:remove
```

---

## Testing

The automated tests check the parts most likely to break quietly: access rules (nobody but admins can see applicant data), status history logging, search, and the seed data.

The database tests need a Postgres server. The easiest way on your computer is Docker Desktop plus the Supabase CLI:

```bash
npx supabase start     # local Supabase in Docker
TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres npm test
```

If `TEST_DATABASE_URL` isn't set, the database tests are skipped (and say so).

Other checks:

```bash
npm run typecheck
npm run lint
npm run build
```

---

## Deploy

Full Netlify and DNS steps arrive with slice 8 of the plan. The domain is configurable through `NEXT_PUBLIC_SITE_URL`, so changing it later is a settings change, not a code change.

DNS for `partnerwithcce.com` is managed in **Squarespace**. The `talent` subdomain will point to Netlify with a single CNAME record, and Resend will need a few TXT records to verify the sending address. Step-by-step instructions will be added here when we deploy.

---

## Project layout

```
supabase/
  migrations/        Database tables, access rules, triggers (versioned)
  seed-data/         catalog.yaml (edit this) and sample-people.yaml
  seed.sql           Generated from catalog.yaml
  sample-data.sql    Generated from sample-people.yaml
scripts/             build-seed.ts, run-sql.ts
src/app/             Pages
src/components/      Shared UI (brand mark, form pieces)
tests/db/            Access-rule and data tests
docs/                PLAN.md, SEED-REVIEW.md
```
