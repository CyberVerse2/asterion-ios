import { z } from "zod";

/** The most entries one `POST /me/history` call may carry. */
export const readingHistoryBatchLimit = 200;

const postgresIntegerMax = 2_147_483_647;
const earliestReadAt = Date.UTC(2000, 0, 1);

export const readingHistoryEntrySchema = z.object({
  novelId: z.string().trim().min(1).max(500),
  chapterId: z.string().trim().min(1).max(500),
  chapterNumber: z.number().int().min(0).max(postgresIntegerMax).nullable().optional(),
  chapterTitle: z.string().trim().max(500).nullable().optional(),
  readAt: z.coerce.date().refine(
    (value) => !Number.isNaN(value.getTime()) && value.getTime() >= earliestReadAt,
    "readAt must be an ISO 8601 date after 2000."
  ),
  progress: z.number().finite().min(0).max(100).nullable().optional(),
}).strict();

export const readingHistoryBatchSchema = z.object({
  entries: z.array(readingHistoryEntrySchema).min(1).max(readingHistoryBatchLimit),
}).strict();

export type ReadingHistoryEntryInput = z.infer<typeof readingHistoryEntrySchema>;

export interface CollapsedReadingHistoryEntry {
  novelId: string;
  chapterId: string;
  chapterNumber: number | null;
  chapterTitle: string | null;
  /** The newest read in the batch. */
  readAt: Date;
  /** The earliest read in the batch. */
  firstReadAt: Date;
  progress: number;
}

/**
 * Folds a batch into one entry per chapter (Postgres can't upsert the same
 * row twice in one statement): the newest read time, the furthest progress,
 * and the latest known chapter number and title. Read times from a device
 * whose clock runs ahead are pulled back to `now`, so a skewed clock can't
 * pin a chapter to the top of History.
 */
export function collapseReadingHistoryEntries(
  entries: readonly ReadingHistoryEntryInput[],
  now: Date
): CollapsedReadingHistoryEntry[] {
  const byChapter = new Map<string, CollapsedReadingHistoryEntry & { titleAt: number; numberAt: number }>();
  for (const entry of entries) {
    const readAt = entry.readAt.getTime() > now.getTime() ? new Date(now.getTime()) : entry.readAt;
    const progress = entry.progress ?? 0;
    const key = `${entry.novelId}\u0000${entry.chapterId}`;
    const existing = byChapter.get(key);
    if (!existing) {
      byChapter.set(key, {
        novelId: entry.novelId,
        chapterId: entry.chapterId,
        chapterNumber: entry.chapterNumber ?? null,
        chapterTitle: entry.chapterTitle || null,
        readAt,
        firstReadAt: readAt,
        progress,
        numberAt: readAt.getTime(),
        titleAt: readAt.getTime(),
      });
      continue;
    }
    if (entry.chapterNumber != null && (existing.chapterNumber == null || readAt.getTime() >= existing.numberAt)) {
      existing.chapterNumber = entry.chapterNumber;
      existing.numberAt = readAt.getTime();
    }
    if (entry.chapterTitle && (existing.chapterTitle == null || readAt.getTime() >= existing.titleAt)) {
      existing.chapterTitle = entry.chapterTitle;
      existing.titleAt = readAt.getTime();
    }
    if (readAt.getTime() > existing.readAt.getTime()) existing.readAt = readAt;
    if (readAt.getTime() < existing.firstReadAt.getTime()) existing.firstReadAt = readAt;
    existing.progress = Math.max(existing.progress, progress);
  }
  return [...byChapter.values()].map(({ titleAt: _titleAt, numberAt: _numberAt, ...entry }) => entry);
}
