import { Agent, ProxyAgent, fetch, type Dispatcher } from 'undici';

import { errorMessage, log } from './log.js';

export type FetchResult =
  | { kind: 'ok'; status: number; html: string }
  /** 404/410 — the page does not exist (novelfire also serves its "Page Not Found" shell for these). */
  | { kind: 'not_found'; status: number }
  /** Retries exhausted (5xx, 403, 429, timeouts, network errors). */
  | { kind: 'error'; status: number | null; error: string };

export interface FetcherOptions {
  requestIntervalMs: number;
  maxInFlight: number;
  timeoutMs: number;
  maxRetries: number;
  proxyUrl: string | null;
}

// One fixed browser user agent. The scraper doesn't rotate identities or
// otherwise try to look like different clients to get past bot checks.
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36';

const RATE_LIMIT_DEFAULT_PAUSE_MS = 30_000;
const RATE_LIMIT_MAX_PAUSE_MS = 10 * 60_000;
const MAX_INTERVAL_MULTIPLIER = 5;
const RECOVERY_AFTER_SUCCESSES = 25;

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function parseRetryAfterMs(value: string | null): number | null {
  if (!value) return null;
  const seconds = Number(value.trim());
  if (Number.isFinite(seconds) && seconds >= 0) return Math.ceil(seconds * 1000);
  const at = Date.parse(value);
  return Number.isNaN(at) ? null : Math.max(0, at - Date.now());
}

function retryable(status: number | null): boolean {
  // 403 is the source refusing us (e.g. a Cloudflare challenge); retrying or
  // working around it isn't appropriate, so it's final.
  return status === null || status === 408 || status === 425 || status === 429 || status >= 500;
}

/** Redacts credentials from a proxy URL for logging. */
export function describeProxy(proxyUrl: string | null): string {
  if (!proxyUrl) return 'none';
  try {
    const url = new URL(proxyUrl);
    return `${url.protocol}//${url.hostname}${url.port ? `:${url.port}` : ''}`;
  } catch {
    return 'invalid';
  }
}

/**
 * Polite HTML fetcher: one global request slot every `requestIntervalMs` (spacing widens after a
 * 429 and slowly recovers), at most `maxInFlight` concurrent requests, retries with exponential
 * backoff + jitter, a shared cookie jar, a session warm-up after 403s, and an optional proxy.
 */
export class Fetcher {
  private readonly dispatcher: Dispatcher;
  private readonly cookies = new Map<string, string>();
  private nextSlotAt = 0;
  private pausedUntil = 0;
  private intervalMs: number;
  private successesSinceSlowdown = 0;
  private inFlight = 0;
  private readonly waiters: Array<() => void> = [];
  requests = 0;

  constructor(private readonly options: FetcherOptions) {
    this.intervalMs = options.requestIntervalMs;
    this.dispatcher = options.proxyUrl
      ? new ProxyAgent({ uri: options.proxyUrl, connections: options.maxInFlight * 2 })
      : new Agent({ connections: options.maxInFlight * 2, keepAliveTimeout: 30_000 });
  }

  async close(): Promise<void> {
    await this.dispatcher.close();
  }

  async get(url: string, referer?: string, signal?: AbortSignal): Promise<FetchResult> {
    let lastStatus: number | null = null;
    let lastError = 'unknown error';

    for (let attempt = 0; attempt <= this.options.maxRetries; attempt++) {
      if (signal?.aborted) return { kind: 'error', status: null, error: 'aborted' };
      if (attempt > 0) {
        const backoff = 2000 * 2 ** (attempt - 1) + Math.floor(Math.random() * 1000);
        await sleep(backoff);
      }

      let response: Awaited<ReturnType<typeof fetch>> | null = null;
      await this.acquire();
      try {
        this.requests++;
        response = await fetch(url, {
          dispatcher: this.dispatcher,
          redirect: 'follow',
          headers: this.headers(url, referer, attempt),
          signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(this.options.timeoutMs)]) : AbortSignal.timeout(this.options.timeoutMs)
        });
        this.storeCookies(response.headers.getSetCookie());
        const status = response.status;

        if (status >= 200 && status < 300) {
          const html = await response.text();
          this.recordSuccess();
          return { kind: 'ok', status, html };
        }

        // novelfire answers removed books/chapters with its "Page Not Found" shell, either as a
        // 404 or (for chapters of taken-down books) as a 500. After one retry, treat the shell
        // as "gone" rather than burning more retries on it.
        const body = status === 500 && attempt >= 1 ? await response.text().catch(() => '') : '';
        if (!body) await response.body?.cancel().catch(() => undefined);
        lastStatus = status;
        lastError = `HTTP ${status}`;

        if (status === 404 || status === 410 || /<title>\s*Page Not Found/i.test(body)) {
          this.recordSuccess();
          return { kind: 'not_found', status };
        }
        if (status === 429) {
          this.slowDown(parseRetryAfterMs(response.headers.get('retry-after')));
        }
        if (!retryable(status)) {
          return { kind: 'error', status, error: lastError };
        }
      } catch (error) {
        lastStatus = null;
        lastError = errorMessage(error);
        if (signal?.aborted) return { kind: 'error', status: null, error: 'aborted' };
      } finally {
        this.release();
      }

