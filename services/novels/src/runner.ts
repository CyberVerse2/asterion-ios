import type { Config } from './config.js';
import type { Database, NovelMetaChanges, NovelRow } from './db.js';
import { isUniqueViolation } from './db.js';
import { Fetcher, type FetchResult } from './fetcher.js';
import { errorMessage, log } from './log.js';
import {
  isEmptyChapter,
  parseChapterListPage,
  parseChapterPage,
  parseNovelPage,
  type ChapterListInfo,
  type NovelPageMeta
} from './parse.js';
import { formatRanges, planMissingChapters } from './plan.js';

export interface RunOptions {
  trigger: string;
  dryRun: boolean;
  novelIds?: number[];
  slugs?: string[];
  maxChaptersPerNovel?: number;
  maxChaptersPerRun?: number;
  /** Dry run only: fetch the first planned chapter of each novel (read-only) to show whether it is fetchable. */
  probe?: boolean;
}

export type NovelOutcome = 'updated' | 'up_to_date' | 'partial' | 'unavailable' | 'error' | 'dry_run' | 'skipped';

export interface NovelReport {
  id: number;
  title: string;
  outcome: NovelOutcome;
  bookPage: 'ok' | 'not_found' | 'error';
  latest: number | null;
  stored: number;
  missing: number;
  holes: number;
  tail: number;
  deferred: number;
  planned: number;
  plannedRanges: string;
  attempted: number;
  added: number;
  refilled: number;
  misses: number;
  errors: number;
  metaChanges: string[];
  probe?: string;
  note?: string;
}

export interface RunSummary {
  runId: number | null;
  trigger: string;
  dryRun: boolean;
  status: 'completed' | 'aborted' | 'failed';
  startedAt: string;
  finishedAt: string;
  durationSeconds: number;
  requests: number;
  novelsScanned: number;
  novelsUpdated: number;
  chaptersAdded: number;
  chaptersRefilled: number;
  misses: number;
  errors: number;
  unavailable: string[];
  failed: Array<{ title: string; error: string }>;
  novels: NovelReport[];
}

export interface RunProgress {
  runId: number | null;
  startedAt: string;
  dryRun: boolean;
  novelsTotal: number;
  novelsDone: number;
  chaptersAdded: number;
  misses: number;
  errors: number;
}

const GLOBAL_BLOCK_ABORT_THRESHOLD = 30;

async function mapLimit<T>(items: readonly T[], limit: number, worker: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next++]!;
      await worker(item);
    }
  });
  await Promise.all(runners);
}

function sameGenres(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((value, index) => value === b[index]);
}

/**
 * Summaries stored by the old scraper carry a trailing "Show More" and arbitrary whitespace; compare
 * without either so cosmetic differences do not rewrite every summary.
 */
export function summaryKey(summary: string | null): string {
  return (summary ?? '').replace(/(\s*Show More)+\s*$/i, '').replace(/\s+/g, '');
}

/** Metadata columns whose freshly scraped value differs from what is stored (never blanks a value). */
export function diffNovelMeta(row: NovelRow, meta: NovelPageMeta): NovelMetaChanges {
  const changes: NovelMetaChanges = {};
  const text = (column: keyof NovelMetaChanges, current: string | null, next: string | null) => {
    if (next && next !== current) changes[column] = next;
  };
  text('author', row.author, meta.author);
  text('rank', row.rank, meta.rank);
  text('total_chapters', row.totalChapters, meta.totalChapters);
  text('views', row.views, meta.views);
  text('bookmarks', row.bookmarks, meta.bookmarks);
  text('status', row.status, meta.status);
  if (meta.summary && summaryKey(meta.summary) !== summaryKey(row.summary)) changes.summary = meta.summary;
  text('chapters_url', row.chaptersUrl, meta.chaptersUrl);
  text('image_url', row.imageUrl, meta.imageUrl);
  if (meta.rating !== null && meta.rating !== row.rating) changes.rating = meta.rating;
  if (meta.genres.length > 0 && !sameGenres(row.genres, meta.genres)) changes.genres = meta.genres;
  return changes;
}

