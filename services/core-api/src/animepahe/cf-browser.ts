import puppeteer from "puppeteer-extra";
import StealthPlugin from "puppeteer-extra-plugin-stealth";
import type { Browser, Page, CookieParam } from "puppeteer";
import { setCloudflareSession, type CloudflareSession } from "./cf-bypass";
import fs from "node:fs";
import Database from "better-sqlite3";

puppeteer.use(StealthPlugin());

const REFRESH_INTERVAL_MS = 20 * 60 * 1000;
const CHALLENGE_MAX_WAIT_MS = 45_000;
const CHALLENGE_POLL_MS = 2000;
const NAV_TIMEOUT_MS = 30_000;
const PROFILE_DIR =
  process.env["ANIMEPAHE_BROWSER_PROFILE"] ?? "/tmp/animepahe-browser-profile";
const COOKIE_CACHE_FILE = "/tmp/animepahe-cf-cookie.txt";

let browser: Browser | null = null;
let apiPage: Page | null = null; // persistent page kept open for API calls
let refreshTimer: ReturnType<typeof setInterval> | null = null;
let running = false;

// ─── Cookie Cache ──────────────────────────────────────────────────

function readCachedCookie(): string | null {
  try {
    if (!fs.existsSync(COOKIE_CACHE_FILE)) return null;
    const data = JSON.parse(fs.readFileSync(COOKIE_CACHE_FILE, "utf8")) as { cookie: string; expires: number };
    if (Date.now() < data.expires) return data.cookie;
    fs.unlinkSync(COOKIE_CACHE_FILE);
    return null;
  } catch { return null; }
}

function writeCachedCookie(cookie: string): void {
  fs.writeFileSync(COOKIE_CACHE_FILE, JSON.stringify({ cookie, expires: Date.now() + 25 * 60 * 1000 }), "utf8");
}

// ─── Profile Cookie Reader ─────────────────────────────────────────

function readProfileCookies(): string | null {
  const cached = readCachedCookie();
  if (cached) return cached;

  const cookieDb = `${PROFILE_DIR}/Default/Cookies`;
  if (!fs.existsSync(cookieDb)) return null;

  try {
    const db = new Database(cookieDb, { readonly: true });
    const row = db
      .prepare("SELECT value FROM cookies WHERE host_key LIKE '%animepahe%' AND name = 'cf_clearance' ORDER BY creation_utc DESC LIMIT 1")
      .get() as { value: string } | undefined;
    db.close();
    if (row?.value) return row.value;
  } catch { /* encrypted */ }
  return null;
}

// ─── Browser Management ────────────────────────────────────────────

async function launchBrowser(headful: boolean): Promise<Browser> {
  if (browser?.connected) return browser;
  browser = await puppeteer.launch({
    headless: !headful,
    userDataDir: PROFILE_DIR,
    args: [
      "--no-sandbox", "--disable-setuid-sandbox",
      "--disable-blink-features=AutomationControlled",
      "--disable-features=IsolateOrigins,site-per-process",
      "--disable-site-isolation-trials",
      "--window-size=1440,900", "--disable-gpu",
    ],
  });
  return browser;
}

async function tryGetCookie(page: Page): Promise<string | null> {
  const start = Date.now();
  while (Date.now() - start < CHALLENGE_MAX_WAIT_MS) {
    await new Promise((r) => setTimeout(r, CHALLENGE_POLL_MS));
    const cookies = await page.cookies();
    const cf = cookies.find((c) => c.name === "cf_clearance");
    if (cf?.value) return cf.value;

    const title = await page.title().catch(() => "");
    if (!title.includes("Just a moment") && !title.includes("Attention Required") && !page.url().includes("__cf_chl")) {
      const c2 = await page.cookies();
      const cf2 = c2.find((c) => c.name === "cf_clearance");
      if (cf2?.value) return cf2.value;
    }
  }
  return null;
}

async function solveOnce(page: Page): Promise<string | null> {
  try {
    await page.goto("https://animepahe.pw/", { waitUntil: "domcontentloaded", timeout: NAV_TIMEOUT_MS });
  } catch { /* timeout ok */ }
  return tryGetCookie(page);
}

