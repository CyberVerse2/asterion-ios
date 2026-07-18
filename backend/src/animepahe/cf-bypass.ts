// ─── Cloudflare Bypass Helper ────────────────────────────────────────
// animepahe.pw uses Cloudflare Turnstile (managed challenge).
// Direct HTTP requests fail with 403. Strategy:
//
//   1. Manual cookie: Open the site in a real browser, solve the
//      challenge once, copy the cf_clearance cookie + user-agent.
//      Set ANIMEPAHE_CF_CLEARANCE + ANIMEPAHE_USER_AGENT env vars.
//
//   2. Headless browser (recommended for automation):
//      Use Playwright/Puppeteer with the cookie jar persisted.
//      See cf-browser.ts for the browser-based implementation.
//
//   3. HTTP fallback: Some API endpoints work without Cloudflare
//      on certain IPs/nodes. The scraper auto-detects which
//      method works and falls back.

export interface CloudflareSession {
  cfClearance: string;
  userAgent: string;
  expiresAt: number; // epoch ms
}

const CF_CLEARANCE_TTL_MS = 25 * 60 * 1000; // 25 min

let cachedSession: CloudflareSession | null = null;

export function getCloudflareSession(): CloudflareSession | null {
  if (cachedSession && Date.now() < cachedSession.expiresAt) {
    return cachedSession;
  }

  const cfClearance = process.env["ANIMEPAHE_CF_CLEARANCE"];
  const userAgent =
    process.env["ANIMEPAHE_USER_AGENT"] ||
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

  if (cfClearance) {
    cachedSession = {
      cfClearance,
      userAgent,
      expiresAt: Date.now() + CF_CLEARANCE_TTL_MS,
    };
    return cachedSession;
  }

  return null;
}

export function setCloudflareSession(session: CloudflareSession): void {
  cachedSession = {
    ...session,
    expiresAt: Date.now() + CF_CLEARANCE_TTL_MS,
  };
}

export function buildCloudflareHeaders(session: CloudflareSession): Record<string, string> {
  return {
    "User-Agent": session.userAgent,
    Cookie: `cf_clearance=${session.cfClearance}`,
    Accept: "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    Referer: "https://animepahe.pw/",
    Origin: "https://animepahe.pw",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "same-origin",
  };
}

export function isCloudflareBlock(html: string): boolean {
  return (
    html.includes("Just a moment") ||
    html.includes("Attention Required") ||
    html.includes("Cloudflare") ||
    html.length < 1000
  );
}
