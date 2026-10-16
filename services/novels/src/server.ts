import { timingSafeEqual } from 'node:crypto';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';

import { loadConfig } from './config.js';
import { Database } from './db.js';
import { describeProxy } from './fetcher.js';
import { errorMessage, log } from './log.js';
import { isRunOverdue, nextScheduledRun } from './plan.js';
import { ScrapeRunner, type RunOptions } from './runner.js';

const config = loadConfig();
const db = new Database(config.databaseUrl);
const runner = new ScrapeRunner(config, db);

let nextRunAt: Date | null = null;
let scheduleTimer: NodeJS.Timeout | null = null;
let shuttingDown = false;

function launch(options: RunOptions): boolean {
  const started = runner.start(options);
  if (!started) return false;
  started.catch((error) => log.error('run crashed', { error: errorMessage(error) }));
  return true;
}

function scheduleAt(when: Date, trigger: string): void {
  if (scheduleTimer) clearTimeout(scheduleTimer);
  nextRunAt = when;
  const delay = Math.max(0, when.getTime() - Date.now());
  scheduleTimer = setTimeout(() => {
    scheduleTimer = null;
    if (shuttingDown) return;
    if (runner.isRunning) {
      log.info('scheduled run skipped: a pass is already running', { trigger });
    } else {
      launch({ trigger, dryRun: false });
    }
    scheduleAt(nextScheduledRun(new Date(), config.scheduleHourUtc, config.scheduleMinuteUtc), 'schedule');
  }, delay);
  log.info('next run scheduled', { at: when.toISOString(), trigger });
}

async function startScheduler(): Promise<void> {
  if (!config.schedulerEnabled) {
    log.info('scheduler disabled (SCHEDULER_ENABLED=false); runs only via POST /run');
    return;
  }
  const daily = nextScheduledRun(new Date(), config.scheduleHourUtc, config.scheduleMinuteUtc);
  try {
    await db.ensureServiceSchema();
    // Only tidy up 'running' rows when nobody else (e.g. a CLI pass) holds the run lock.
    const release = await db.tryAcquireRunLock();
    if (release) {
      const abandoned = await db.closeAbandonedRuns().finally(release);
      if (abandoned > 0) log.warn('marked runs left over from a previous process as interrupted', { count: abandoned });
    }
    const lastCompleted = await db.lastCompletedRunAt();
    if (isRunOverdue(lastCompleted, new Date(), config.runIntervalHours)) {
      const soon = new Date(Date.now() + config.startupRunDelaySeconds * 1000);
      log.info('last completed run is older than the interval; running soon after start', {
        lastCompleted: lastCompleted?.toISOString() ?? null
      });
      // A catch-up run first; the daily slot is picked up again after it fires.
      scheduleAt(soon < daily ? soon : daily, soon < daily ? 'startup-catch-up' : 'schedule');
      return;
    }
  } catch (error) {
    log.error('could not read run history; retrying in 5 minutes', { error: errorMessage(error) });
    setTimeout(() => void startScheduler(), 5 * 60_000).unref();
    return;
  }
  scheduleAt(daily, 'schedule');
}

function send(response: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Cache-Control': 'no-store'
  });
  response.end(payload);
}

function authorised(request: IncomingMessage): boolean {
  if (!config.token) return false;
  const header = request.headers.authorization ?? '';
  const supplied = header.startsWith('Bearer ') ? header.slice(7).trim() : String(request.headers['x-scraper-token'] ?? '');
  const expected = Buffer.from(config.token);
  const actual = Buffer.from(supplied);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function readJson(request: IncomingMessage, limit = 16 * 1024): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += (chunk as Buffer).length;
    if (size > limit) throw new Error('request body too large');
    chunks.push(chunk as Buffer);
  }
  const text = Buffer.concat(chunks).toString('utf8').trim();
  if (!text) return {};
  const value = JSON.parse(text) as unknown;
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('body must be a JSON object');
  return value as Record<string, unknown>;
}

function positiveInt(value: unknown, name: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1) throw new Error(`${name} must be a positive integer`);
  return value;
}

function runOptionsFromBody(body: Record<string, unknown>): RunOptions {
  const novelIds = body.novelIds;
  if (novelIds !== undefined && (!Array.isArray(novelIds) || !novelIds.every((id) => Number.isInteger(id) && id > 0))) {
    throw new Error('novelIds must be an array of positive integers');
  }
  const slugs = body.slugs;
  if (slugs !== undefined && (!Array.isArray(slugs) || !slugs.every((slug) => typeof slug === 'string' && /^[a-z0-9-]+$/.test(slug)))) {
    throw new Error('slugs must be an array of novelfire slugs');
  }
  const options: RunOptions = { trigger: 'api', dryRun: body.dryRun === true, probe: body.probe === true };
  if (novelIds) options.novelIds = novelIds as number[];
  if (slugs) options.slugs = slugs as string[];
  const perNovel = positiveInt(body.maxChaptersPerNovel, 'maxChaptersPerNovel');
  if (perNovel !== undefined) options.maxChaptersPerNovel = perNovel;
  const perRun = positiveInt(body.maxChapters, 'maxChapters');
  if (perRun !== undefined) options.maxChaptersPerRun = perRun;
  return options;
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', 'http://localhost');
  try {
    if (request.method === 'GET' && (url.pathname === '/health' || url.pathname === '/')) {
      const last = runner.lastSummary ?? (await db.lastRun().catch(() => null));
      const dbOk = await db.ping();
      send(response, 200, {
        status: 'ok',
        service: 'asterion-novels',
        database: dbOk ? 'ok' : 'unreachable',
        running: runner.isRunning,
        progress: runner.currentProgress,
        nextRunAt: nextRunAt?.toISOString() ?? null,
        lastRun: last
          ? 'novels' in last
            ? { ...last, novels: undefined }
            : last
          : null
      });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/run') {
      if (!config.token) {
        send(response, 503, { error: 'NOVEL_SCRAPER_TOKEN is not configured; manual runs are disabled' });
        return;
      }
      if (!authorised(request)) {
        send(response, 401, { error: 'unauthorised' });
        return;
      }
      let options: RunOptions;
      try {
        options = runOptionsFromBody(await readJson(request));
      } catch (error) {
        send(response, 400, { error: errorMessage(error) });
        return;
      }
      if (shuttingDown) {
        send(response, 503, { error: 'shutting down' });
        return;
      }
      if (!launch(options)) {
        send(response, 409, { error: 'a run is already in progress', progress: runner.currentProgress });
        return;
      }
      send(response, 202, { accepted: true, options });
      return;
    }

    send(response, 404, { error: 'not found' });
  } catch (error) {
    log.error('request failed', { path: url.pathname, error: errorMessage(error) });
    if (!response.headersSent) send(response, 500, { error: 'internal error' });
  }
});

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  log.info('shutting down', { signal });
  if (scheduleTimer) clearTimeout(scheduleTimer);
  server.close();
  runner.abort();
  await runner.waitForIdle();
  await db.close().catch(() => undefined);
  process.exit(0);
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));

server.listen(config.port, config.host, () => {
  log.info('asterion-novels listening', {
    host: config.host,
    port: config.port,
    proxy: describeProxy(config.proxyUrl),
    schedule: config.schedulerEnabled
      ? `daily ${String(config.scheduleHourUtc).padStart(2, '0')}:${String(config.scheduleMinuteUtc).padStart(2, '0')} UTC`
      : 'disabled',
    manualRuns: config.token ? 'enabled' : 'disabled (no NOVEL_SCRAPER_TOKEN)'
  });
  void startScheduler();
});