async function solveOnceWithTimeout(page: Page, timeoutMs: number): Promise<string | null> {
  try {
    await page.goto("https://animepahe.pw/", { waitUntil: "domcontentloaded", timeout: NAV_TIMEOUT_MS });
  } catch { /* ok */ }
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    await new Promise((r) => setTimeout(r, CHALLENGE_POLL_MS));
    const cookies = await page.cookies();
    const cf = cookies.find((c) => c.name === "cf_clearance");
    if (cf?.value) return cf.value;
    const title = await page.title().catch(() => "");
    if (!title.includes("Just a moment") && !title.includes("Attention Required") && !page.url().includes("__cf_chl")) return null;
  }
  return null;
}

async function solveHeadful(): Promise<string | null> {
  let page: Page | null = null;
  try {
    const b = await launchBrowser(true);
    page = await b.newPage();
    await page.setViewport({ width: 1200, height: 800 });
    await page.evaluateOnNewDocument(() => {
      const observer = new MutationObserver(() => {
        if (document.body && !document.getElementById("_ast_cf_msg")) {
          const el = document.createElement("div");
          el.id = "_ast_cf_msg";
          el.style.cssText = "position:fixed;top:20px;left:50%;transform:translateX(-50%);z-index:9999999;background:#7c3aed;color:#fff;padding:16px 32px;border-radius:12px;font:bold 16px system-ui;pointer-events:none;text-align:center;box-shadow:0 4px 24px rgba(124,58,237,0.5);animation:_ast_pulse 2s ease-in-out infinite;";
          el.innerHTML = "\u26a1 Asterion — Solving Cloudflare...<br><span style='font-size:12px;font-weight:400;opacity:0.8'>If asked, click Verify you are human</span>";
          document.body.appendChild(el);
          const style = document.createElement("style");
          style.textContent = "@keyframes _ast_pulse{0%,100%{opacity:1}50%{opacity:0.6}}";
          document.head.appendChild(style);
        }
      });
      observer.observe(document, { childList: true, subtree: true });
    });
    const result = await solveOnce(page);
    await page.close().catch(() => {});
    await b.close().catch(() => {});
    browser = null;
    // Wait for browser process to fully exit before any new launch
    await new Promise(r => setTimeout(r, 3000));
    return result;
  } catch {
    if (page) await page.close().catch(() => {});
    await new Promise(r => setTimeout(r, 3000));
    return null;
  }
}

// ─── Browser-Based Fetch (runs inside real browser context) ────────

async function ensureApiPage(): Promise<Page> {
  if (apiPage && !apiPage.isClosed()) return apiPage;

  const b = await launchBrowser(false);
  apiPage = await b.newPage();
  await apiPage.setViewport({ width: 1440, height: 900 });

  // Navigate to animepahe to establish the origin context
  await apiPage.goto("https://animepahe.pw/", { waitUntil: "domcontentloaded", timeout: 10000 }).catch(() => {});

  // The profile should have the cookie from the solve step. If not, wait briefly.
  const cookies = await apiPage.cookies();
  const cf = cookies.find((c) => c.name === "cf_clearance");
  if (!cf?.value) {
    console.log("[cf] API page waiting for cookie...");
    const solved = await tryGetCookie(apiPage);
    if (!solved) throw new Error("Cannot establish API session — Cloudflare still blocking");
  } else {
    console.log("[cf] API page ready with cookie");
  }

  return apiPage;
}

/**
 * Make an HTTP request through the live puppeteer browser context.
 * Returns a Response-like object compatible with the native fetch API.
 */
