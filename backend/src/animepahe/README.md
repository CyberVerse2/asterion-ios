# AnimePahe.pw — Reverse-Engineered API Reference

## Overview

**animepahe.pw** is an anime streaming site that provides a JSON-based REST-ish API for browsing, searching, and streaming anime. The same API powers `animepahe.com` (original domain). Content is sourced from MyAnimeList and served through third-party video hosts (primarily kwik.si).

## Protection

| Layer | Detail |
|-------|--------|
| CDN / DDoS | Cloudflare (104.21.37.233, 172.67.214.176) |
| Challenge | Cloudflare Turnstile **managed challenge** (cType: `managed`) |
| WAF | Blocks all non-browser User-Agents with HTTP 403 |
| Bypass | Requires `cf_clearance` cookie obtained from a real browser session |

The Cloudflare protection returns `403` with either:
- `Just a moment...` (JS challenge page — earlier tier)
- `Attention Required! | Cloudflare` (hard block — current)

Without a valid `cf_clearance` cookie, **no endpoint is accessible via direct HTTP**. The cookie is valid for ~25 minutes.

## Domain & DNS

```
animepahe.pw  → Cloudflare: 104.21.37.233, 172.67.214.176
animepahe.com → Cloudflare: same IPs (identical backend)
animepahe.ru  → Not resolving (dead)
pahe.win      → Video proxy domain (separate Cloudflare zone)
kwik.si       → Primary video host
```

## API Architecture

```
┌─ animepahe.pw ─────────────────────────────────────────────┐
│  GET  /api?m=search&q={query}&page={n}       Search        │
│  GET  /api?m=anime&id={session_id}           Anime detail  │
│  GET  /api?m=release&id={session}&sort=...   Episodes      │
│  GET  /api?m=airing                          Airing now    │
│  GET  /api?m=feed&page={n}                   Recent eps    │
│  GET  /api?m=genre                           Genre list    │
│  POST /pahewin/api?m=anime&id={ep_session}   Video sources │
└────────────────────────────────────────────────────────────┘
```

The API uses `?m=` as a method router. All responses are JSON. No authentication is required.

### Session IDs

animepahe uses **session IDs** (opaque alphanumeric strings) instead of numeric database IDs for API calls. A session ID represents a specific anime or episode within a browser session context.

## Endpoints

### 1. Search Anime

```
GET /api?m=search&q={query}&page={n}
```

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `m` | string | yes | Must be `search` |
| `q` | string | yes | Search query (URL-encoded) |
| `page` | int | no | Page number (default: 1) |

**Response:** `AnimeSearchResponse`

```json
{
  "total": 42,
  "per_page": 15,
  "current_page": 1,
  "last_page": 3,
  "from": 1,
  "to": 15,
  "data": [
    {
      "id": 4598,
      "title": "One Piece",
      "type": "TV",
      "episodes": 1122,
      "season": "Fall 1999",
      "year": 1999,
      "score": 8.72,
      "poster": "/posters/abc123.jpg",
      "session": "a1b2c3d4e5f6...",
      "status": "Currently Airing"
    }
  ]
}
```

---

### 2. Anime Detail

```
GET /api?m=anime&id={session_id}
```

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `m` | string | yes | Must be `anime` |
| `id` | string | yes | Anime session_id from search/feed |

**Response:** `AnimeDetailResponse`

```json
{
  "data": {
    "id": 4598,
    "title": "One Piece",
    "title_english": "One Piece",
    "title_japanese": "ワンピース",
    "type": "TV",
    "episodes": 1122,
    "status": "Currently Airing",
    "aired": "Oct 20, 1999 to ?",
    "premiered": "Fall 1999",
    "producers": ["Fuji TV", "TAP", "Shueisha"],
    "studios": ["Toei Animation"],
    "source": "Manga",
    "genres": ["Action", "Adventure", "Comedy", "Fantasy"],
    "duration": "24 min. per ep.",
    "rating": "PG-13 - Teens 13 or older",
    "score": 8.72,
    "scored_by": 2350000,
    "rank": 42,
    "popularity": 15,
    "members": 3850000,
    "favorites": 182000,
    "synopsis": "Gol D. Roger was known as the Pirate King...",
    "poster": "/posters/abc123.jpg",
    "session": "a1b2c3d4e5f6..."
  }
}
```