function describeChange(column: string, row: NovelRow, changes: NovelMetaChanges): string {
  const before = (row as unknown as Record<string, unknown>)[
    {
      total_chapters: 'totalChapters',
      chapters_url: 'chaptersUrl',
      image_url: 'imageUrl'
    }[column] ?? column
  ];
  const after = (changes as Record<string, unknown>)[column];
  if (column === 'summary') return 'summary';
  if (column === 'genres') return `genres(${(after as string[]).length})`;
  return `${column} ${JSON.stringify(before)}→${JSON.stringify(after)}`;
}

export class ScrapeRunner {
  private running: Promise<RunSummary> | null = null;
  private progress: RunProgress | null = null;
  private abortController: AbortController | null = null;
  lastSummary: RunSummary | null = null;

  constructor(
    private readonly config: Config,
    private readonly db: Database
  ) {}

  get isRunning(): boolean {
    return this.running !== null;
  }

  get currentProgress(): RunProgress | null {
    return this.progress;
  }

  /** Requests a graceful stop of the current pass (in-flight chapters finish, the rest are skipped). */
  abort(): void {
    this.abortController?.abort();
  }

  async waitForIdle(): Promise<void> {
    await this.running?.catch(() => undefined);
  }

  /**
   * Starts a pass unless one is already running in this process. Returns null when busy.
   * Another process holding the database advisory lock makes the pass fail fast.
   */
  start(options: RunOptions): Promise<RunSummary> | null {
    if (this.running) return null;
    const promise = this.execute(options).finally(() => {
      this.running = null;
      this.progress = null;
      this.abortController = null;
    });
    this.running = promise;
    return promise;
  }

