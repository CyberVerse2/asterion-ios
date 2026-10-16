import { randomUUID } from "node:crypto";
import { sql } from "drizzle-orm";
import type { db } from "./db";
import { readingHistory } from "../db/schema";
import type { CollapsedReadingHistoryEntry } from "./reading-history-contract";

type InsertExecutor = Pick<typeof db, "insert">;

/**
 * Upserts one row per (user, novel, chapter). Replays and late uploads from
 * another device are harmless: the row keeps the newest read time and the
 * furthest progress, and a chapter number or title is never cleared.
 * `entries` must hold at most one entry per chapter (see
 * `collapseReadingHistoryEntries`).
 */
export function buildReadingHistoryUpsert(
  executor: InsertExecutor,
  userId: string,
  entries: readonly CollapsedReadingHistoryEntry[],
  now: Date
) {
  return executor
    .insert(readingHistory)
    .values(entries.map((entry) => ({
      id: randomUUID(),
      userId,
      novelId: entry.novelId,
      chapterId: entry.chapterId,
      chapterNumber: entry.chapterNumber,
      chapterTitle: entry.chapterTitle,
      progress: entry.progress,
      visitedAt: entry.readAt,
      createdAt: entry.firstReadAt,
      updatedAt: now,
    })))
    .onConflictDoUpdate({
      target: [readingHistory.userId, readingHistory.novelId, readingHistory.chapterId],
      set: {
        chapterNumber: sql`coalesce(excluded.chapter_number, ${readingHistory.chapterNumber})`,
        chapterTitle: sql`coalesce(excluded.chapter_title, ${readingHistory.chapterTitle})`,
        progress: sql`greatest(${readingHistory.progress}, excluded.progress)`,
        visitedAt: sql`greatest(${readingHistory.visitedAt}, excluded.visited_at)`,
        createdAt: sql`least(${readingHistory.createdAt}, excluded.created_at)`,
        updatedAt: now,
      },
    })
    .returning();
}