---

### 3. Episode List

```
GET /api?m=release&id={session_id}&sort={order}&page={n}
```

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `m` | string | yes | Must be `release` |
| `id` | string | yes | Anime session_id |
| `sort` | string | no | `episode_asc` (default) or `episode_desc` |
| `page` | int | no | Page number (default: 1) |

**Response:** `EpisodeListResponse`

```json
{
  "total": 135,
  "per_page": 30,
  "current_page": 1,
  "last_page": 5,
  "from": 1,
  "to": 30,
  "data": [
    {
      "id": 123456,
      "anime_id": 4598,
      "episode": 1122,
      "snapshot": "/snapshots/xyz789.jpg",
      "session": "e7f8a9b0c1d2...",
      "created_at": "2025-01-15 12:30:00",
      "disc": "1 (1-30)",
      "duration": "24 min",
      "fansub": "SubsPlease",
      "audio": "jpn"
    }
  ]
}
```

---

### 4. Airing Schedule

```
GET /api?m=airing
```

**Parameters:** None required.

**Response:** `AiringResponse`

```json
{
  "data": [
    {
      "id": 4710,
      "title": "Solo Leveling Season 2",
      "poster": "/posters/def456.jpg",
      "session": "solo-leveling-s2-session...",
      "episode": 2,
      "score": 8.9,
      "type": "TV",
      "aired": "Sat Jan 12, 2025"
    }
  ]
}
```

---

### 5. Recent Feed

```
GET /api?m=feed&page={n}
```

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `m` | string | yes | Must be `feed` |
| `page` | int | no | Page number (default: 1) |

**Response:** `FeedResponse`

```json
{
  "total": 5000,
  "per_page": 20,
  "current_page": 1,
  "last_page": 250,
  "data": [
    {
      "id": 4598,
      "title": "One Piece",
      "episode": 1122,
      "type": "TV",
      "season": "Fall 1999",
      "session": "anime-session...",
      "episode_session": "ep-session...",
      "snapshot": "/snapshots/ghi789.jpg",
      "created_at": "2025-01-15 14:00:00",
      "fansub": "SubsPlease",
      "audio": "jpn",
      "duration": "24 min",
      "score": 8.72
    }
  ]
}
```

---

### 6. Genre List

```
GET /api?m=genre
```

**Response:** `GenreListResponse`

```json
{
  "data": [
    { "id": 1, "name": "Action", "count": 2850 },
    { "id": 2, "name": "Adventure", "count": 1920 }
  ]
}
```

---

### 7. Video Sources (Pahewin)

```
POST /pahewin/api?m=anime&id={episode_session_id}

Content-Type: application/x-www-form-urlencoded

Body: _b=1
```

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `m` | string | yes | Must be `anime` |
| `id` | string | yes | Episode session_id (from episode list) |
| `_b` | string | yes | Form body field: must be `1` |

**Response:** The response format varies. Sometimes JSON directly, sometimes embedded in HTML/JS.

The typical extracted data structure:

```json
[
  {
    "id": 9876,
    "session": "video-session...",
    "episode_id": 123456,
    "quality": "1080p",
    "audio": "jpn",
    "source": "kwik",
    "url": "https://kwik.si/f/tokenabc123...",
    "size": 1450000000,
    "type": "mp4"
  },
  {
    "id": 9877,
    "quality": "720p",
    "audio": "eng",
    "source": "kwik",
    "url": "https://kwik.si/f/tokendef456...",
    "size": 800000000,
    "type": "mp4"
  }
]
```

---

## Video Extraction Flow

The complete flow from search to playable video:

```
1. Search            GET  /api?m=search&q=one+piece
       ↓
2. Get episodes      GET  /api?m=release&id={anime_session}
       ↓
3. Get sources       POST /pahewin/api?m=anime&id={ep_session}
       ↓
4. Kwik extraction   GET  https://kwik.si/f/{token}
                         Parse JS: var _v = "m3u8_url"
       ↓
5. Play              HLS/M3U8 manifest URL
```

### Kwik Extraction

The kwik.si page embeds the video URL in JavaScript:

```js
var _v = "https://video-hoster.example/stream/abc123/playlist.m3u8";
```

