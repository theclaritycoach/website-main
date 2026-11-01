# CCE Talent Network: Build Plan (draft for approval)

Status: **approved 2026-11-01.** Slices 0 and 1 are done.

### Answers that shaped this plan (2026-11-01)

- Separate repo: `cce-talent-network`
- Brand colors: CCE Visual Brand Kit v1.0. Sunbeam `#FCCA03` is the primary accent (the old gold is retired)
- Supabase: free tier, with a daily keep-alive job
- No Cloudflare account, so spam protection uses a honeypot, a minimum fill time, and rate limits. Turnstile can be added later (free) if spam shows up
- DNS for partnerwithcce.com is at Squarespace
- Sender: talent@partnerwithcce.com
- First admin: precious@theclaritycoach.co
- Firm team invites go out only when an admin clicks "Send invites"
- Everyone, including current consultants, goes through the new application. No CSV import or manual add
- Working name stays "CCE Talent Network"

---

## 1. Build order recommendation

**Order: schema and seed data first, then intake (Phase 1), then the admin backend (Phase 2).** A bare-bones admin profile page ships at the end of Phase 1 so the link in the Slack alert has somewhere to go.

Why intake goes first:

1. **It's the piece that faces the market.** The form can start collecting applicants while I build the backend. Every week it's live is a week of data you'd otherwise wait for.
2. **Resume extraction is the riskiest piece.** It involves the AI call, file parsing, timeouts, cost, and the fallback path. Building it first means we find problems while they're cheap to fix.
3. **The backend is more useful with real data in it.** Filters and dashboards are easier to judge when real records sit behind them. The 10 labeled fake applicants cover testing until real ones arrive.

Your current people apply through the same form, so there's no import step to wait for.

### Slices (each ends with "here's what to click to test it")

| # | Slice | You can test |
|---|---|---|
| 0 ✅ | Project setup: Next.js, Tailwind, Supabase migrations, seed file, `.env.example`, README, DECISIONS.md | App runs locally; seeded tables visible in Supabase |
| 1 ✅ | Schema + RLS + seed (practices, roles, skills, certs, options, statuses, 10 fake people) | Review `docs/SEED-REVIEW.md` |
| 2 | Public form, manual path only (steps 2 to 11, local save, review, submit, confirmation) | Fill out the whole form on your phone without a resume |
| 3 | Resume upload + text extraction + Claude extraction + prefill + fallback | Upload a PDF, a DOCX, and an image-only PDF |
| 4 | Confirmation email (Resend) + Slack ping + Slack failure alerts + rate limiting + honeypot spam check | Submit and watch your inbox and Slack |
| 5 | Admin login (allowlist) + minimal profile page + resume signed URL + RLS tests | Try opening a resume while logged out (it should fail) |
| 6 | Firm/Team path + team member invite links (sent when you click "Send invites") | Apply as a firm, send invites, open an invite link |
| 7 | "Update my profile" magic link | Request a link and edit availability |
| 8 | Deploy to Netlify + `talent.partnerwithcce.com` DNS walkthrough (Squarespace) + daily keep-alive job | **Phase 1 done** |
| 9 | Talent pool table, combined filters, full-text search, saved filters, CSV export | Run the "AI architects, 5+ years, available in 30 days" search |
| 10 | Profile view: assigned roles, status changes + history, notes, tags, scorecards, onboarding checklist, changed-field markers | Move a fake applicant through statuses |
| 11 | Projects + shortlists + export | Shortlist people onto a fake RFP |
| 12 | Overview dashboard + suggested skills queue + retention/deletion jobs | **Phase 2 done** |

---

## 2. Stack (confirmed, with two adjustments)

- **Next.js (App Router) + TypeScript + Tailwind** on **Netlify** (free tier)
- **Supabase**: Postgres, Auth (magic links), Storage (private buckets), RLS, scheduled jobs (`pg_cron`)
- **Claude API** for resume extraction only, using Claude's smallest, fastest model tier (Haiku)
- **Resend** for the one confirmation email (free tier)
- **Slack incoming webhook** for alerts (free)
- **Spam protection:** honeypot field, minimum time to fill, and rate limits (Cloudflare Turnstile can be added later for free)

**Adjustment 1: where extraction runs.** Netlify's standard functions have a short time limit. Reading a resume with AI can occasionally take longer than that. I plan to run the extraction step as a **Supabase Edge Function**, which allows a longer run time on the free tier. The browser never talks to Claude directly either way. I'll confirm the exact limits on both platforms during slice 3 and log the result in DECISIONS.md.

