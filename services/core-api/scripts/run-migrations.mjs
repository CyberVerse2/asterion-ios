import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import pg from "pg";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  throw new Error("DATABASE_URL is required.");
}

const migrationsDirectory = fileURLToPath(new URL("../drizzle/", import.meta.url));
const migrationFiles = (await readdir(migrationsDirectory))
  .filter((file) => file.endsWith(".sql"))
  .sort();

// Openship recreates Postgres a few seconds after the api container starts, so
// keep retrying the connection for a minute; SQL errors still fail immediately.
const connectAttempts = 30;
const connectRetryDelayMs = 2000;

async function connect() {
  for (let attempt = 1; ; attempt += 1) {
    const candidate = new pg.Client({ connectionString: databaseUrl });
    try {
      await candidate.connect();
      return candidate;
    } catch (error) {
      await candidate.end().catch(() => {});
      if (attempt >= connectAttempts) {
        throw error;
      }
      console.log(
        `Database not reachable (${error.code ?? error.message}); retrying in ${connectRetryDelayMs / 1000}s (${attempt}/${connectAttempts}).`
      );
      await new Promise((resolve) => setTimeout(resolve, connectRetryDelayMs));
    }
  }
}

const client = await connect();

try {
  await client.query(`
    CREATE TABLE IF NOT EXISTS "asterion_schema_migrations" (
      "name" text PRIMARY KEY NOT NULL,
      "applied_at" timestamp with time zone DEFAULT now() NOT NULL
    )
  `);

  for (const migrationFile of migrationFiles) {
    const existing = await client.query(
      'SELECT 1 FROM "asterion_schema_migrations" WHERE "name" = $1',
      [migrationFile]
    );

    if (existing.rowCount) {
      console.log(`Skipping ${migrationFile}; already applied.`);
      continue;
    }

    const sql = await readFile(path.join(migrationsDirectory, migrationFile), "utf8");

    await client.query("BEGIN");
    try {
      await client.query(sql);
      await client.query(
        'INSERT INTO "asterion_schema_migrations" ("name") VALUES ($1)',
        [migrationFile]
      );
      await client.query("COMMIT");
      console.log(`Applied ${migrationFile}.`);
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    }
  }
} finally {
  await client.end();
}
