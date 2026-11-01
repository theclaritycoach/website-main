# Decisions Log

Plain-language record of choices made while building the CCE Talent Network, and why.

## 2026-11-01: Planning

1. **Build order: schema, then intake, then backend.** The form starts collecting applicants while the backend is built, and the riskiest piece (resume extraction) gets tested first. A minimal admin profile page ships with Phase 1 so the Slack link works. (Approved.)
2. **Resume extraction uses Claude's smallest, fastest model tier (Haiku).** Estimated cost is about $0.003 to $0.004 per resume, or about $0.35 per 100 applicants. Reading and organizing a resume doesn't need a larger model.
3. **Extraction runs in a Supabase Edge Function, not a Netlify function.** Netlify's standard functions have a short time limit, and an AI read can run past it. To be confirmed in testing.
4. **Status history is written by a database trigger.** That way no code path can change a status without logging it, which Phase 3 emails will depend on.
5. **Self-selected roles and admin-assigned roles share one table with a `kind` column.** It keeps filtering simple ("show me assigned AI Solutions Architects") while keeping the two clearly separate.
6. **One person per email.** Re-applications add a new row to `applications` (with both the AI and confirmed versions) and update the person record in place.
7. **Applicants never get direct database access.** Their profile updates go through a server route that only allows their own record and editable fields. This keeps RLS simple: public sees reference lists, admins see everything, nobody else sees people data.
8. **All fake seed data is flagged `is_sample = true`** so it can be removed with one command before launch.

## 2026-11-01: Answers from Precious, and slices 0 to 1

9. **Separate repository (`cce-talent-network`).** The work started on a branch of `website-main`, which was empty, so the full history moves over to the new repository cleanly.
10. **Brand colors come from CCE Visual Brand Kit v1.0.** The old gold (`#C9A02C`) is retired in that kit, so the site uses Sunbeam `#FCCA03` as the accent. Sunbeam is never used as text on white, because it fails contrast; it appears as rules, dots, and highlights. Buttons and links use Violet `#5B4BFF`, per the kit. Fonts are Manrope and Space Mono.
11. **The CCE mark is live text** ("CCE" with a Sunbeam period on a black tile) until a final logo file is confirmed. One component (`src/components/brand-mark.tsx`) swaps it everywhere.
12. **Supabase free tier, with a daily keep-alive job.** The same daily job will also delete expired drafts and apply the retention rules, so one scheduled task does all the housekeeping.
13. **Spam protection without Cloudflare:** a hidden honeypot field, a minimum time-to-fill check, and rate limits per IP and per email. Turnstile can be added later if spam gets through.
14. **No CSV import or manual "Add person."** Everyone, including current consultants, applies through the same form. That keeps every record complete and consistent.
15. **Firm invites are sent only when an admin clicks "Send invites."** Invite links are created at submission but sit unsent (`firm_invites.sent_at` stays empty) until then.
16. **The catalog lives in one YAML file** (`supabase/seed-data/catalog.yaml`). A script checks it and turns it into database updates. Removing an item hides it rather than deleting it, so people who picked it keep their history.
17. **Seeded certifications have no prices yet.** Prices change, and a wrong price is worse than a blank. Every certification is flagged `needs_verification` until you confirm it.
18. **Placeholder certifications for cloud associates.** Your brief said "AWS, Azure, or Google Cloud associate-level credentials" without naming specific ones, so these are generic entries until you pick the exact credentials.
19. **Some general credentials in the brief became specific entries.** "Agile/Scrum" became CSM and PSM I. "ATD credentials" became APTD and CPTD. "ICF credentials" became ACC, PCC, and MCC. "SHRM credentials" became SHRM-CP and SHRM-SCP. "Lean Six Sigma" became Green Belt and Black Belt. The advanced levels (CPTD, MCC, SHRM-SCP, Black Belt, and Claude Certified Architect Professional) sit at the specialist tier. Delete any you don't want from the YAML.
20. **Sample people work at fictional companies.** That avoids attaching made-up people to real employers while still exercising the company search.
21. **Access rules are tested on every run.** The tests check that every table has RLS on, that anonymous visitors and logged-in non-admins see zero rows of people data, and that a deactivated admin loses access immediately.