export async function browserFetch(input: string | URL, options?: { method?: string; headers?: Record<string, string>; body?: string | null }): Promise<Response> {
  const url = typeof input === "string" ? input : input.toString();
  const page = await ensureApiPage();

  const result = await page.evaluate(async ({ url, method, headers, body }) => {
    try {
      const init: any = {
        method: method || "GET",
        headers: { Accept: "application/json, text/plain, */*", ...headers },
      };
      if (body) init.body = body;
      const resp = await fetch(url, init);
      const text = await resp.text();
      const respHeaders: Record<string, string> = {};
      resp.headers.forEach((v, k) => { respHeaders[k] = v; });
      return { ok: resp.ok, status: resp.status, text, headers: respHeaders, error: null as string | null };
    } catch (e: any) {
      return { ok: false, status: 0, text: "", headers: {}, error: e.message || "fetch error" };
    }
  }, { url, method: options?.method || "GET", headers: options?.headers || {}, body: options?.body || "" });

  // Return a Response-like wrapper
  return {
    ok: result.ok,
    status: result.status,
    headers: new Headers(result.headers),
    text: async () => result.text,
    json: async () => JSON.parse(result.text),
  } as Response;
}

// ─── Cookie Refresh ────────────────────────────────────────────────

async function refreshCookie(): Promise<boolean> {
  try {
    const diskCookie = readProfileCookies();
    if (diskCookie) {
      setCloudflareSession({ cfClearance: diskCookie, userAgent: "", expiresAt: Date.now() + 25 * 60 * 1000 });
      console.log("[cf] Cookie from cache (no browser needed)");
      return true;
    }

    console.log("[cf] Quick headless attempt...");
    try {
      const b = await launchBrowser(false);
      const page = await b.newPage();
      await page.setViewport({ width: 1440, height: 900 });
      const cookie = await solveOnceWithTimeout(page, 15000);
      if (cookie) {
        writeCachedCookie(cookie);
        setCloudflareSession({ cfClearance: cookie, userAgent: "", expiresAt: Date.now() + 25 * 60 * 1000 });
        console.log("[cf] Headless solved!");
        await page.close().catch(() => {});
        return true;
      }
      console.log("[cf] Headless blocked.");
      await page.close().catch(() => {});
      await b.close().catch(() => {});
      browser = null;
    } catch (e) { console.log("[cf] Headless error:", (e as Error).message); }

    if (process.env["ANIMEPAHE_NO_HEADFUL"] === "true") {
      console.error("[cf] Blocked and NO_HEADFUL set. Cannot proceed.");
      return false;
    }

    console.log("[cf] Opening visible browser...");
    const hfCookie = await solveHeadful();
    if (hfCookie) {
      writeCachedCookie(hfCookie);
      setCloudflareSession({ cfClearance: hfCookie, userAgent: "", expiresAt: Date.now() + 25 * 60 * 1000 });
      console.log("[cf] Cookie saved to cache.");
      return true;
    }

    return false;
  } catch (err) {
    console.error("[cf] Error:", err);
    return false;
  }
}

// ─── Public API ─────────────────────────────────────────────────────

export async function startCookieRefresh(): Promise<boolean> {
  if (running) return true;
  running = true;
  console.log("[cf] Starting auto-refresh (every 20m)");

  const ok = await refreshCookie();
  if (!ok) console.error("[cf] Initial cookie acquisition failed");

  // Start API page in background
  ensureApiPage().then(() => console.log("[cf] API page ready")).catch(e => console.error("[cf] API page error:", e));

  refreshTimer = setInterval(async () => {
    console.log("[cf] Refreshing cookie...");
    const result = await refreshCookie();
    if (!result) console.error("[cf] Refresh failed");
    // Re-create API page if needed
    if (apiPage?.isClosed()) {
      apiPage = null;
      ensureApiPage().catch(() => {});
    }
  }, REFRESH_INTERVAL_MS);

  return ok;
}

export async function stopCookieRefresh(): Promise<void> {
  running = false;
  if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
  if (apiPage) { await apiPage.close().catch(() => {}); apiPage = null; }
  if (browser) { await browser.close().catch(() => {}); browser = null; }
  console.log("[cf] Stopped");
}

export function isRefreshRunning(): boolean { return running; }

export async function fetchFreshCookie(): Promise<CloudflareSession | null> {
  const ok = await refreshCookie();
  if (!ok) return null;
  return (await import("./cf-bypass")).getCloudflareSession();
}

process.on("exit", () => { if (refreshTimer) clearInterval(refreshTimer); });
