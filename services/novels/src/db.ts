import pg from 'pg';

import { errorMessage, log } from './log.js';

const { Pool } = pg;

export interface NovelRow {
  id: number;
  title: string;
  novelUrl: string;
  author: string | null;
  rank: string | null;
  totalChapters: string | null;
  views: string | null;
  bookmarks: string | null;
  status: string | null;
  genres: string[];
  summary: string | null;
  chaptersUrl: string | null;
  imageUrl: string | null;
  rating: number | null;
  lastScraped: Date | null;
}

/** Columns of `novels` the scraper may refresh. The title is deliberately left alone. */
export type NovelMetaColumn =
  | 'author'
  | 'rank'
  | 'total_chapters'
  | 'views'
  | 'bookmarks'
  | 'status'
  | 'genres'
  | 'summary'
  | 'chapters_url'
  | 'image_url'
  | 'rating';

const META_COLUMNS = new Set<NovelMetaColumn>([
  'author',
  'rank',
  'total_chapters',
  'views',
  'bookmarks',
  'status',
  'genres',
  'summary',
  'chapters_url',
  'image_url',
  'rating'
]);

export type NovelMetaChanges = Partial<Record<NovelMetaColumn, string | number | string[]>>;

export interface RunRecord {
  id: number;
  startedAt: Date;
  finishedAt: Date | null;
  status: string;
  trigger: string;
  summary: unknown;
}

const TRANSIENT_CODES = new Set([
  'ECONNREFUSED',
  'ECONNRESET',
  'ETIMEDOUT',
  'EPIPE',
  'EHOSTUNREACH',
  'ENETUNREACH',
  'EAI_AGAIN',
  'EADDRNOTAVAIL',
  '57P01', // admin_shutdown
  '57P02', // crash_shutdown
  '57P03', // cannot_connect_now ("the database system is starting up")
  '08000',
  '08001',
  '08003',
  '08004',
  '08006',
  '53300', // too_many_connections
  '40001', // serialization_failure
  '40P01' // deadlock_detected
]);

export function isTransientDbError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const code = (error as { code?: unknown }).code;
  if (typeof code === 'string' && TRANSIENT_CODES.has(code)) return true;
  return /connection terminated|terminating connection|timeout exceeded when trying to connect|server closed the connection|socket hang up|database system is (starting up|shutting down)/i.test(
    error.message
  );
}

