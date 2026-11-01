/**
 * Test helpers: build a fresh database from the migrations + seed, and run
 * queries as different kinds of visitors (anonymous, a logged-in non-admin,
 * an admin, or the server's service role).
 *
 * Needs a Postgres server. Set TEST_DATABASE_URL to a superuser connection,
 * e.g. postgres://postgres@localhost:54329/postgres
 */
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { Client } from "pg";

const root = join(__dirname, "..", "..");

export const ADMIN_EMAIL = "precious@theclaritycoach.co";
export const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
export const OUTSIDER_EMAIL = "someone@example.org";
export const OUTSIDER_ID = "22222222-2222-4222-8222-222222222222";

export function adminUrl(): string {
  const url = process.env.TEST_DATABASE_URL;
  if (!url) throw new Error("Set TEST_DATABASE_URL to run database tests (see README, Testing).");
  return url;
}

export async function createTestDatabase(name: string): Promise<string> {
  const admin = new Client({ connectionString: adminUrl() });
  await admin.connect();
  await admin.query(`drop database if exists ${name} with (force)`);
  await admin.query(`create database ${name}`);
  await admin.end();

  const url = new URL(adminUrl());
  url.pathname = `/${name}`;
  const db = new Client({ connectionString: url.toString() });
  await db.connect();
  await db.query(readFileSync(join(root, "tests/db/supabase-shim.sql"), "utf8"));
  const migrationsDir = join(root, "supabase/migrations");
  for (const f of readdirSync(migrationsDir).filter((f) => f.endsWith(".sql")).sort()) {
    await db.query(readFileSync(join(migrationsDir, f), "utf8"));
  }
  await db.query(readFileSync(join(root, "supabase/seed.sql"), "utf8"));
  await db.query(readFileSync(join(root, "supabase/sample-data.sql"), "utf8"));
  await db.end();
  return url.toString();
}

export async function dropTestDatabase(name: string) {
  const admin = new Client({ connectionString: adminUrl() });
  await admin.connect();
  await admin.query(`drop database if exists ${name} with (force)`);
  await admin.end();
}

export type Actor =
  | { kind: "anon" }
  | { kind: "user"; id: string; email: string }
  | { kind: "service" }
  | { kind: "owner" };

/**
 * Runs `fn` inside a transaction as the given actor, then rolls back so
 * tests never affect each other.
 */
export async function as<T>(url: string, actor: Actor, fn: (c: Client) => Promise<T>): Promise<T> {
  const c = new Client({ connectionString: url });
  await c.connect();
  try {
    await c.query("begin");
    if (actor.kind === "anon") {
      await c.query("set local role anon");
      await c.query(`select set_config('request.jwt.claims', '{"role":"anon"}', true)`);
    } else if (actor.kind === "user") {
      await c.query("set local role authenticated");
      await c.query(`select set_config('request.jwt.claims', $1, true)`, [
        JSON.stringify({ sub: actor.id, email: actor.email, role: "authenticated" }),
      ]);
    } else if (actor.kind === "service") {
      await c.query("set local role service_role");
    }
    return await fn(c);
  } finally {
    await c.query("rollback").catch(() => {});
    await c.end();
  }
}

export const admin: Actor = { kind: "user", id: ADMIN_ID, email: ADMIN_EMAIL };
export const outsider: Actor = { kind: "user", id: OUTSIDER_ID, email: OUTSIDER_EMAIL };
export const anon: Actor = { kind: "anon" };
export const service: Actor = { kind: "service" };
