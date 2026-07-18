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

const client = new pg.Client({ connectionString: databaseUrl });

await client.connect();

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
