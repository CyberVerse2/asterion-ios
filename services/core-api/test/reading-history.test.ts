import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import pg from "pg";
import { drizzle } from "drizzle-orm/node-postgres";
import { getTableConfig } from "drizzle-orm/pg-core";
import { readingHistory } from "../src/db/schema";
import {
  collapseReadingHistoryEntries,
  readingHistoryBatchLimit,
  readingHistoryBatchSchema,
} from "../src/lib/reading-history-contract";
import { buildReadingHistoryUpsert } from "../src/lib/reading-history-queries";

const now = new Date("2026-10-16T12:00:00.000Z");

function entry(overrides: Record<string, unknown> = {}) {
  return {
    novelId: "novel-1",
    chapterId: "chapter-1",
    chapterNumber: 1,
    chapterTitle: "Beginnings",
    readAt: "2026-10-16T11:00:00.000Z",
    progress: 40,
    ...overrides,
  };
}

test("history batches validate entries, cap their size, and reject spoofed identity", () => {
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [entry()] }).success, true);
  // Only the ids and read time are required.
  assert.equal(
    readingHistoryBatchSchema.safeParse({
      entries: [{ novelId: "n", chapterId: "c", readAt: "2026-10-16T11:00:00Z" }],
    }).success,
    true
  );
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [] }).success, false);
  assert.equal(
    readingHistoryBatchSchema.safeParse({
      entries: Array.from({ length: readingHistoryBatchLimit + 1 }, (_, index) => entry({ chapterId: `c${index}` })),
    }).success,
    false
  );
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [entry({ readAt: "yesterday" })] }).success, false);
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [entry({ readAt: "1999-12-31T00:00:00Z" })] }).success, false);
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [entry({ progress: 101 })] }).success, false);
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [entry({ chapterNumber: 1.5 })] }).success, false);
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [entry({ userId: "someone-else" })] }).success, false);
  assert.equal(readingHistoryBatchSchema.safeParse({ entries: [entry()], userId: "someone-else" }).success, false);
});

test("a batch collapses to one entry per chapter with the newest read and furthest progress", () => {
  const parsed = readingHistoryBatchSchema.parse({
    entries: [
      entry({ readAt: "2026-10-16T10:00:00Z", progress: 90, chapterTitle: "Old title" }),
      entry({ readAt: "2026-10-16T11:00:00Z", progress: 20, chapterTitle: "New title", chapterNumber: null }),
      entry({ chapterId: "chapter-2", readAt: "2026-10-16T09:00:00Z", progress: undefined }),
      // A device clock running ahead is pulled back to the server's time.
      entry({ chapterId: "chapter-3", readAt: "2026-10-17T09:00:00Z" }),
    ],
  });
  const collapsed = collapseReadingHistoryEntries(parsed.entries, now);
  assert.equal(collapsed.length, 3);

  const first = collapsed.find((row) => row.chapterId === "chapter-1");
  assert.deepEqual(first, {
    novelId: "novel-1",
    chapterId: "chapter-1",
    chapterNumber: 1,
    chapterTitle: "New title",
    readAt: new Date("2026-10-16T11:00:00Z"),
    firstReadAt: new Date("2026-10-16T10:00:00Z"),
    progress: 90,
  });
  assert.equal(collapsed.find((row) => row.chapterId === "chapter-2")?.progress, 0);
  assert.deepEqual(collapsed.find((row) => row.chapterId === "chapter-3")?.readAt, now);
});

test("the schema keeps one history row per user, novel and chapter", () => {
  const unique = getTableConfig(readingHistory).indexes.find(
    (index) => index.config.name === "reading_history_user_chapter_unique"
  );
  assert.ok(unique?.config.unique);
  assert.deepEqual(
    unique.config.columns.map((column) => ("name" in column ? column.name : null)),
    ["user_id", "novel_id", "chapter_id"]
  );
});

test("the history upsert is idempotent and never moves a chapter backwards", () => {
  const database = drizzle.mock();
  const statement = buildReadingHistoryUpsert(database, "user-1", [{
    novelId: "novel-1",
    chapterId: "chapter-1",
    chapterNumber: null,
    chapterTitle: null,
    readAt: now,
    firstReadAt: now,
    progress: 10,
  }], now).toSQL();
  assert.match(statement.sql, /on conflict \("user_id","novel_id","chapter_id"\) do update/);
  assert.match(statement.sql, /greatest\("reading_history"\."visited_at", excluded\.visited_at\)/);
  assert.match(statement.sql, /greatest\("reading_history"\."progress", excluded\.progress\)/);
  assert.match(statement.sql, /coalesce\(excluded\.chapter_number, "reading_history"\."chapter_number"\)/);
  assert.match(statement.sql, /least\("reading_history"\."created_at", excluded\.created_at\)/);
  assert.ok(statement.params.includes("user-1"));
});

// Runs the migration and the upsert against a real database when one is
// given, e.g. TEST_DATABASE_URL=postgres://localhost:5432/postgres. Each run
// works in a throwaway schema.
const databaseUrl = process.env.TEST_DATABASE_URL;

