import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { userPreferences, users } from "../db/schema";
import { db, pool } from "./db";

let userSchemaEnsured = false;
let userSchemaPromise: Promise<void> | null = null;

export async function ensureUserSchema() {
  if (userSchemaEnsured) {
    return;
  }

  if (userSchemaPromise) {
    await userSchemaPromise;
    return;
  }

  userSchemaPromise = (async () => {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        clerk_user_id TEXT NOT NULL,
        email TEXT,
        username TEXT,
        avatar_url TEXT,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
    `);

    await pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS users_clerk_user_id_key
      ON users (clerk_user_id);
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS reading_progress (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        novel_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        current_line INTEGER NOT NULL DEFAULT 0,
        total_lines INTEGER NOT NULL DEFAULT 0,
        percentage DOUBLE PRECISION NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
    `);

    await pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS user_novel_progress_unique
      ON reading_progress (user_id, novel_id);
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS reading_progress_user_updated_idx
      ON reading_progress (user_id, updated_at);
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS reading_progress_user_novel_idx
      ON reading_progress (user_id, novel_id);
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        novel_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        note TEXT,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
    `);

    await pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS bookmark_user_chapter_unique
      ON bookmarks (user_id, chapter_id);
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS bookmark_user_novel_idx
      ON bookmarks (user_id, novel_id);
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS bookmark_user_created_idx
      ON bookmarks (user_id, created_at);
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS reading_history (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        novel_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        visited_at TIMESTAMP NOT NULL DEFAULT NOW(),
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS reading_history_user_visited_idx
      ON reading_history (user_id, visited_at);
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS reading_history_user_novel_idx
      ON reading_history (user_id, novel_id);
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_preferences (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        reading_goal INTEGER NOT NULL DEFAULT 30,
        dark_mode BOOLEAN NOT NULL DEFAULT true,
        notifications_on BOOLEAN NOT NULL DEFAULT true,
        font_size_pref TEXT NOT NULL DEFAULT 'medium',
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
    `);

    await pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS user_preferences_user_unique
      ON user_preferences (user_id);
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_library_novels (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        novel_id TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
    `);

    await pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS user_library_novel_unique
      ON user_library_novels (user_id, novel_id);
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS user_library_user_created_idx
      ON user_library_novels (user_id, created_at);
    `);

    userSchemaEnsured = true;
  })();

  try {
    await userSchemaPromise;
  } finally {
    userSchemaPromise = null;
  }
}

export async function ensureUser(clerkUserId: string) {
  await ensureUserSchema();

  const existing = await db.query.users.findFirst({
    where: eq(users.clerkUserId, clerkUserId),
  });
  if (existing) return { user: existing, created: false as const };

  const [created] = await db
    .insert(users)
    .values({
      id: randomUUID(),
      clerkUserId,
    })
    .onConflictDoNothing({ target: users.clerkUserId })
    .returning();
  if (created) return { user: created, created: true as const };

  const raceSafe = await db.query.users.findFirst({
    where: eq(users.clerkUserId, clerkUserId),
  });
  if (!raceSafe) {
    throw new Error("Unable to ensure user.");
  }
  return { user: raceSafe, created: false as const };
}

export async function ensureUserPreferences(userId: string) {
  await ensureUserSchema();

  const existing = await db.query.userPreferences.findFirst({
    where: eq(userPreferences.userId, userId),
  });
  if (existing) return existing;

  const [created] = await db
    .insert(userPreferences)
    .values({
      id: randomUUID(),
      userId,
    })
    .onConflictDoNothing({ target: userPreferences.userId })
    .returning();
  if (created) return created;

  const raceSafe = await db.query.userPreferences.findFirst({
    where: eq(userPreferences.userId, userId),
  });
  if (!raceSafe) {
    throw new Error("Unable to ensure user preferences.");
  }
  return raceSafe;
}
