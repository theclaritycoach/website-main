/**
 * Runs a .sql file against the database in DATABASE_URL.
 * Used by: npm run seed:apply, npm run sample:load, npm run sample:remove
 *
 * DATABASE_URL is the Postgres connection string from Supabase
 * (Project Settings > Database > Connection string). Keep it in .env.local.
 */
import { readFileSync } from "node:fs";
import { Client } from "pg";

async function main() {
  const file = process.argv[2];
  if (!file) throw new Error("Usage: tsx scripts/run-sql.ts <file.sql>");
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set. Add it to .env.local (see .env.example).");
  const client = new Client({ connectionString: url });
  await client.connect();
  try {
    await client.query(readFileSync(file, "utf8"));
    console.log(`Ran ${file}`);
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