Extraction steps:
1. Fetch the kwik page
2. Regex match `var _v = "..."` or `<source src="...">`
3. Fallback: POST form with CSRF token + kwik encrypted value

### Alternate Hosts

| Host | Extraction Difficulty | Notes |
|------|----------------------|-------|
| kwik.si | Easy (regex from HTML) | Primary host, 90% of episodes |
| mp4upload | Medium (JS required) | Fallback host |
| streamsb | Hard (browser JS needed) | Rarely used |

---

## Usage

### Method A: Automatic (Recommended) — Browser-Based Cookie Refresh

The `cf-browser.ts` module launches a stealth Chromium browser in the background
that solves Cloudflare's Turnstile challenge automatically and refreshes the
cookie every 20 minutes. **Zero manual intervention.**

```typescript
import { startCookieRefresh, searchAnime, listEpisodes, getStreamUrl } from "./animepahe";

// Start the background cookie refresher once at boot
await startCookieRefresh();

// Now all API calls work transparently — the cookie is auto-refreshed
const results = await searchAnime("Attack on Titan");
// ...
```

**Requirements:** Chrome/Chromium must be installed on the system (npx puppeteer handles this).

**Headful mode (if headless gets detected):** Set `ANIMEPAHE_HEADFUL=true` to open a visible browser window. Close it when done.

**Persistent profile (skip challenge after first solve):**
```bash
export ANIMEPAHE_BROWSER_PROFILE="/tmp/animepahe-profile"
```
The browser saves cookies to disk, so subsequent launches skip the challenge entirely.

**Lifecycle:**
```typescript
// The refresher runs as a background setInterval. Stop when your app shuts down:
import { stopCookieRefresh } from "./animepahe";
process.on("SIGTERM", stopCookieRefresh);
```

### Method B: Manual Cookie (Fallback)

```bash
export ANIMEPAHE_CF_CLEARANCE="your_cf_clearance_cookie_value"
export ANIMEPAHE_USER_AGENT="Mozilla/5.0 ..."  # optional
```

1. Open https://animepahe.pw/ in Chrome
2. Wait for the Cloudflare check to pass (~5s)
3. DevTools → Application → Cookies → `cf_clearance` → copy value
4. Valid for ~25 minutes

### Method C: One-Shot Fetch

```typescript
import { fetchFreshCookie } from "./animepahe";
const session = await fetchFreshCookie();
if (session) {
  console.log("Got cookie:", session.cfClearance);
}
```

### Example

```typescript
import { searchAnime, getAnimeDetail, listEpisodes, getStreamUrl } from "./animepahe";

// Search for anime
const results = await searchAnime("Attack on Titan");
if ("error" in results) throw new Error(results.error);

const anime = results.data[0];
console.log(`Found: ${anime.title} (${anime.episodes} eps, score: ${anime.score})`);

// Get episodes
const episodes = await listEpisodes(anime.session);
if ("error" in episodes) throw new Error(episodes.error);

console.log(`Episodes: ${episodes.data.length} (total: ${episodes.total})`);

// Get video for first episode
const stream = await getStreamUrl(episodes.data[0].session, "720p");
if (typeof stream === "string") {
  console.log(`Stream URL: ${stream}`);
}
```

---

## Rate Limiting

- The API seems to tolerate ~1 request/second without issues
- The built-in client enforces a 1200ms delay between requests
- For bulk scraping, add longer delays (2-3s) and rotate user agents

## Data Model

### Anime Fields Mapped to MAL

AnimePahe mirrors MyAnimeList data. Key mappings:

| AnimePahe Field | MAL Equivalent | Notes |
|----------------|----------------|-------|
| `id` | mal_id | Same numeric ID |
| `score` | score | Same 0-10 scale |
| `scored_by` | scored_by | Number of users |
| `rank` | rank | MAL ranking |
| `popularity` | popularity | MAL popularity # |
| `type` | type | TV/Movie/OVA/ONA/Special |
| `source` | source | Manga/LN/Original/Novel/etc. |

## Notes

- The API responses sometimes wrap the data in an extra array level. The types account for this.
- Episode numbers are 1-indexed (no inconsistencies observed).
- The `session` field is always required for the next API call — never use numeric IDs directly.
- Some anime entries have a `mal_id` field that directly maps to MyAnimeList IDs.
