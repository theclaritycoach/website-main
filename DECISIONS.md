# Decisions Log

Plain-language record of choices made while building the CCE Talent Network, and why.

## 2026-11-01: Planning

1. **Build order: schema, then intake, then backend.** The form starts collecting applicants while the backend is built, and the riskiest piece (resume extraction) gets tested first. A minimal admin profile page ships with Phase 1 so the Slack link works. (Pending approval.)
2. **Resume extraction uses Claude's smallest, fastest model tier (Haiku).** Estimated cost is about $0.003 to $0.004 per resume, or about $0.35 per 100 applicants. Reading and organizing a resume doesn't need a larger model.
3. **Extraction runs in a Supabase Edge Function, not a Netlify function.** Netlify's standard functions have a short time limit, and an AI read can run past it. To be confirmed in testing.
4. **Status history is written by a database trigger.** That way no code path can change a status without logging it, which Phase 3 emails will depend on.
5. **Self-selected roles and admin-assigned roles share one table with a `kind` column.** It keeps filtering simple ("show me assigned AI Solutions Architects") while keeping the two clearly separate.
6. **One person per email.** Re-applications add a new row to `applications` (with both the AI and confirmed versions) and update the person record in place.
7. **Applicants never get direct database access.** Their profile updates go through a server route that only allows their own record and editable fields. This keeps RLS simple: public sees reference lists, admins see everything, nobody else sees people data.
8. **All fake seed data is flagged `is_sample = true`** so it can be removed with one command before launch.