  private async execute(options: RunOptions): Promise<RunSummary> {
    const startedAt = new Date();
    const abort = new AbortController();
    this.abortController = abort;
    this.progress = {
      runId: null,
      startedAt: startedAt.toISOString(),
      dryRun: options.dryRun,
      novelsTotal: 0,
      novelsDone: 0,
      chaptersAdded: 0,
      misses: 0,
      errors: 0
    };
    const fetcher = new Fetcher({
      requestIntervalMs: this.config.requestIntervalMs,
      maxInFlight: this.config.maxInFlight,
      timeoutMs: this.config.httpTimeoutMs,
      maxRetries: this.config.httpMaxRetries,
      proxyUrl: this.config.proxyUrl
    });

    let releaseLock: (() => Promise<void>) | null = null;
    let runId: number | null = null;
    let serviceSchema = false;
    const reports: NovelReport[] = [];
    let status: RunSummary['status'] = 'completed';
    let fatal: string | null = null;

    try {
      if (options.dryRun) {
        serviceSchema = await this.db.serviceSchemaExists();
      } else {
        releaseLock = await this.db.tryAcquireRunLock();
        if (!releaseLock) throw new Error('another scraper process holds the run lock');
        await this.db.ensureServiceSchema();
        serviceSchema = true;
        const fullPass = !options.novelIds?.length && !options.slugs?.length && options.maxChaptersPerRun === undefined;
        runId = await this.db.startRun(options.trigger, fullPass, { ...options, trigger: undefined });
      }

      const novels = await this.db.listNovels({
        ...(options.novelIds ? { ids: options.novelIds } : {}),
        ...(options.slugs ? { slugs: options.slugs } : {})
      });
      this.progress = {
        runId,
        startedAt: startedAt.toISOString(),
        dryRun: options.dryRun,
        novelsTotal: novels.length,
        novelsDone: 0,
        chaptersAdded: 0,
        misses: 0,
        errors: 0
      };
      log.info(`${options.dryRun ? 'dry run' : 'run'} started`, {
        runId,
        trigger: options.trigger,
        novels: novels.length,
        maxChaptersPerNovel: options.maxChaptersPerNovel ?? this.config.maxChaptersPerNovel,
        maxChaptersPerRun: options.maxChaptersPerRun ?? (this.config.maxChaptersPerRun || 'unlimited')
      });

      const budget = { remaining: options.maxChaptersPerRun ?? (this.config.maxChaptersPerRun || Infinity) };
      const blocked = { consecutive: 0 };

      await mapLimit(novels, this.config.novelConcurrency, async (novel) => {
        if (abort.signal.aborted) return;
        const report = await this.processNovel(novel, options, fetcher, serviceSchema, budget, blocked, abort);
        reports.push(report);
        if (this.progress) {
          this.progress.novelsDone++;
          this.progress.chaptersAdded += report.added + report.refilled;
          this.progress.misses += report.misses;
          this.progress.errors += report.errors;
        }
        this.logNovel(report, options.dryRun);
      });

      if (abort.signal.aborted) status = 'aborted';
    } catch (error) {
      status = 'failed';
      fatal = errorMessage(error);
      log.error('run failed', { error: fatal });
    } finally {
      await fetcher.close().catch(() => undefined);
    }

    reports.sort((a, b) => a.id - b.id);
    const finishedAt = new Date();
    const summary: RunSummary = {
      runId,
      trigger: options.trigger,
      dryRun: options.dryRun,
      status,
      startedAt: startedAt.toISOString(),
      finishedAt: finishedAt.toISOString(),
      durationSeconds: Math.round((finishedAt.getTime() - startedAt.getTime()) / 100) / 10,
      requests: fetcher.requests,
      novelsScanned: reports.length,
      novelsUpdated: reports.filter((r) => r.added + r.refilled > 0 || r.metaChanges.length > 0).length,
      chaptersAdded: reports.reduce((sum, r) => sum + r.added, 0),
      chaptersRefilled: reports.reduce((sum, r) => sum + r.refilled, 0),
      misses: reports.reduce((sum, r) => sum + r.misses, 0),
      errors: reports.reduce((sum, r) => sum + r.errors, 0) + (fatal ? 1 : 0),
      unavailable: reports.filter((r) => r.outcome === 'unavailable').map((r) => r.title),
      failed: [
        ...(fatal ? [{ title: '(run)', error: fatal }] : []),
        ...reports.filter((r) => r.outcome === 'error').map((r) => ({ title: r.title, error: r.note ?? 'error' }))
      ],
      novels: reports
    };

    if (runId !== null) {
      await this.db.finishRun(runId, status, { ...summary, novels: undefined }).catch((error) => {
        log.error('could not record run summary', { error: errorMessage(error) });
      });
    }
    await releaseLock?.();

    log.info(`${options.dryRun ? 'dry run' : 'run'} finished`, {
      runId,
      status,
      durationSeconds: summary.durationSeconds,
      requests: summary.requests,
      novelsScanned: summary.novelsScanned,
      novelsUpdated: summary.novelsUpdated,
      chaptersAdded: summary.chaptersAdded,
      chaptersRefilled: summary.chaptersRefilled,
      misses: summary.misses,
      errors: summary.errors,
      unavailable: summary.unavailable.length
    });
    this.lastSummary = summary;
    return summary;
  }

  private logNovel(report: NovelReport, dryRun: boolean): void {
    const base = `[${report.id}] ${report.title}`;
    const fields: Record<string, unknown> = {
      outcome: report.outcome,
      latest: report.latest,
      stored: report.stored,
      missing: report.missing
    };
    if (dryRun) {
      Object.assign(fields, {
        holes: report.holes,
        tail: report.tail,
        deferred: report.deferred,
        wouldFetch: report.planned,
        ranges: report.plannedRanges
      });
      if (report.probe) fields.probe = report.probe;
    } else if (report.attempted > 0 || report.metaChanges.length > 0) {
      Object.assign(fields, {
        attempted: report.attempted,
        added: report.added,
        refilled: report.refilled,
        misses: report.misses,
        errors: report.errors
      });
    }
    if (report.bookPage !== 'ok') fields.bookPage = report.bookPage;
    if (report.metaChanges.length > 0) fields.meta = report.metaChanges.join('; ');
    if (report.note) fields.note = report.note;
    const level = report.outcome === 'error' ? 'warn' : 'info';
    log[level](base, fields);
  }

