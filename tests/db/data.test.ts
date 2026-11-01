/**
 * Status history logging, search, and seed data integrity.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { admin, as, createTestDatabase, dropTestDatabase, ADMIN_EMAIL } from "./helpers";

const DB = "cce_test_data";
const enabled = !!process.env.TEST_DATABASE_URL;
const root = join(__dirname, "..", "..");
let url = "";

beforeAll(async () => {
  if (enabled) url = await createTestDatabase(DB);
}, 60_000);
afterAll(async () => {
  if (enabled) await dropTestDatabase(DB);
});

describe.skipIf(!enabled)("status history", () => {
  it("every person has at least one history entry", async () => {
    const r = await as(url, admin, (c) =>
      c.query(`select count(*)::int as n from public.people p where not exists (select 1 from public.status_history h where h.person_id = p.id)`),
    );
    expect(r.rows[0].n).toBe(0);
  });

  it("logs from and to when a status changes", async () => {
    const r = await as(url, admin, (c) =>
      c.query(`select h.from_status, h.to_status from public.status_history h
               join public.people p on p.id = h.person_id
               where p.email = 'maya.okafor@example.com' order by h.changed_at, h.from_status nulls first`),
    );
    expect(r.rows).toEqual([
      { from_status: null, to_status: "applied" },
      { from_status: "applied", to_status: "qualified_awaiting_assignment" },
    ]);
  });

  it("change_status records who did it and the note", async () => {
    const row = await as(url, admin, async (c) => {
      const p = await c.query(`select id from public.people where email = 'jordan.lee@example.com'`);
      await c.query(`select public.change_status($1, 'under_review', 'Strong PM background')`, [p.rows[0].id]);
      const h = await c.query(
        `select from_status, to_status, note, changed_by_email from public.status_history where person_id = $1 order by changed_at desc, from_status desc nulls last limit 1`,
        [p.rows[0].id],
      );
      return h.rows[0];
    });
    expect(row).toEqual({
      from_status: "applied",
      to_status: "under_review",
      note: "Strong PM background",
      changed_by_email: ADMIN_EMAIL,
    });
  });

  it("does not log when the status stays the same", async () => {
    const counts = await as(url, admin, async (c) => {
      const p = await c.query(`select id from public.people where email = 'jordan.lee@example.com'`);
      const before = (await c.query(`select count(*)::int n from public.status_history where person_id = $1`, [p.rows[0].id])).rows[0].n;
      await c.query(`update public.people set status = 'applied', city = 'Bethesda' where id = $1`, [p.rows[0].id]);
      const after = (await c.query(`select count(*)::int n from public.status_history where person_id = $1`, [p.rows[0].id])).rows[0].n;
      return { before, after };
    });
    expect(counts.after).toBe(counts.before);
  });

  it("rejects a status that isn't in the statuses list", async () => {
    await expect(
      as(url, admin, (c) => c.query(`update public.people set status = 'hired' where email = 'jordan.lee@example.com'`)),
    ).rejects.toThrow(/foreign key/);
  });

  it("one person per email, regardless of capitalization", async () => {
    await expect(
      as(url, admin, (c) => c.query(`insert into public.people (email, full_name) values ('Maya.Okafor@Example.com', 'Dup')`)),
    ).rejects.toThrow(/duplicate key/);
  });
});

describe.skipIf(!enabled)("search", () => {

  const find = (term: string) =>
    as(url, admin, (c) =>
      c.query(`select email from public.people where search_vector @@ websearch_to_tsquery('english', $1) order by email`, [term]),
    ).then((r) => r.rows.map((x) => x.email));

  it("finds people by company", async () => {
    expect(await find("Meridian Insurance")).toEqual(["marcus.bennett@example.com", "maya.okafor@example.com"]);
  });

  it("finds people by skill", async () => {
    expect(await find("RAG")).toEqual(["maya.okafor@example.com"]);
  });

  it("updates when work history changes", async () => {
    const r = await as(url, admin, async (c) => {
      await c.query(`insert into public.work_history (person_id, company) select id, 'Zephyrine Robotics' from public.people where email = 'jordan.lee@example.com'`);
      return c.query(`select email from public.people where search_vector @@ websearch_to_tsquery('english', 'Zephyrine')`);
    });
    expect(r.rows.map((x) => x.email)).toEqual(["jordan.lee@example.com"]);
  });

  it("supports the Phase 2 target search with sample data", async () => {
    // AI Solutions Architect skills at Advanced (3) or higher, 5+ years, available within 30 days
    const r = await as(url, admin, (c) =>
      c.query(`
        select distinct p.email from public.people p
        join public.person_skills ps on ps.person_id = p.id and ps.proficiency >= 3
        join public.role_skills rs on rs.skill_id = ps.skill_id
        join public.roles r on r.id = rs.role_id and r.slug = 'ai-solutions-architect'
        join public.skills s on s.id = ps.skill_id and not s.is_shared
        where p.total_years >= 5 and p.earliest_start <= current_date + 30
        order by p.email`),
    );
    expect(r.rows.map((x) => x.email)).toEqual(["maya.okafor@example.com"]);
  });
});

describe.skipIf(!enabled)("seed data", () => {

  it("has the 26 roles across 3 practices plus cross-practice", async () => {
    const r = await as(url, admin, (c) =>
      c.query(`select p.slug, count(r.id)::int n from public.practices p join public.roles r on r.practice_id = p.id group by p.slug order by p.slug`),
    );
    expect(r.rows).toEqual([
      { slug: "ai-automation", n: 11 },
      { slug: "cross-practice", n: 4 },
      { slug: "people-workforce", n: 6 },
      { slug: "strategy-transformation", n: 5 },
    ]);
  });

  it("marks every seeded certification as needing verification", async () => {
    const r = await as(url, admin, (c) => c.query(`select count(*)::int n from public.certifications where not needs_verification`));
    expect(r.rows[0].n).toBe(0);
  });

  it("links shared skills to every role", async () => {
    const r = await as(url, admin, (c) =>
      c.query(`select count(*)::int n from public.roles r cross join public.skills s
               where s.is_shared and not exists (select 1 from public.role_skills rs where rs.role_id = r.id and rs.skill_id = s.id)`),
    );
    expect(r.rows[0].n).toBe(0);
  });

  it("can be applied again without errors or duplicates", async () => {
    const counts = await as(url, { kind: "owner" }, async (c) => {
      const before = (await c.query(`select (select count(*) from public.skills)::int s, (select count(*) from public.role_skills)::int rs`)).rows[0];
      const sql = readFileSync(join(root, "supabase/seed.sql"), "utf8").replace(/^begin;$/m, "").replace(/^commit;$/m, "");
      await c.query(sql);
      const after = (await c.query(`select (select count(*) from public.skills)::int s, (select count(*) from public.role_skills)::int rs`)).rows[0];
      return { before, after };
    });
    expect(counts.after).toEqual(counts.before);
  });

  it("sample data is fully removable", async () => {
    const n = await as(url, { kind: "owner" }, async (c) => {
      const sql = readFileSync(join(root, "supabase/remove-sample-data.sql"), "utf8").replace(/^begin;$/m, "").replace(/^commit;$/m, "");
      await c.query(sql);
      return (await c.query(`select (select count(*) from public.people)::int + (select count(*) from public.firms)::int as n`)).rows[0].n;
    });
    expect(n).toBe(0);
  });
});