test("migration 0006 collapses duplicate rows and the upsert merges uploads", { skip: !databaseUrl }, async () => {
  const schema = `history_test_${process.pid}_${Date.now()}`;
  const admin = new pg.Client({ connectionString: databaseUrl });
  await admin.connect();
  await admin.query(`CREATE SCHEMA "${schema}"`);
  const client = new pg.Client({ connectionString: databaseUrl, options: `-c search_path=${schema}` });
  await client.connect();
  try {
    // The tables as they were before 0006.
    await client.query(`
      CREATE TABLE "users" ("id" text PRIMARY KEY);
      CREATE TABLE "reading_progress" (
        "id" text PRIMARY KEY, "user_id" text NOT NULL, "novel_id" text NOT NULL,
        "chapter_id" text NOT NULL, "current_line" integer DEFAULT 0 NOT NULL,
        "total_lines" integer DEFAULT 0 NOT NULL, "percentage" double precision DEFAULT 0 NOT NULL,
        "created_at" timestamp DEFAULT now() NOT NULL, "updated_at" timestamp DEFAULT now() NOT NULL
      );
      CREATE TABLE "reading_history" (
        "id" text PRIMARY KEY,
        "user_id" text NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
        "novel_id" text NOT NULL, "chapter_id" text NOT NULL,
        "visited_at" timestamp DEFAULT now() NOT NULL,
        "created_at" timestamp DEFAULT now() NOT NULL,
        "updated_at" timestamp DEFAULT now() NOT NULL
      );
      INSERT INTO "users" VALUES ('u1'), ('u2');
      INSERT INTO "reading_progress" ("id", "user_id", "novel_id", "chapter_id", "percentage")
        VALUES ('p1', 'u1', 'n1', 'c1', 64);
      INSERT INTO "reading_history" ("id", "user_id", "novel_id", "chapter_id", "visited_at", "created_at") VALUES
        ('h1', 'u1', 'n1', 'c1', '2026-10-01 10:00', '2026-10-01 10:00'),
        ('h2', 'u1', 'n1', 'c1', '2026-10-03 10:00', '2026-10-03 10:00'),
        ('h3', 'u1', 'n1', 'c1', '2026-10-02 10:00', '2026-10-02 10:00'),
        ('h4', 'u1', 'n1', 'c2', '2026-10-02 10:00', '2026-10-02 10:00'),
        ('h5', 'u2', 'n1', 'c1', '2026-10-02 10:00', '2026-10-02 10:00');
    `);

    const migration = await readFile(
      path.join(__dirname, "../drizzle/0006_reading_history_per_chapter.sql"),
      "utf8"
    );
    await client.query("BEGIN");
    await client.query(migration);
    await client.query("COMMIT");

    const collapsed = await client.query(
      `SELECT "id", "user_id", "chapter_id", "progress",
              to_char("visited_at", 'YYYY-MM-DD') AS "visited", to_char("created_at", 'YYYY-MM-DD') AS "created"
       FROM "reading_history" ORDER BY "user_id", "chapter_id"`
    );
    assert.deepEqual(collapsed.rows, [
      { id: "h2", user_id: "u1", chapter_id: "c1", progress: 64, visited: "2026-10-03", created: "2026-10-01" },
      { id: "h4", user_id: "u1", chapter_id: "c2", progress: 0, visited: "2026-10-02", created: "2026-10-02" },
      { id: "h5", user_id: "u2", chapter_id: "c1", progress: 0, visited: "2026-10-02", created: "2026-10-02" },
    ]);

    // Running it again (e.g. a retried deploy) changes nothing.
    await client.query("BEGIN");
    await client.query(migration);
    await client.query("COMMIT");
    assert.equal((await client.query(`SELECT count(*)::int AS "n" FROM "reading_history"`)).rows[0].n, 3);

    const database = drizzle(client);
    const upload = (readAt: string, progress: number, chapterNumber: number | null) =>
      buildReadingHistoryUpsert(database, "u1", [{
        novelId: "n1",
        chapterId: "c1",
        chapterNumber,
        chapterTitle: chapterNumber == null ? null : "Chapter One",
        readAt: new Date(readAt),
        firstReadAt: new Date(readAt),
        progress,
      }], now);

    // An older offline read with less progress leaves the row's newest read and progress alone.
    let [row] = await upload("2026-09-30T10:00:00Z", 10, 1);
    assert.equal(row?.progress, 64);
    assert.deepEqual(row?.visitedAt, new Date("2026-10-03T10:00:00Z"));
    assert.deepEqual(row?.createdAt, new Date("2026-09-30T10:00:00Z"));
    assert.equal(row?.chapterNumber, 1);

    // A newer read moves it forward; a missing chapter number keeps the known one.
    [row] = await upload("2026-10-10T10:00:00Z", 100, null);
    assert.equal(row?.progress, 100);
    assert.deepEqual(row?.visitedAt, new Date("2026-10-10T10:00:00Z"));
    assert.equal(row?.chapterNumber, 1);
    assert.equal(row?.chapterTitle, "Chapter One");

    // Replaying the same upload is a no-op.
    [row] = await upload("2026-10-10T10:00:00Z", 100, null);
    assert.equal(row?.id, "h2");
    assert.equal((await client.query(`SELECT count(*)::int AS "n" FROM "reading_history"`)).rows[0].n, 3);

    // The unique index now rejects a second row for the chapter.
    await assert.rejects(client.query(
      `INSERT INTO "reading_history" ("id", "user_id", "novel_id", "chapter_id") VALUES ('dup', 'u1', 'n1', 'c1')`
    ));
  } finally {
    await client.end();
    await admin.query(`DROP SCHEMA "${schema}" CASCADE`);
    await admin.end();
  }
});
