-- CCE Talent Network: functions, triggers, and access rules (RLS)

-- ---------------------------------------------------------------------------
-- Who is an admin? Checked inside the database on every request.
-- ---------------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins a
    where a.active
      and (a.user_id = auth.uid() or a.email = (auth.jwt() ->> 'email'))
  );
$$;

-- ---------------------------------------------------------------------------
-- Status history: written by a trigger so no code path can skip it.
-- Phase 3 emails will hang off rows in status_history.
-- ---------------------------------------------------------------------------

create or replace function public.log_status_change()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_note text := nullif(current_setting('app.status_note', true), '');
  v_actor_email text := coalesce(auth.jwt() ->> 'email', nullif(current_setting('app.actor_email', true), ''));
begin
  if tg_op = 'INSERT' then
    insert into public.status_history (person_id, from_status, to_status, changed_by, changed_by_email, note)
    values (new.id, null, new.status, auth.uid(), v_actor_email, v_note);
  elsif new.status is distinct from old.status then
    insert into public.status_history (person_id, from_status, to_status, changed_by, changed_by_email, note)
    values (new.id, old.status, new.status, auth.uid(), v_actor_email, v_note);
  end if;
  return new;
end $$;

create trigger people_status_history
after insert or update of status on public.people
for each row execute function public.log_status_change();

-- Admin-facing way to change a status with a note attached.
create or replace function public.change_status(p_person uuid, p_status text, p_note text default null)
returns void
language plpgsql security invoker
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can change status' using errcode = '42501';
  end if;
  perform set_config('app.status_note', coalesce(p_note, ''), true);
  update public.people set status = p_status where id = p_person;
  if not found then
    raise exception 'Person % not found', p_person;
  end if;
  perform set_config('app.status_note', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- Full-text search across names, companies, titles, descriptions, skills,
-- and raw resume text. Kept up to date by triggers.
-- ---------------------------------------------------------------------------

create or replace function public.refresh_person_search(p_person uuid)
returns void
language sql security definer
set search_path = public
as $$
  update public.people p set search_vector =
      setweight(to_tsvector('english', coalesce(p.full_name, '')), 'A')
   || setweight(to_tsvector('english', coalesce((
        select string_agg(concat_ws(' ', w.company, w.title), ' ')
        from public.work_history w where w.person_id = p.id), '')), 'A')
   || setweight(to_tsvector('english', coalesce((
        select string_agg(s.name, ' ')
        from public.person_skills ps join public.skills s on s.id = ps.skill_id
        where ps.person_id = p.id), '')), 'B')
   || setweight(to_tsvector('english', concat_ws(' ',
        (select string_agg(w.description, ' ') from public.work_history w where w.person_id = p.id),
        p.city, p.state, p.tools_other, p.fit_problem, p.fit_proud_of, p.ai_outcome_story)), 'C')
   || setweight(to_tsvector('english', coalesce(p.resume_text, '')), 'D')
  where p.id = p_person;
$$;

create or replace function public.trg_refresh_search_self()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.refresh_person_search(new.id);
  return null;
end $$;

create or replace function public.trg_refresh_search_child()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.refresh_person_search(coalesce(new.person_id, old.person_id));
  return null;
end $$;

create trigger people_search_refresh
after insert or update of full_name, city, state, tools_other, fit_problem, fit_proud_of, ai_outcome_story, resume_text
on public.people
for each row execute function public.trg_refresh_search_self();

create trigger work_history_search_refresh
after insert or update or delete on public.work_history
for each row execute function public.trg_refresh_search_child();

create trigger person_skills_search_refresh
after insert or update or delete on public.person_skills
for each row execute function public.trg_refresh_search_child();

-- ---------------------------------------------------------------------------
-- Rate limiting for the public form and resume extraction.
-- Returns true if the request is allowed. Server-only.
-- ---------------------------------------------------------------------------

create or replace function public.hit_rate_limit(p_bucket text, p_max int, p_window_seconds int)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  v_window timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  v_hits int;
begin
  insert into public.rate_limits (bucket, window_start, hits)
  values (p_bucket, v_window, 1)
  on conflict (bucket, window_start) do update set hits = public.rate_limits.hits + 1
  returning hits into v_hits;
  return v_hits <= p_max;
end $$;

revoke execute on function public.hit_rate_limit(text, int, int) from public, anon, authenticated;
revoke execute on function public.refresh_person_search(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
--   * Every table: admins (allowlisted) can do everything.
--   * Reference lists: anyone can read (the public form needs them).
--   * Everything else: no access without admin login. The public form writes
--     through server routes that use the service key after validating input.
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy admin_all on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'practices', 'roles', 'skills', 'role_skills',
    'certifications', 'certification_roles', 'certification_practices',
    'option_sets'
  ]
  loop
    execute format('create policy public_read on public.%I for select to anon, authenticated using (true)', t);
  end loop;
end $$;
