// ─── AnimePahe API Client ───────────────────────────────────────────
// Complete reverse-engineered client for animepahe.pw JSON API.
//
// ┌──────────────────────────────────────────────────────────────────┐
// │                        API ARCHITECTURE                          │
// ├──────────────────────────────────────────────────────────────────┤
// │ Base URL:   https://animepahe.pw (or .com, same backend)         │
// │ API style:  REST-ish JSON via ?m= parameter routing              │
// │ Auth:       None (public API)                                    │
// │ Protection: Cloudflare Turnstile managed challenge (403 hard)     │
// │             Requires cf_clearance cookie from a real browser      │
// ├──────────────────────────────────────────────────────────────────┤
// │ Endpoints:                                                       │
// │   GET /api?m=search&q={query}&page={n}                           │
// │   GET /api?m=anime&id={session_id}                               │
// │   GET /api?m=release&id={session_id}&sort=episode_asc&page={n}   │
// │   GET /api?m=airing                                              │
// │   GET /api?m=feed&page={n}                                       │
// │   GET /api?m=genre                                               │
// │   POST /pahewin/api?m=anime&id={ep_session}   (video sources)    │
// ├──────────────────────────────────────────────────────────────────┤
// │ Data flow for watching an episode:                               │
// │   1. Search anime -> get anime session_id                        │
// │   2. /api?m=release&id={session} -> get episodes with sessions   │
// │   3. POST /pahewin/api?m=anime&id={ep_session} -> get video URLs │
// │   4. Extract kwik.si page -> get M3U8 manifest                   │
// └──────────────────────────────────────────────────────────────────┘
//
// All responses are wrapped in top-level arrays with metadata.

import type {
  AnimeSearchResponse,
  AnimeDetailResponse,
  EpisodeListResponse,
  FeedResponse,
  GenreListResponse,
  AiringResponse,
  PahewinAnimeResponse,
  PahewinVideoSource,
} from "./types";
import {
  getCloudflareSession,
  buildCloudflareHeaders,
  isCloudflareBlock,
  type CloudflareSession,
} from "./cf-bypass";
import { resolveVideoUrl } from "./kwik";

// ─── Configuration ──────────────────────────────────────────────────

const BASE_URL = "https://animepahe.pw";
const PAHEWIN_URL = "https://pahe.win"; // video proxy domain
const REQUEST_DELAY_MS = 1200;

let lastRequestTime = 0;

// Global fetch override — inject browserFetch for cookie/TLS matching
let _globalFetch: typeof fetch | null = null;
export function setGlobalFetch(fn: typeof fetch): void {
  _globalFetch = fn;
}

async function rateLimit(): Promise<void> {
  const now = Date.now();
  const elapsed = now - lastRequestTime;
  if (elapsed < REQUEST_DELAY_MS) {
    await new Promise((r) => setTimeout(r, REQUEST_DELAY_MS - elapsed));
  }
  lastRequestTime = Date.now();
}

// ─── HTTP Transport ─────────────────────────────────────────────────

interface FetchOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string | null;
}

async function apiFetch(
  path: string,
  options: FetchOptions = {},
  customFetch?: typeof fetch
): Promise<Response> {
  await rateLimit();

  const session = getCloudflareSession();
  const defaultHeaders = session
    ? buildCloudflareHeaders(session)
    : {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        Accept: "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        Referer: "https://animepahe.pw/",
      };

  const url = path.startsWith("http") ? path : `${BASE_URL}${path}`;
  const fn = customFetch ?? _globalFetch ?? fetch;

  const init: RequestInit = {
    method: options.method ?? "GET",
    headers: { ...defaultHeaders, ...options.headers },
    redirect: "follow",
  };
  if (options.body !== undefined && options.body !== null) {
    init.body = options.body;
  }
  return fn(url, init);
}

