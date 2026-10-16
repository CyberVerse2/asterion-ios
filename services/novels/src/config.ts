export interface Config {
  databaseUrl: string;
  token: string | null;
  proxyUrl: string | null;
  host: string;
  port: number;

  schedulerEnabled: boolean;
  scheduleHourUtc: number;
  scheduleMinuteUtc: number;
  runIntervalHours: number;
  startupRunDelaySeconds: number;

  requestIntervalMs: number;
  maxInFlight: number;
  novelConcurrency: number;
  chapterConcurrency: number;
  httpTimeoutMs: number;
  httpMaxRetries: number;

  maxChaptersPerNovel: number;
  maxChaptersPerRun: number;
  missRetryBaseHours: number;
  missRetryMaxDays: number;
  minContentChars: number;
  circuitBreakerFailures: number;
}

type Env = Record<string, string | undefined>;

function int(env: Env, name: string, fallback: number, min = 0, max = Number.MAX_SAFE_INTEGER): number {
  const raw = env[name]?.trim();
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || !Number.isInteger(value) || value < min || value > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max} (got "${raw}")`);
  }
  return value;
}

function bool(env: Env, name: string, fallback: boolean): boolean {
  const raw = env[name]?.trim().toLowerCase();
  if (!raw) return fallback;
  if (['1', 'true', 'yes', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'off'].includes(raw)) return false;
  throw new Error(`${name} must be true or false (got "${raw}")`);
}

function str(env: Env, name: string): string | null {
  const raw = env[name]?.trim();
  return raw ? raw : null;
}

export function loadConfig(env: Env = process.env): Config {
  const databaseUrl = str(env, 'DATABASE_URL');
  if (!databaseUrl) {
    throw new Error('DATABASE_URL is required');
  }

  return {
    databaseUrl,
    token: str(env, 'NOVEL_SCRAPER_TOKEN'),
    proxyUrl: str(env, 'PROXY_URL') ?? str(env, 'HTTPS_PROXY') ?? str(env, 'https_proxy'),
    host: str(env, 'HOST') ?? '0.0.0.0',
    port: int(env, 'PORT', 8080, 1, 65535),

    schedulerEnabled: bool(env, 'SCHEDULER_ENABLED', true),
    scheduleHourUtc: int(env, 'SCHEDULE_HOUR_UTC', 4, 0, 23),
    scheduleMinuteUtc: int(env, 'SCHEDULE_MINUTE_UTC', 0, 0, 59),
    runIntervalHours: int(env, 'RUN_INTERVAL_HOURS', 24, 1, 24 * 30),
    startupRunDelaySeconds: int(env, 'STARTUP_RUN_DELAY_SECONDS', 120, 0, 24 * 3600),

    requestIntervalMs: int(env, 'REQUEST_INTERVAL_MS', 1000, 100, 60_000),
    maxInFlight: int(env, 'MAX_IN_FLIGHT', 3, 1, 32),
    novelConcurrency: int(env, 'NOVEL_CONCURRENCY', 2, 1, 16),
    chapterConcurrency: int(env, 'CHAPTER_CONCURRENCY', 2, 1, 16),
    httpTimeoutMs: int(env, 'HTTP_TIMEOUT_MS', 30_000, 1000, 300_000),
    httpMaxRetries: int(env, 'HTTP_MAX_RETRIES', 3, 0, 10),

    maxChaptersPerNovel: int(env, 'MAX_CHAPTERS_PER_NOVEL', 500, 1),
    maxChaptersPerRun: int(env, 'MAX_CHAPTERS_PER_RUN', 0, 0),
    missRetryBaseHours: int(env, 'MISS_RETRY_BASE_HOURS', 12, 1, 24 * 30),
    missRetryMaxDays: int(env, 'MISS_RETRY_MAX_DAYS', 30, 1, 365),
    minContentChars: int(env, 'MIN_CONTENT_CHARS', 30, 1, 10_000),
    circuitBreakerFailures: int(env, 'CIRCUIT_BREAKER_FAILURES', 5, 1, 1000)
  };
}
