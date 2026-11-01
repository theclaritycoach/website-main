/**
 * Access rules (RLS). These are the tests that prove applicant data can't be
 * read without admin login. If any of these fail, do not deploy.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { admin, anon, as, createTestDatabase, dropTestDatabase, outsider, service, ADMIN_EMAIL } from "./helpers";

const DB = "cce_test_security";
const enabled = !!process.env.TEST_DATABASE_URL;
let url = "";

const REFERENCE_TABLES = [
  "practices", "roles", "skills", "role_skills",
  "certifications", "certification_roles", "certification_practices", "option_sets",
];

// Tables that hold people data or admin-only data. Sample data guarantees most have rows.
const PRIVATE_TABLES = [
  "people", "person_practices", "person_roles", "person_skills", "work_history",
  "person_certifications", "status_history", "firms", "firm_services", "admins",
  "settings", "statuses", "applications", "application_drafts", "person_files",
  "notes", "scorecards", "projects", "shortlists", "deletion_log", "error_log",
  "suggested_skills", "firm_invites", "members", "rate_limits", "extraction_runs",
];

describe.skipIf(!enabled)("access rules (RLS)", () => {
  beforeAll(async () => {
    url = await createTestDatabase(DB);
  }, 60_000);
  afterAll(async () => {
    if (enabled) await dropTestDatabase(DB);
  });

  it("every table in the public schema has RLS turned on", async () => {
    const rows = await as(url, { kind: "owner" }, (c) =>
      c.query(`select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity`),
    );
    expect(rows.rows.map((r) => r.relname)).toEqual([]);
  });

  it.each(REFERENCE_TABLES)("anyone can read the reference list %s", async (t) => {
    const r = await as(url, anon, (c) => c.query(`select count(*)::int as n from public.${t}`));
    expect(r.rows[0].n).toBeGreaterThan(0);
  });

  it.each(PRIVATE_TABLES)("anonymous visitors see nothing in %s", async (t) => {
    const r = await as(url, anon, (c) => c.query(`select count(*)::int as n from public.${t}`));
    expect(r.rows[0].n).toBe(0);
  });

  it.each(PRIVATE_TABLES)("a logged-in non-admin sees nothing in %s", async (t) => {
    const r = await as(url, outsider, (c) => c.query(`select count(*)::int as n from public.${t}`));
    expect(r.rows[0].n).toBe(0);
  });

  it("anonymous visitors cannot write people records", async () => {
    await expect(
      as(url, anon, (c) => c.query(`insert into public.people (email, full_name) values ('x@example.com', 'X')`)),
    ).rejects.toThrow(/row-level security/);
  });

  it("anonymous visitors cannot change reference lists", async () => {
    await expect(
      as(url, anon, (c) => c.query(`insert into public.skills (slug, name) values ('hack', 'Hack')`)),
    ).rejects.toThrow(/row-level security/);
  });

  it("a logged-in non-admin cannot make themselves an admin", async () => {
    await expect(
      as(url, outsider, (c) => c.query(`insert into public.admins (email) values ('someone@example.org')`)),
    ).rejects.toThrow(/row-level security/);
  });

  it("an allowlisted admin can read every sample person", async () => {
    const r = await as(url, admin, (c) => c.query(`select count(*)::int as n from public.people`));
    expect(r.rows[0].n).toBe(10);
  });

  it("an admin can add a note", async () => {
    const r = await as(url, admin, async (c) => {
      const p = await c.query(`select id from public.people limit 1`);
      return c.query(
        `insert into public.notes (person_id, author_email, body) values ($1, $2, 'Strong call') returning id`,
        [p.rows[0].id, ADMIN_EMAIL],
      );
    });
    expect(r.rowCount).toBe(1);
  });

  it("a deactivated admin loses access immediately", async () => {
    const n = await as(url, admin, async (c) => {
      await c.query(`reset role`);
      await c.query(`update public.admins set active = false where email = $1`, [ADMIN_EMAIL]);
      await c.query(`set local role authenticated`);
      return (await c.query(`select count(*)::int as n from public.people`)).rows[0].n;
    });
    expect(n).toBe(0);
  });

  it("only the server can use the rate limiter", async () => {
    await expect(as(url, anon, (c) => c.query(`select public.hit_rate_limit('x', 1, 60)`))).rejects.toThrow(
      /permission denied/,
    );
    const ok = await as(url, service, (c) => c.query(`select public.hit_rate_limit('x', 1, 60) as ok`));
    expect(ok.rows[0].ok).toBe(true);
  });

  it("the rate limiter blocks after the limit", async () => {
    const results = await as(url, service, async (c) => {
      const out: boolean[] = [];
      for (let i = 0; i < 4; i++) out.push((await c.query(`select public.hit_rate_limit('ip:1.2.3.4', 3, 3600) as ok`)).rows[0].ok);
      return out;
    });
    expect(results).toEqual([true, true, true, false]);
  });

  it("a non-admin cannot change anyone's status", async () => {
    await expect(
      as(url, outsider, (c) =>
        c.query(`select public.change_status('00000000-0000-4000-8000-000000000000', 'withdrawn', null)`),
      ),
    ).rejects.toThrow(/Only admins/);
  });
});