  private async processNovel(
    novel: NovelRow,
    options: RunOptions,
    fetcher: Fetcher,
    serviceSchema: boolean,
    budget: { remaining: number },
    blocked: { consecutive: number },
    abort: AbortController
  ): Promise<NovelReport> {
    const report: NovelReport = {
      id: novel.id,
      title: novel.title,
      outcome: 'up_to_date',
      bookPage: 'ok',
      latest: null,
      stored: 0,
      missing: 0,
      holes: 0,
      tail: 0,
      deferred: 0,
      planned: 0,
      plannedRanges: '-',
      attempted: 0,
      added: 0,
      refilled: 0,
      misses: 0,
      errors: 0,
      metaChanges: []
    };

    try {
      const bookUrl = novel.novelUrl.replace(/\/+$/, '');

      // 1. Book page → metadata (may be gone for taken-down novels).
      const bookResult = await fetcher.get(bookUrl, undefined, abort.signal);
      let meta: NovelPageMeta | null = null;
      if (bookResult.kind === 'ok') {
        meta = parseNovelPage(bookResult.html, bookUrl);
        if (!meta) report.bookPage = 'not_found';
      } else {
        report.bookPage = bookResult.kind === 'not_found' ? 'not_found' : 'error';
      }
      this.noteBlocked(bookResult, blocked, abort);

      // 2. Chapter list page 1 → authoritative latest chapter URL number.
      const listUrl = `${bookUrl}/chapters`;
      const listResult = await fetcher.get(listUrl, bookUrl, abort.signal);
      this.noteBlocked(listResult, blocked, abort);
      let list: ChapterListInfo | null = null;
      if (listResult.kind === 'ok') list = parseChapterListPage(listResult.html, listUrl);

      let latest = list?.latestChapterNumber ?? null;
      if (latest === null && meta?.totalChapters) {
        const count = Number.parseInt(meta.totalChapters, 10);
        if (Number.isSafeInteger(count) && count > 0) latest = count;
      }
      report.latest = latest;

      // 3. Metadata refresh (only columns that changed).
      if (meta) {
        const changes = diffNovelMeta(novel, meta);
        report.metaChanges = Object.keys(changes).map((column) => describeChange(column, novel, changes));
        if (!options.dryRun) await this.db.updateNovelMeta(novel.id, changes);
      }

      if (latest === null) {
        report.outcome = report.bookPage === 'not_found' && listResult.kind === 'not_found' ? 'unavailable' : 'error';
        report.note =
          listResult.kind === 'ok'
            ? 'chapter list did not expose a latest chapter'
            : `chapter list ${listResult.kind === 'not_found' ? 'not found' : listResult.error}`;
        if (report.outcome === 'error') report.errors++;
        return report;
      }

      // 4. Plan: everything in 1..latest that is not stored, minus misses still backing off.
      const stored = await this.db.storedChapterNumbers(novel.id);
      const deferred = serviceSchema ? await this.db.deferredMisses(novel.id) : [];
      const perNovel = options.maxChaptersPerNovel ?? this.config.maxChaptersPerNovel;
      const plan = planMissingChapters(stored, latest, {
        deferred,
        max: Math.max(0, Math.min(perNovel, budget.remaining))
      });
      budget.remaining -= plan.toFetch.length;
      Object.assign(report, {
        stored: stored.length,
        missing: plan.missing.length,
        holes: plan.holes,
        tail: plan.tail,
        deferred: plan.deferred.length,
        planned: plan.toFetch.length,
        plannedRanges: formatRanges(plan.toFetch)
      });

      if (options.dryRun) {
        report.outcome = plan.missing.length === 0 && report.metaChanges.length === 0 ? 'up_to_date' : 'dry_run';
        if (options.probe && plan.toFetch.length > 0) {
          const number = plan.toFetch[0]!;
          const result = await fetcher.get(`${bookUrl}/chapter-${number}`, listUrl, abort.signal);
          const page = result.kind === 'ok' ? parseChapterPage(result.html) : null;
          report.probe =
            result.kind === 'ok'
              ? isEmptyChapter(page, this.config.minContentChars)
                ? `chapter-${number}: 200 but empty content`
                : `chapter-${number}: ok "${page?.title ?? ''}" (${page?.textLength ?? 0} chars)`
              : `chapter-${number}: ${result.kind === 'not_found' ? `gone (HTTP ${result.status})` : result.error}`;
        }
        if (report.bookPage === 'not_found') report.note = 'book page is gone on novelfire (taken down?)';
        return report;
      }

      if (plan.toFetch.length === 0) {
        report.outcome = report.metaChanges.length > 0 ? 'updated' : 'up_to_date';
        return report;
      }

      // 5. Fetch and store, isolating every chapter; trip a breaker if the source looks dead.
      let consecutiveFailures = 0;
      let successes = 0;
      let tripped = false;
      const queue = [...plan.toFetch];
      const minChars = this.config.minContentChars;
      const baseDelaySeconds = this.config.missRetryBaseHours * 3600;
      const maxDelaySeconds = this.config.missRetryMaxDays * 86400;

      const recordMiss = async (number: number, statusLabel: string, error: string | null) => {
        report.misses++;
        await this.db
          .recordMiss({ novelId: novel.id, chapterNumber: number, status: statusLabel, error, baseDelaySeconds, maxDelaySeconds })
          .catch((dbError) => {
            report.errors++;
            log.warn('could not record miss', { novel: novel.id, chapter: number, error: errorMessage(dbError) });
          });
      };

      await mapLimit(Array.from({ length: this.config.chapterConcurrency }), this.config.chapterConcurrency, async () => {
        while (queue.length > 0 && !tripped && !abort.signal.aborted) {
          const number = queue.shift()!;
          const url = `${bookUrl}/chapter-${number}`;
          report.attempted++;
          const result = await fetcher.get(url, listUrl, abort.signal);
          this.noteBlocked(result, blocked, abort);
          if (abort.signal.aborted && result.kind === 'error') break;

          if (result.kind !== 'ok') {
            consecutiveFailures++;
            await recordMiss(number, result.kind === 'not_found' ? `http_${result.status}` : 'fetch_error', result.kind === 'error' ? result.error : null);
          } else {
            const page = parseChapterPage(result.html);
            if (!page || isEmptyChapter(page, minChars)) {
              consecutiveFailures++;
              await recordMiss(number, 'empty', page ? `text ${page.textLength} chars` : 'not a chapter page');
            } else {
              try {
                const { inserted } = await this.db.upsertChapter({
                  novelId: novel.id,
                  chapterNumber: number,
                  url,
                  title: page.title ?? `Chapter ${number}`,
                  content: page.contentHtml
                });
                if (inserted) report.added++;
                else report.refilled++;
                successes++;
                consecutiveFailures = 0;
                if (serviceSchema) await this.db.clearMiss(novel.id, number).catch(() => undefined);
              } catch (error) {
                report.errors++;
                consecutiveFailures++;
                const conflict = isUniqueViolation(error, 'chapters_url_key');
                log.warn('could not store chapter', { novel: novel.id, chapter: number, error: errorMessage(error) });
                await recordMiss(number, conflict ? 'db_url_conflict' : 'db_error', errorMessage(error));
              }
            }
          }

          const threshold = successes === 0 ? this.config.circuitBreakerFailures : this.config.circuitBreakerFailures * 4;
          if (!tripped && consecutiveFailures >= threshold) {
            tripped = true;
            report.note = `stopped after ${consecutiveFailures} consecutive failures; will retry next run`;
          }
        }
      });

      const added = report.added + report.refilled;
      if (added === plan.toFetch.length) report.outcome = 'updated';
      else if (tripped && added === 0 && report.bookPage === 'not_found') report.outcome = 'unavailable';
      else report.outcome = 'partial';
      if (report.bookPage === 'not_found' && !report.note) report.note = 'book page is gone on novelfire';
      return report;
    } catch (error) {
      report.outcome = 'error';
      report.errors++;
      report.note = errorMessage(error);
      return report;
    }
  }

  /** Aborts the whole pass if the source keeps refusing us (sustained 403/429 after retries). */
  private noteBlocked(result: FetchResult, blocked: { consecutive: number }, abort: AbortController): void {
    if (result.kind === 'error' && (result.status === 403 || result.status === 429)) {
      blocked.consecutive++;
      if (blocked.consecutive >= GLOBAL_BLOCK_ABORT_THRESHOLD && !abort.signal.aborted) {
        log.error('source keeps refusing requests; aborting run', { consecutive: blocked.consecutive });
        abort.abort();
      }
    } else if (result.kind !== 'error') {
      blocked.consecutive = 0;
    }
  }
}