async function apiFetchJson<T>(
  path: string,
  options: FetchOptions = {},
  customFetch?: typeof fetch
): Promise<T | { error: string }> {
  const resp = await apiFetch(path, options, customFetch);

  if (!resp.ok) {
    const text = await resp.text();
    if (isCloudflareBlock(text)) {
      return { error: "Cloudflare blocked request. Set ANIMEPAHE_CF_CLEARANCE env var." };
    }
    return { error: `HTTP ${resp.status}: ${text.slice(0, 200)}` };
  }

  const text = await resp.text();
  if (isCloudflareBlock(text)) {
    return { error: "Cloudflare blocked request. Set ANIMEPAHE_CF_CLEARANCE env var." };
  }

  try {
    return JSON.parse(text) as T;
  } catch {
    return { error: `JSON parse error: ${text.slice(0, 200)}` };
  }
}

// ─── API Methods ────────────────────────────────────────────────────

/**
 * Search for anime by title.
 * Endpoint: GET /api?m=search&q={query}&page={n}
 */
export async function searchAnime(
  query: string,
  page = 1,
  customFetch?: typeof fetch
): Promise<AnimeSearchResponse | { error: string }> {
  const q = encodeURIComponent(query.trim());
  return apiFetchJson<AnimeSearchResponse>(
    `/api?m=search&q=${q}&page=${page}`,
    {},
    customFetch
  );
}

/**
 * Get detailed info for an anime by its session_id.
 * Endpoint: GET /api?m=anime&id={session}
 *
 * The session_id comes from search results or the airing list.
 */
export async function getAnimeDetail(
  sessionId: string,
  customFetch?: typeof fetch
): Promise<AnimeDetailResponse | { error: string }> {
  return apiFetchJson<AnimeDetailResponse>(
    `/api?m=anime&id=${encodeURIComponent(sessionId)}`,
    {},
    customFetch
  );
}

/**
 * List episodes for an anime by its session_id.
 * Endpoint: GET /api?m=release&id={session}&sort=episode_{asc|desc}&page={n}
 *
 * Returns episode list with their own session_ids for video extraction.
 */
export async function listEpisodes(
  sessionId: string,
  page = 1,
  sort: "episode_asc" | "episode_desc" = "episode_asc",
  customFetch?: typeof fetch
): Promise<EpisodeListResponse | { error: string }> {
  return apiFetchJson<EpisodeListResponse>(
    `/api?m=release&id=${encodeURIComponent(sessionId)}&sort=${sort}&page=${page}`,
    {},
    customFetch
  );
}

/**
 * Get currently airing anime list.
 * Endpoint: GET /api?m=airing
 */
export async function getAiring(
  customFetch?: typeof fetch
): Promise<AiringResponse | { error: string }> {
  return apiFetchJson<AiringResponse>("/api?m=airing", {}, customFetch);
}

/**
 * Get recent episode releases (feed).
 * Endpoint: GET /api?m=feed&page={n}
 */
export async function getFeed(
  page = 1,
  customFetch?: typeof fetch
): Promise<FeedResponse | { error: string }> {
  return apiFetchJson<FeedResponse>(
    `/api?m=feed&page=${page}`,
    {},
    customFetch
  );
}

/**
 * Get list of all genres.
 * Endpoint: GET /api?m=genre
 */
export async function getGenres(
  customFetch?: typeof fetch
): Promise<GenreListResponse | { error: string }> {
  return apiFetchJson<GenreListResponse>("/api?m=genre", {}, customFetch);
}

// ─── Video Extraction ───────────────────────────────────────────────

/**
 * Get video sources for a specific episode.
 * Endpoint: POST /pahewin/api?m=anime&id={episode_session}
 *
 * NOTE: This uses pahe.win (a separate domain) which handles the
 * actual video host redirects. The response contains URLs for
 * different qualities and audio tracks (usually kwik.si links).
 *
 * The POST body is form-encoded: _b=1
 * The response is JSON wrapped in HTML comments/JS, requires parsing.
 */