      log.debug('request failed, retrying', { url, status: lastStatus, error: lastError, attempt: attempt + 1 });
    }

    return { kind: 'error', status: lastStatus, error: lastError };
  }

  private headers(url: string, referer: string | undefined, attempt: number): Record<string, string> {
    const origin = new URL(url).origin;
    const headers: Record<string, string> = {
      'User-Agent': USER_AGENT,
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
      Pragma: 'no-cache',
      Referer: referer ?? `${origin}/`,
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': attempt === 0 && !referer ? 'none' : 'same-origin',
      'Sec-Fetch-User': '?1',
      'sec-ch-ua': '"Google Chrome";v="135", "Not-A.Brand";v="8", "Chromium";v="135"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"'
    };
    if (this.cookies.size > 0) {
      headers.Cookie = [...this.cookies].map(([name, value]) => `${name}=${value}`).join('; ');
    }
    return headers;
  }

  private storeCookies(setCookies: string[]): void {
    for (const raw of setCookies) {
      const pair = raw.split(';', 1)[0] ?? '';
      const index = pair.indexOf('=');
      if (index <= 0) continue;
      this.cookies.set(pair.slice(0, index).trim(), pair.slice(index + 1).trim());
    }
  }

  private slowDown(retryAfterMs: number | null): void {
    const now = Date.now();
    const pause = Math.min(RATE_LIMIT_MAX_PAUSE_MS, Math.max(1000, retryAfterMs ?? RATE_LIMIT_DEFAULT_PAUSE_MS));
    if (this.pausedUntil <= now) {
      const previous = this.intervalMs;
      this.intervalMs = Math.min(this.options.requestIntervalMs * MAX_INTERVAL_MULTIPLIER, Math.ceil(this.intervalMs * 1.5));
      log.warn('rate limited by source; pausing all requests', {
        pauseSeconds: Math.ceil(pause / 1000),
        intervalMs: `${previous}->${this.intervalMs}`
      });
    }
    this.successesSinceSlowdown = 0;
    this.pausedUntil = Math.max(this.pausedUntil, now + pause);
  }

  private recordSuccess(): void {
    if (this.intervalMs <= this.options.requestIntervalMs) return;
    this.successesSinceSlowdown++;
    if (this.successesSinceSlowdown >= RECOVERY_AFTER_SUCCESSES) {
      this.successesSinceSlowdown = 0;
      this.intervalMs = Math.max(this.options.requestIntervalMs, Math.floor(this.intervalMs * 0.9));
    }
  }

  private async acquire(): Promise<void> {
    while (this.inFlight >= this.options.maxInFlight) {
      await new Promise<void>((resolve) => this.waiters.push(resolve));
    }
    this.inFlight++;
    // Reserve the next global slot, honouring any rate-limit pause.
    for (;;) {
      const now = Date.now();
      const slot = Math.max(now, this.nextSlotAt, this.pausedUntil);
      this.nextSlotAt = slot + this.intervalMs + Math.floor(Math.random() * (this.intervalMs / 4));
      if (slot > now) await sleep(slot - now);
      if (Date.now() >= this.pausedUntil) return;
    }
  }

  private release(): void {
    this.inFlight--;
    this.waiters.shift()?.();
  }
}
