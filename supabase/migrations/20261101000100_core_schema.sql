-- CCE Talent Network: core schema
-- Plain-language notes are in comments. Editable lists (practices, roles, skills,
-- certifications, dropdown options, statuses) are data, loaded from supabase/seed-data.

create extension if not exists citext;
create extension if not exists pg_trgm;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Reference data (the lists you edit)
-- ---------------------------------------------------------------------------

create table public.practices (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  sort int not null default 0,
  is_cross_practice boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practices(id) on delete restrict,
  slug text not null unique,
  name text not null,
  description text,
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.skills (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  is_shared boolean not null default false,  -- shared skills apply to every role
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.role_skills (
  role_id uuid not null references public.roles(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete cascade,
  primary key (role_id, skill_id)
);

create table public.certifications (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  issuer text not null,
  code text,
  tier text not null check (tier in ('baseline', 'role_recommended', 'specialist')),
  official_url text,
  approx_cost text,
  last_verified date,
  needs_verification boolean not null default true,  -- every seeded cert starts unverified
  display_priority int not null default 100,           -- lower shows first (Anthropic first)
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.certification_roles (
  certification_id uuid not null references public.certifications(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  primary key (certification_id, role_id)
);

create table public.certification_practices (
  certification_id uuid not null references public.certifications(id) on delete cascade,
  practice_id uuid not null references public.practices(id) on delete cascade,
  primary key (certification_id, practice_id)
);

-- Every dropdown / checklist on the form that isn't practices, roles, skills or certs.
create table public.option_sets (
  id uuid primary key default gen_random_uuid(),
  set_key text not null,
  value text not null,
  label text not null,
  sort int not null default 0,
  active boolean not null default true,
  unique (set_key, value)
);

create table public.statuses (
  key text primary key,
  label text not null,
  description text,
  sort int not null default 0,
  is_terminal boolean not null default false
);

create table public.scorecard_criteria (
  id uuid primary key default gen_random_uuid(),
  scorecard_type text not null check (scorecard_type in ('application_review', 'post_call')),
  key text not null,
  label text not null,
  sort int not null default 0,
  active boolean not null default true,
  unique (scorecard_type, key)
);

create table public.onboarding_step_templates (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  label text not null,
  sort int not null default 0,
  active boolean not null default true
);

create table public.settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Firms
-- ---------------------------------------------------------------------------

create table public.firms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  website text,
  team_size text,
  years_in_business int,
  business_certs text[] not null default '{}',
  capability_statement_path text,
  primary_contact_person_id uuid,  -- FK added after people exists
  is_sample boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.firm_services (
  firm_id uuid not null references public.firms(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  primary key (firm_id, role_id)
);

-- ---------------------------------------------------------------------------
-- People (one row per human, matched on email)
-- ---------------------------------------------------------------------------

create table public.people (
  id uuid primary key default gen_random_uuid(),
  email citext not null unique,
  full_name text not null,
  phone text,
  city text,
  state text,
  time_zone text,
  linkedin_url text,
  website_url text,

  applicant_type text not null default 'individual'
    check (applicant_type in ('individual', 'firm_contact', 'firm_member')),
  firm_id uuid references public.firms(id) on delete set null,

  -- How they found us
  hear_about text,
  referrer_name text,
  ref_code text,
  utm jsonb not null default '{}',

  -- Experience
  total_years numeric(4,1),
  consulting_years numeric(4,1),
  gov_subcontractor boolean,
  gov_subcontractor_details text,
  industries text[] not null default '{}',
  client_types text[] not null default '{}',

  -- Tools and AI fluency
  tools text[] not null default '{}',
  tools_other text,
  ai_usage_frequency text,
  ai_outcome_story text,

  -- Availability
  hours_per_week text,
  earliest_start date,
  engagement_types text[] not null default '{}',
  work_settings text[] not null default '{}',
  travel_frequency text,
  rate_min numeric(8,2),   -- optional, admin-only (all people data is admin-only)
  rate_max numeric(8,2),

  -- Contractor readiness
  operating_as text,
  entity_name text,
  can_provide_w9 boolean,
  has_liability_insurance text,
  nda_ok boolean,
  has_conflict boolean,
  conflict_details text,

  -- Development commitment
  ai_cert_commitment text,

  -- Fit
  fit_problem text,
  fit_proud_of text,
  fit_why_cce text,

  -- Consent
  consent_accurate boolean not null default false,
  consent_storage boolean not null default false,
  consent_contact boolean not null default false,
  consented_at timestamptz,

  -- Pipeline
  status text not null default 'applied',
  first_submitted_at timestamptz,
  last_submitted_at timestamptz,
  last_profile_update_at timestamptz,

  -- Future-proofing
  email_prefs jsonb not null default '{"status_updates": true, "refresh_reminders": true, "opportunities": true}',
  enthryve_contact_id text,

  -- Search
  resume_text text,
  search_vector tsvector,

  is_sample boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.people
  add constraint people_status_fk foreign key (status) references public.statuses(key);

alter table public.firms
  add constraint firms_primary_contact_fk foreign key (primary_contact_person_id)
  references public.people(id) on delete set null;

create index people_status_idx on public.people (status);
create index people_firm_idx on public.people (firm_id);
create index people_last_update_idx on public.people (last_profile_update_at);
create index people_search_idx on public.people using gin (search_vector);
create index people_industries_idx on public.people using gin (industries);
create index people_engagement_idx on public.people using gin (engagement_types);
create index people_settings_idx on public.people using gin (work_settings);

create table public.person_practices (
  person_id uuid not null references public.people(id) on delete cascade,
  practice_id uuid not null references public.practices(id) on delete restrict,
  rank text not null check (rank in ('primary', 'secondary')),
  primary key (person_id, practice_id),
  unique (person_id, rank)
);

-- Self-selected roles, roles they want to grow into, development pathways of
-- interest, and official CCE roles assigned by an admin all live here, kept
-- apart by `kind`.
create table public.person_roles (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete restrict,
  kind text not null check (kind in ('self_qualified', 'aspiration', 'pathway_interest', 'assigned')),
  assigned_by uuid,
  created_at timestamptz not null default now(),
  unique (person_id, role_id, kind)
);
create index person_roles_lookup_idx on public.person_roles (role_id, kind);

create table public.person_skills (
  person_id uuid not null references public.people(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete restrict,
  proficiency smallint not null check (proficiency between 1 and 4),
  source text not null default 'applicant' check (source in ('resume', 'applicant', 'admin')),
  ai_suggested_proficiency smallint check (ai_suggested_proficiency between 1 and 4),
  evidence text,
  updated_at timestamptz not null default now(),
  primary key (person_id, skill_id)
);
create index person_skills_lookup_idx on public.person_skills (skill_id, proficiency);

create table public.work_history (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  sort int not null default 0,
  company text not null,
  title text,
  start_month smallint check (start_month between 1 and 12),
  start_year smallint,
  end_month smallint check (end_month between 1 and 12),
  end_year smallint,
  is_current boolean not null default false,
  industry text,
  description text,
  from_resume boolean not null default false,
  changed_by_applicant boolean not null default false,
  created_at timestamptz not null default now()
);
create index work_history_person_idx on public.work_history (person_id);
create index work_history_company_trgm_idx on public.work_history using gin (company gin_trgm_ops);

create table public.education (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  school text,
  degree text,
  field text,
  year smallint
);

create table public.person_certifications (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  certification_id uuid references public.certifications(id) on delete set null,
  name_text text not null,
  issuer text,
  year_earned smallint,
  expires_on date,
  credential_url text,
  state text not null default 'earned' check (state in ('earned', 'in_progress')),
  target_date date,
  from_resume boolean not null default false
);
create index person_certs_lookup_idx on public.person_certifications (certification_id, state);

create table public.person_files (
  id uuid primary key default gen_random_uuid(),
  person_id uuid references public.people(id) on delete cascade,
  firm_id uuid references public.firms(id) on delete cascade,
  kind text not null check (kind in ('resume', 'work_sample', 'capability_statement')),
  bucket text not null default 'talent-files',
  storage_path text not null unique,
  original_name text,
  mime_type text,
  size_bytes int,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Applications, drafts, and resume extraction
-- ---------------------------------------------------------------------------

-- A draft exists from the moment a resume is uploaded until submit.
-- Unsubmitted drafts (and their resume files) are deleted after 30 days.
create table public.application_drafts (
  id uuid primary key default gen_random_uuid(),
  email citext,
  firm_invite_id uuid,
  resume_path text,
  resume_text text,
  extraction jsonb,
  extraction_status text check (extraction_status in ('pending', 'ok', 'failed')),
  ip_hash text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  submitted_at timestamptz,
  person_id uuid references public.people(id) on delete set null
);
create index drafts_cleanup_idx on public.application_drafts (created_at) where submitted_at is null;

-- One row per submission. Re-applying adds a row and updates the person in place.
-- `extracted` is what the AI read from the resume; `confirmed` is what the
-- applicant submitted. `changed_fields` lists where they differ.
create table public.applications (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  draft_id uuid references public.application_drafts(id) on delete set null,
  source text not null check (source in ('public_form', 'firm_invite', 'profile_update')),
  extracted jsonb,
  confirmed jsonb not null,
  changed_fields text[] not null default '{}',
  submitted_at timestamptz not null default now()
);
create index applications_person_idx on public.applications (person_id, submitted_at desc);

create table public.extraction_runs (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid references public.application_drafts(id) on delete cascade,
  status text not null check (status in ('ok', 'failed', 'timeout', 'refused', 'invalid_output', 'unreadable')),
  model text,
  input_tokens int,
  output_tokens int,
  cost_usd numeric(10,6),
  duration_ms int,
  error text,
  created_at timestamptz not null default now()
);

-- Skills the AI found that aren't in our master list yet.
create table public.suggested_skills (
  id uuid primary key default gen_random_uuid(),
  normalized text not null unique,
  display_name text not null,
  times_seen int not null default 1,
  sample_evidence text,
  state text not null default 'pending' check (state in ('pending', 'approved', 'merged', 'ignored')),
  merged_into_skill_id uuid references public.skills(id) on delete set null,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.firm_invites (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  full_name text not null,
  email citext not null,
  role_text text,
  token text not null unique default encode(gen_random_bytes(24), 'hex'),
  sent_at timestamptz,     -- stays null until an admin clicks "send invites"
  accepted_person_id uuid references public.people(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (firm_id, email)
);

alter table public.application_drafts
  add constraint drafts_invite_fk foreign key (firm_invite_id) references public.firm_invites(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------

create table public.admins (
  id uuid primary key default gen_random_uuid(),
  email citext not null unique,
  user_id uuid unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.status_history (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  from_status text references public.statuses(key),
  to_status text not null references public.statuses(key),
  changed_by uuid,
  changed_by_email text,
  note text,
  changed_at timestamptz not null default now()
);
create index status_history_person_idx on public.status_history (person_id, changed_at desc);

-- Everything else worth a timeline entry: re-applied, profile updated, invite sent.
create table public.person_events (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  kind text not null,
  detail jsonb not null default '{}',
  actor_email text,
  created_at timestamptz not null default now()
);
create index person_events_person_idx on public.person_events (person_id, created_at desc);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  author_id uuid,
  author_email text,
  body text not null,
  created_at timestamptz not null default now()
);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  name citext not null unique
);

create table public.person_tags (
  person_id uuid not null references public.people(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key (person_id, tag_id)
);

create table public.scorecards (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  scorecard_type text not null check (scorecard_type in ('application_review', 'post_call')),
  author_id uuid,
  author_email text,
  summary text,
  created_at timestamptz not null default now()
);

create table public.scorecard_ratings (
  scorecard_id uuid not null references public.scorecards(id) on delete cascade,
  criterion_id uuid not null references public.scorecard_criteria(id) on delete restrict,
  rating smallint check (rating between 1 and 4),
  comment text,
  primary key (scorecard_id, criterion_id)
);

create table public.person_onboarding_steps (
  person_id uuid not null references public.people(id) on delete cascade,
  template_id uuid not null references public.onboarding_step_templates(id) on delete cascade,
  done boolean not null default false,
  done_at timestamptz,
  done_by_email text,
  note text,
  primary key (person_id, template_id)
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  client text,
  practice_id uuid references public.practices(id) on delete set null,
  project_type text not null check (project_type in ('client_engagement', 'rfp_bid')),
  start_date date,
  end_date date,
  status text not null default 'planning' check (status in ('planning', 'active', 'submitted', 'won', 'lost', 'complete', 'cancelled')),
  description text,
  is_sample boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.project_roles_needed (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete restrict,
  quantity int not null default 1
);

create table public.shortlists (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete cascade,
  proposed_role_id uuid references public.roles(id) on delete set null,
  state text not null default 'shortlisted' check (state in ('shortlisted', 'confirmed', 'declined')),
  note text,
  added_by_email text,
  created_at timestamptz not null default now(),
  unique (project_id, person_id)
);

create table public.saved_filters (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_email text,
  filters jsonb not null,
  created_at timestamptz not null default now()
);

-- Records that a deletion happened. Holds no personal data.
create table public.deletion_log (
  id uuid primary key default gen_random_uuid(),
  deleted_at timestamptz not null default now(),
  deleted_by_email text,
  reason text not null check (reason in ('admin_request', 'retention_policy', 'draft_expired')),
  files_removed int not null default 0
);

create table public.error_log (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  source text not null,
  ref text,
  message text not null,
  context jsonb not null default '{}'
);

create table public.rate_limits (
  bucket text not null,
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (bucket, window_start)
);

-- ---------------------------------------------------------------------------
-- Future member portal (tables only, no UI yet)
-- ---------------------------------------------------------------------------

create table public.members (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null unique references public.people(id) on delete cascade,
  auth_user_id uuid unique,
  created_at timestamptz not null default now()
);

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  project_id uuid references public.projects(id) on delete set null,
  role_id uuid references public.roles(id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'open', 'closed')),
  opens_at timestamptz,
  closes_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.trainings (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind text not null check (kind in ('external_certification', 'internal_course')),
  certification_id uuid references public.certifications(id) on delete set null,
  url text,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.training_progress (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  training_id uuid not null references public.trainings(id) on delete cascade,
  status text not null default 'not_started' check (status in ('not_started', 'in_progress', 'complete')),
  started_at timestamptz,
  completed_at timestamptz,
  unique (person_id, training_id)
);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['practices','roles','skills','certifications','firms','people','projects']
  loop
    execute format('create trigger %I_updated_at before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;