export function isUniqueViolation(error: unknown, constraint?: string): boolean {
  if (!(error instanceof Error)) return false;
  const pgError = error as { code?: string; constraint?: string };
  return pgError.code === '23505' && (constraint === undefined || pgError.constraint === constraint);
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

const RETRY_DELAYS_MS = [1000, 2000, 4000, 8000, 15_000, 30_000];

export class Database {
  private readonly pool: pg.Pool;

  constructor(connectionString: string) {
    this.pool = new Pool({
      connectionString,
      max: 6,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 10_000,
      application_name: 'asterion-novels'
    });
    this.pool.on('error', (error) => {
      log.warn('idle PostgreSQL client error', { error: errorMessage(error) });
    });
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  /** Runs a query, retrying transient connection errors (~1 minute total, enough for a DB restart). */
  async query<T extends pg.QueryResultRow = pg.QueryResultRow>(text: string, values?: unknown[]): Promise<pg.QueryResult<T>> {
    for (let attempt = 0; ; attempt++) {
      try {
        return await this.pool.query<T>(text, values);
      } catch (error) {
        const delay = RETRY_DELAYS_MS[attempt];
        if (delay === undefined || !isTransientDbError(error)) throw error;
        log.warn('transient database error, retrying', { error: errorMessage(error), retryInMs: delay });
        await sleep(delay);
      }
    }
  }

  async ping(): Promise<boolean> {
    try {
      await this.pool.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  // --- service-owned state (schema "novel_scraper"; kept out of public so drizzle never sees it) ---

  async ensureServiceSchema(): Promise<void> {
    await this.query(`CREATE SCHEMA IF NOT EXISTS novel_scraper`);
    await this.query(`
      CREATE TABLE IF NOT EXISTS novel_scraper.runs (
        id BIGSERIAL PRIMARY KEY,
        trigger TEXT NOT NULL,
        full_pass BOOLEAN NOT NULL DEFAULT FALSE,
        status TEXT NOT NULL DEFAULT 'running',
        options JSONB NOT NULL DEFAULT '{}'::jsonb,
        summary JSONB,
        started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        finished_at TIMESTAMPTZ
      )
    `);
    await this.query(`
      CREATE TABLE IF NOT EXISTS novel_scraper.misses (
        novel_id BIGINT NOT NULL REFERENCES public.novels(id) ON DELETE CASCADE,
        chapter_number INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 1,
        last_status TEXT NOT NULL,
        last_error TEXT,
        first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        next_attempt_at TIMESTAMPTZ NOT NULL,
        PRIMARY KEY (novel_id, chapter_number)
      )
    `);
  }

  async serviceSchemaExists(): Promise<boolean> {
    const result = await this.query<{ exists: boolean }>(
      `SELECT to_regclass('novel_scraper.misses') IS NOT NULL AND to_regclass('novel_scraper.runs') IS NOT NULL AS exists`
    );
    return Boolean(result.rows[0]?.exists);
  }

  async startRun(trigger: string, fullPass: boolean, options: unknown): Promise<number> {
    const result = await this.query<{ id: string }>(
      `INSERT INTO novel_scraper.runs (trigger, full_pass, options) VALUES ($1, $2, $3) RETURNING id`,
      [trigger, fullPass, JSON.stringify(options ?? {})]
    );
    return Number(result.rows[0]!.id);
  }

  async finishRun(id: number, status: string, summary: unknown): Promise<void> {
    await this.query(`UPDATE novel_scraper.runs SET status = $2, summary = $3, finished_at = NOW() WHERE id = $1`, [
      id,
      status,
      JSON.stringify(summary)
    ]);
  }

  /** Marks runs left 'running' by a crashed/killed process as interrupted. */
  async closeAbandonedRuns(): Promise<number> {
    const result = await this.query(
      `UPDATE novel_scraper.runs SET status = 'interrupted', finished_at = NOW() WHERE status = 'running'`
    );
    return result.rowCount ?? 0;
  }

  /** When the last completed full pass (all novels, no chapter cap) finished. */
  async lastCompletedRunAt(): Promise<Date | null> {
    const result = await this.query<{ finished_at: Date }>(
      `SELECT finished_at FROM novel_scraper.runs
        WHERE status = 'completed' AND full_pass
        ORDER BY finished_at DESC LIMIT 1`
    );
    return result.rows[0]?.finished_at ?? null;
  }

  async lastRun(): Promise<RunRecord | null> {
    const result = await this.query<{
      id: string;
      started_at: Date;
      finished_at: Date | null;
      status: string;
      trigger: string;
      summary: unknown;
    }>(`SELECT id, started_at, finished_at, status, trigger, summary FROM novel_scraper.runs ORDER BY id DESC LIMIT 1`);
    const row = result.rows[0];
    return row
      ? {
          id: Number(row.id),
          startedAt: row.started_at,
          finishedAt: row.finished_at,
          status: row.status,
          trigger: row.trigger,
          summary: row.summary
        }
      : null;
  }

  /**
   * Cross-process guard: holds a session advisory lock on a dedicated client until released.
   * Returns null when another process already holds it.
   */
  async tryAcquireRunLock(): Promise<(() => Promise<void>) | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query<{ locked: boolean }>(
        `SELECT pg_try_advisory_lock(hashtext('asterion-novel-scraper')) AS locked`
      );
      if (!result.rows[0]?.locked) {
        client.release();
        return null;
      }
    } catch (error) {
      client.release(true);
      throw error;
    }
    return async () => {
      try {
        await client.query(`SELECT pg_advisory_unlock(hashtext('asterion-novel-scraper'))`);
        client.release();
      } catch {
        client.release(true);
      }
    };
  }

  // --- content tables (public.novels / public.chapters, owned by services/core-api) ---

  async listNovels(filter: { ids?: number[]; slugs?: string[] } = {}): Promise<NovelRow[]> {
    const conditions = [`novel_url LIKE 'https://novelfire.net/book/%'`];
    const values: unknown[] = [];
    const ors: string[] = [];
    if (filter.ids && filter.ids.length > 0) {
      values.push(filter.ids);
      ors.push(`id = ANY($${values.length}::bigint[])`);
    }
    if (filter.slugs && filter.slugs.length > 0) {
      values.push(filter.slugs.map((slug) => `https://novelfire.net/book/${slug}`));
      ors.push(`novel_url = ANY($${values.length}::text[])`);
    }
    if (ors.length > 0) conditions.push(`(${ors.join(' OR ')})`);

    const result = await this.query(
      `SELECT id, title, novel_url, author, rank, total_chapters, views, bookmarks, status, genres,
              summary, chapters_url, image_url, rating, last_scraped
         FROM novels
        WHERE ${conditions.join(' AND ')}
        ORDER BY id`,
      values
    );
    return result.rows.map((row) => ({
      id: Number(row.id),
      title: row.title,
      novelUrl: row.novel_url,
      author: row.author,
      rank: row.rank,
      totalChapters: row.total_chapters,
      views: row.views,
      bookmarks: row.bookmarks,
      status: row.status,
      genres: Array.isArray(row.genres) ? row.genres : [],
      summary: row.summary,
      chaptersUrl: row.chapters_url,
      imageUrl: row.image_url,
      rating: row.rating === null ? null : Number(row.rating),
      lastScraped: row.last_scraped
    }));
  }

  /** Chapter numbers already stored with non-empty content. */
  async storedChapterNumbers(novelId: number): Promise<number[]> {
    const result = await this.query<{ chapter_number: number }>(
      `SELECT chapter_number FROM chapters WHERE novel_id = $1 AND length(content) > 0`,
      [novelId]
    );
    return result.rows.map((row) => row.chapter_number);
  }

  /** Missing chapters whose retry back-off has not elapsed yet. */
  async deferredMisses(novelId: number): Promise<number[]> {
    const result = await this.query<{ chapter_number: number }>(
      `SELECT chapter_number FROM novel_scraper.misses WHERE novel_id = $1 AND next_attempt_at > NOW()`,
      [novelId]
    );
    return result.rows.map((row) => row.chapter_number);
  }

  /**
   * Inserts or refreshes one chapter. Content is only overwritten when the new content is
   * non-empty, so a bad fetch can never blank a stored chapter. Returns whether a row was inserted.
   */
  async upsertChapter(chapter: {
    novelId: number;
    chapterNumber: number;
    url: string;
    title: string;
    content: string;
  }): Promise<{ inserted: boolean }> {
    if (chapter.content.trim().length === 0) {
      throw new Error('refusing to store a chapter with empty content');
    }
    const result = await this.query<{ inserted: boolean }>(
      `INSERT INTO chapters (novel_id, chapter_number, url, title, content)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (novel_id, chapter_number) DO UPDATE SET
         url = EXCLUDED.url,
         title = CASE WHEN length(EXCLUDED.title) > 0 THEN EXCLUDED.title ELSE chapters.title END,
         content = CASE WHEN length(EXCLUDED.content) > 0 THEN EXCLUDED.content ELSE chapters.content END,
         updated_at = NOW()
       RETURNING (xmax = 0) AS inserted`,
      [chapter.novelId, chapter.chapterNumber, chapter.url, chapter.title, chapter.content]
    );
    return { inserted: Boolean(result.rows[0]?.inserted) };
  }

  async recordMiss(miss: {
    novelId: number;
    chapterNumber: number;
    status: string;
    error: string | null;
    baseDelaySeconds: number;
    maxDelaySeconds: number;
  }): Promise<void> {
    await this.query(
      `INSERT INTO novel_scraper.misses
         (novel_id, chapter_number, attempts, last_status, last_error, next_attempt_at)
       VALUES ($1, $2, 1, $3, $4, NOW() + make_interval(secs => $5))
       ON CONFLICT (novel_id, chapter_number) DO UPDATE SET
         attempts = novel_scraper.misses.attempts + 1,
         last_status = EXCLUDED.last_status,
         last_error = EXCLUDED.last_error,
         last_attempt_at = NOW(),
         next_attempt_at = NOW() + make_interval(secs => LEAST($6::double precision,
           $5::double precision * power(2, LEAST(novel_scraper.misses.attempts, 20))))`,
      [miss.novelId, miss.chapterNumber, miss.status, miss.error, miss.baseDelaySeconds, miss.maxDelaySeconds]
    );
  }

  async clearMiss(novelId: number, chapterNumber: number): Promise<void> {
    await this.query(`DELETE FROM novel_scraper.misses WHERE novel_id = $1 AND chapter_number = $2`, [
      novelId,
      chapterNumber
    ]);
  }

  /** Updates only the given metadata columns, plus last_scraped. */
  async updateNovelMeta(novelId: number, changes: NovelMetaChanges): Promise<void> {
    const sets: string[] = [];
    const values: unknown[] = [];
    for (const [column, value] of Object.entries(changes) as Array<[NovelMetaColumn, unknown]>) {
      if (!META_COLUMNS.has(column)) throw new Error(`unexpected novels column ${column}`);
      values.push(value);
      sets.push(`${column} = $${values.length}`);
    }
    sets.push('last_scraped = NOW()');
    if (sets.length > 1) sets.push('updated_at = NOW()');
    values.push(novelId);
    await this.query(`UPDATE novels SET ${sets.join(', ')} WHERE id = $${values.length}`, values);
  }
}