**Adjustment 2: everything editable lives in data.** Practices, roles, skills, certifications, statuses, scorecard criteria, onboarding steps, and every dropdown list (industries, client types, tools, engagement types, hours ranges, "how did you hear") live in database tables loaded from one seed file (`supabase/seed/*.sql` or a JSON/YAML file that generates it). Nothing is hard-coded in components.

---

## 3. Costs

### Resume extraction (the only paid piece)

Haiku-tier pricing at the time of writing: **$0.10 per million input tokens, $0.50 per million output tokens** (for requests under 100K tokens, which every resume will be).

| Per resume | Tokens (estimate) | Cost |
|---|---|---|
| Input: instructions + our skills/certs catalog + resume text | ~8,000 | ~$0.0008 |
| Output: structured JSON + the model's internal reasoning | ~5,000 | ~$0.0025 |
| **Total per resume** | | **~$0.003 to $0.004** |
| **Per 100 applicants** | | **~$0.35** |
| Per 100, worst case (long resumes, every one retried once) | | **~$1.00** |

Guardrails: per-IP and per-email rate limits, a hard monthly spend limit set in the Anthropic console, and token counts plus cost logged on every extraction so you can see actual spend in the backend.

### Supabase free tier: pausing

Supabase pauses free projects after **7 days without activity**. A paused project means the public form stops working. Options:

| Option | Monthly cost | Notes |
|---|---|---|
| **A. Keep-alive ping** | $0 | A scheduled job (GitHub Actions or a Netlify scheduled function) runs a tiny database query daily. I'd pair it with a daily health check that posts to Slack if the form's backend stops responding. Risk: it's a workaround, so if Supabase changes how it detects activity, it could stop working. Free tier also has small limits (500 MB database, about 1 GB file storage) and fewer backup options. |
| **B. Supabase Pro** | $25 | No pausing, 8 GB database, 100 GB file storage, backups. |

**Decision:** Option A (free tier with keep-alive). Revisit Pro before promoting the form widely or once the database holds data you can't afford to lose.

### Resend free tier

3,000 emails per month, capped at **100 per day**. You'd only use it for confirmation emails (and later the update-profile links), so you'd need 100 applications in one day to hit the cap. If the cap is hit, the email fails, the application still saves, and Slack gets an alert. Requires adding DNS records for `partnerwithcce.com` to verify the sending domain.

### Everything else

Netlify, Slack webhook: $0. **Nothing else that costs money gets added without asking you first.**

---

## 4. Database schema

Conventions: every table has `id uuid`, `created_at`, `updated_at`. Fake seed records carry `is_sample = true` so one command deletes them before launch.

### Reference data (editable lists)

| Table | Key fields |
|---|---|
| `practices` | name, slug, sort, is_cross_practice |
| `roles` | practice_id, name, slug, description, sort, active |
| `skills` | name, slug, category (shared / role), active |
| `role_skills` | role_id, skill_id (a skill can belong to many roles; shared skills link to every role) |
| `certifications` | name, issuer, code, tier (baseline / role_recommended / specialist), official_url, approx_cost, last_verified, **needs_verification (all seeded = true)**, display_priority |
| `certification_roles`, `certification_practices` | links |
| `option_sets` | set_key (industries, client_types, tools, engagement_types, hours_ranges, hear_about, business_certs, ai_usage_freq...), value, label, sort, active |
| `statuses` | key, label, sort, is_terminal, description (Phase 3 email triggers will key off these) |
| `scorecard_criteria` | scorecard_type (application_review / post_call), label, sort |
| `onboarding_step_templates` | label, sort |
| `settings` | key/value: retention_months (24), draft_resume_days (30), refresh_reminder_days (90), public_domain |

### People and applications