export async function getEpisodeSources(
  episodeSessionId: string,
  customFetch?: typeof fetch
): Promise<PahewinVideoSource[] | { error: string }> {
  const formData = new URLSearchParams();
  formData.set("_b", "1");

  const resp = await apiFetch(
    `/pahewin/api?m=anime&id=${encodeURIComponent(episodeSessionId)}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        Accept: "*/*",
        "X-Requested-With": "XMLHttpRequest",
        Referer: `https://animepahe.pw/play/${episodeSessionId}`,
      },
      body: formData.toString(),
    },
    customFetch
  );

  if (!resp.ok) {
    const text = await resp.text();
    if (isCloudflareBlock(text)) {
      return { error: "Cloudflare blocked request." };
    }
    return { error: `HTTP ${resp.status}` };
  }

  const html = await resp.text();
  if (isCloudflareBlock(html)) {
    return { error: "Cloudflare blocked request." };
  }

  // Parse the JSON response (may contain HTML comments)
  try {
    const jsonMatch = html.match(/\{[\s\S]*"data"[\s\S]*\}/);
    if (jsonMatch) {
      const parsed: PahewinAnimeResponse = JSON.parse(jsonMatch[0]);
      return parsed.data.flatMap((ep) => ep.video ?? []);
    }
    return JSON.parse(html);
  } catch (err) {
    // Some responses are embedded in JS:
    // window.pahewin = [...]
    const pahewinMatch = html.match(
      /pahewin\s*=\s*(\[[\s\S]*?\])\s*;/
    );
    const pahewinJson = pahewinMatch?.[1];
    if (pahewinJson) {
      try {
        return JSON.parse(pahewinJson);
      } catch {
        return { error: "Failed to parse pahewin response" };
      }
    }
    return { error: `Parse error: ${html.slice(0, 300)}` };
  }
}

/**
 * High-level: get a playable stream URL for an episode.
 * Resolves through pahewin -> kwik -> M3U8.
 */
export async function getStreamUrl(
  episodeSessionId: string,
  preferredQuality?: string,
  preferredAudio?: string,
  customFetch?: typeof fetch
): Promise<string | { error: string }> {
  const sources = await getEpisodeSources(episodeSessionId, customFetch);
  if ("error" in sources) return sources;

  if (sources.length === 0) {
    return { error: "No video sources found" };
  }

  // Filter by preferences
  let best = sources[0];
  if (preferredQuality || preferredAudio) {
    const filtered = sources.filter((s) => {
      const qMatch = !preferredQuality || s.quality === preferredQuality;
      const aMatch = !preferredAudio || s.audio === preferredAudio;
      return qMatch && aMatch;
    });
    if (filtered.length > 0) best = filtered[0];
    // fallback to any if no match
  }

  if (!best) {
    return { error: "No matching source" };
  }

  const resolved = await resolveVideoUrl(best.url, customFetch);
  if (!resolved) {
    return { error: `Could not resolve video URL for ${best.source}` };
  }

  return resolved;
}

// ─── Batch Helpers ──────────────────────────────────────────────────

/**
 * Fetch all pages of episodes for an anime.
 */
export async function listAllEpisodes(
  sessionId: string,
  customFetch?: typeof fetch
): Promise<EpisodeListResponse["data"] | { error: string }> {
  const allEpisodes: EpisodeListResponse["data"] = [];
  let page = 1;

  while (true) {
    const result = await listEpisodes(sessionId, page, "episode_asc", customFetch);
    if ("error" in result) return result;

    allEpisodes.push(...result.data);

    if (page >= result.last_page) break;
    page++;
  }

  return allEpisodes;
}

// ─── Convenience ────────────────────────────────────────────────────

/**
 * Build the poster URL from a relative path.
 * animepahe stores posters as "/posters/{hash}.jpg"
 */
export function posterUrl(relativePath: string): string {
  if (!relativePath) return "";
  if (relativePath.startsWith("http")) return relativePath;
  return `https://animepahe.pw${relativePath}`;
}

/**
 * Build the anime page URL from session_id and title slug.
 * Used for the web view / sharing.
 */
export function animePageUrl(
  sessionId: string,
  title?: string
): string {
  const slug = title
    ? title
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/(^-|-$)/g, "")
    : "anime";
  return `https://animepahe.pw/anime/${sessionId}/${slug}`;
}