| Table | Key fields |
|---|---|
| `people` | email (unique, case-insensitive; the duplicate match key), name, phone, city, state, time_zone, linkedin_url, website_url, applicant_type (individual / firm_contact / firm_member), firm_id, hear_about, referrer_name, ref_code, utm (json), total_years, consulting_years, gov_sub (bool + details), industries[], client_types[], ai_usage_freq, ai_story, hours_range, earliest_start, engagement_types[], work_settings[], travel_frequency, rate_min, rate_max (admin-only), operating_as, entity_name, w9, insurance, nda_ok, conflict (bool + details), ai_cert_commitment, fit answers (3), **status**, last_profile_update_at, email_prefs (json), enthryve_contact_id, resume_text, search_vector, is_sample |
| `applications` | person_id, submitted_at, **extracted (json: what the AI found)**, **confirmed (json: what the applicant submitted)**, changed_fields[], source (public_form / admin_add / csv_import / profile_update). Each re-application adds a row; the person record updates in place. |
| `application_drafts` | draft token, email (if known), resume path, extraction result, created_at, submitted (bool). Unsubmitted drafts and their resumes are deleted after 30 days. |
| `extraction_runs` | draft/person, status (ok / failed / timeout / refused), input/output tokens, cost, error, duration |
| `person_practices` | person_id, practice_id, rank (primary / secondary) |
| `person_roles` | person_id, role_id, **kind (self_qualified / aspiration / assigned)**, assigned_by, assigned_at. Self-selected and admin-assigned roles stay separate and are filterable separately. |
| `person_skills` | person_id, skill_id, proficiency (1 to 4), source (resume / applicant / admin), ai_suggested_proficiency, evidence |
| `person_tools` | person_id, option value, other_text |
| `work_history` | person_id, company, title, start_month, start_year, end_month, end_year, is_current, industry, description, from_resume, changed_by_applicant. Years per company are calculated. |
| `education` | person_id, school, degree, field, year |
| `person_certifications` | person_id, certification_id (nullable), name_text, issuer, year_earned, expires_on, credential_url, state (earned / in_progress), target_date |
| `person_pathways` | person_id, role_id (development pathways of interest) |
| `person_files` | person_id, kind (resume / work_sample / capability_statement), storage_path, mime, size. Private buckets, signed URLs only. |
| `suggested_skills` | raw_name, normalized, times_seen, sample_evidence, state (pending / approved / merged / ignored), merged_into_skill_id |

### Firms

| Table | Key fields |
|---|---|
| `firms` | name, website, team_size, years_in_business, services (role ids), business_certs[], capability_statement_path, primary_contact_person_id |
| `firm_invites` | firm_id, name, email, role_text, token, sent_at, accepted_person_id |

### Admin

| Table | Key fields |
|---|---|
| `admins` | email, user_id, active. The allowlist that RLS checks. |
| `status_history` | person_id, from_status, to_status, changed_by, note, changed_at. **Written by a database trigger**, so no status change can skip the log. |
| `notes` | person_id, author_id, body, created_at |
| `tags`, `person_tags` | name; links |
| `scorecards`, `scorecard_ratings` | person_id, type, author, created_at; criterion_id, rating 1 to 4, comment |
| `person_onboarding_steps` | person_id, template_id, done, done_at, done_by |
| `projects` | name, client, practice_id, type (client_engagement / rfp_bid), start/end, status |
| `project_roles_needed` | project_id, role_id, count |
| `shortlists` | project_id, person_id, proposed_role_id, state (shortlisted / confirmed / declined) |
| `saved_filters` | name, owner, filter json |
| `deletion_log` | deleted_at, deleted_by, reason. Stores no personal data. |
| `error_log` | where, record ref, message, context |

### Future-ready (cheap to create now, no UI)

`members` (person_id, auth_user_id), `opportunities`, `trainings` (external link or internal course), `training_progress`. Phase 3 email hangs off `status_history` + `people.email_prefs`.

### Access rules (RLS)

- **Public (not logged in):** can read reference lists only. Cannot read any person, file, or note. Submissions go through server routes that validate everything first.
- **Applicants (magic link):** never touch tables directly. The update-profile page talks to a server route that only accepts their own record and only the editable fields. They never see status, notes, scores, or assigned roles.
- **Admins:** full read/write, checked against the `admins` allowlist inside the database.
- Automated tests try each of these from the wrong side and confirm they fail.

---

## 5. Pages

**Public** (`talent.partnerwithcce.com`)
- `/` Landing: what the network is, practices, how it works, Apply button, tagline
- `/apply` 11-step application (resume first), progress bar, local autosave, review step
- `/apply/confirmation`
- `/join/[token]` Firm team member invite (same flow, linked to firm)
- `/update` Request an update-my-profile link, then `/update/profile`
- `/privacy` Privacy note

**Admin** (`/admin`, magic link + allowlist)
- `/admin` Overview dashboard
- `/admin/talent` Talent pool (filters, search, saved filters, export, add to shortlist)
- `/admin/people/[id]` Profile
- `/admin/firms/[id]` Firm with its people
- `/admin/projects` and `/admin/projects/[id]`
- `/admin/suggested-skills` Review queue

---

## 6. AI rules built into the design

- AI fills in fields. It never scores, ranks, filters, or rejects. No fit score exists anywhere in the schema.
- Applicants are told AI reads their resume, on the upload step and in the privacy note.
- Resume text is passed to Claude as data inside clearly marked tags, with instructions to ignore anything in it that looks like an instruction. Output must match a strict JSON schema, and the server validates it again before using it.
- Both versions (extracted and confirmed) are stored; changed fields are flagged for admins.
- On any failure (unreadable file, image-only PDF, timeout, refusal, bad JSON) the applicant sees the plain-language message, lands on the same steps in manual mode, and Slack gets an alert.
