# Asterion novels scraper

Keeps the `novels` and `chapters` tables (owned by `services/core-api`) in step with novelfire.net.
It is a long-lived Node 22 service with its own daily schedule; it replaces the hand-run
`asterion-scraper` project.

## How a pass works

For every novel whose `novel_url` is on novelfire.net:

1. Fetch the book page and refresh metadata (`total_chapters`, `status`, `rating`, `views`,
   `bookmarks`, `rank`, `genres`, `summary`, `image_url`, `author`, `chapters_url`). Only columns
   whose value changed are written. A value is never blanked, and the title is never changed.
2. Fetch page 1 of `/chapters`. Its "Latest Release" link gives the highest chapter URL number.
3. Compare `1..latest` with the chapter numbers already stored (with non-empty content). Fetch only
   the missing ones: new chapters at the end first, then holes. At most `MAX_CHAPTERS_PER_NOVEL`
   are fetched per novel per pass, so a big backlog fills in over a few passes.
4. Each chapter is upserted on `(novel_id, chapter_number)` as soon as it is fetched. Content is
   only overwritten when the new content is non-empty. Ads and scripts are removed from `#content`
   before it is stored.
5. A fetch that fails, returns 404/500, or comes back with empty content counts as a **miss**. A
   miss is never stored as an empty chapter. It goes into `novel_scraper.misses` and is retried
   with back-off: after 12 h, then 24 h, then 48 h, and so on, up to 30 days.

Each novel runs on its own, so one bad novel cannot stop the pass. If a novel fails 5 times in a
row before any chapter succeeds, the pass stops working on that novel until the next pass. This
happens with novels taken down from novelfire: their book page is a 404 and every chapter is a
500. If novelfire keeps answering 403/429 even after retries, the whole pass is aborted.

HTTP rules: one request slot every `REQUEST_INTERVAL_MS` across the whole process, with jitter. At
most `MAX_IN_FLIGHT` requests run at once. Failed requests are retried with exponential back-off.
A 429 pauses every request (honouring `Retry-After`) and widens the spacing. A 403 triggers a
cookie warm-up. `PROXY_URL` is optional. Transient database errors (connection refused or reset,
the server restarting) are retried for about a minute.

Only one pass runs at a time. The process refuses a second pass, and a PostgreSQL advisory lock
stops a CLI pass and the service from overlapping.

### Service-owned tables

These tables live in schema `novel_scraper` (outside `public`, so drizzle never sees them) and are
created on first start:

- `novel_scraper.runs`: one row per pass (trigger, status, options, summary JSON, timings).
- `novel_scraper.misses`: chapters that could not be fetched, with their back-off state.

## Schedule

- Daily at `SCHEDULE_HOUR_UTC:SCHEDULE_MINUTE_UTC` (default 04:00 UTC).
- On start, if the last completed **full** pass is older than `RUN_INTERVAL_HOURS` (or none
  exists), a catch-up pass starts `STARTUP_RUN_DELAY_SECONDS` after boot. A full pass covers every
  novel with no `maxChapters` cap. Targeted or capped runs from `POST /run` or the CLI do not count.
- If a scheduled slot comes up while a pass is still running, that slot is skipped.

## HTTP

Port `PORT` (default **8080**).

- `GET /health` returns `200` with `{ status, database, running, progress, nextRunAt, lastRun }`.
- `POST /run` starts a pass. It needs `Authorization: Bearer $NOVEL_SCRAPER_TOKEN` (or an
  `X-Scraper-Token` header). It answers `202` when the pass starts, `409` when one is already
  running, `401` for a bad token, and `503` when no token is configured. The optional JSON body is
  `{ "dryRun": bool, "probe": bool, "novelIds": [1, 2], "slugs": ["shadow-slave"],
  "maxChaptersPerNovel": n, "maxChapters": n }`.

```sh
curl -X POST https://<host>/run -H "Authorization: Bearer $NOVEL_SCRAPER_TOKEN"
curl -X POST https://<host>/run -H "Authorization: Bearer $NOVEL_SCRAPER_TOKEN" \
  -H 'Content-Type: application/json' -d '{"slugs":["shadow-slave"],"maxChapters":30}'
curl https://<host>/health
```

Each pass logs one line per novel and a closing summary: novels updated, chapters added,
misses, errors, and novels that are unavailable.

## CLI (one pass, then exit)

```sh
npm run build
node dist/cli.js --dry-run --probe --novel 923 --novel shadow-slave   # read-only report
node dist/cli.js --novel shadow-slave --max-chapters 30               # small real pass
node dist/cli.js                                                       # full pass
```

`--dry-run` writes nothing (it does not even create the `novel_scraper` schema). `--probe` also
fetches the first planned chapter of each novel, to show whether novelfire still serves it.

## Environment

| Variable | Default | |
| --- | --- | --- |
| `DATABASE_URL` | required | PostgreSQL holding `novels`/`chapters` |
| `NOVEL_SCRAPER_TOKEN` | unset | Bearer token for `POST /run` (manual runs are disabled when unset) |
| `PROXY_URL` | unset | HTTP(S) proxy for novelfire requests (`HTTPS_PROXY` is also read) |
| `PORT` / `HOST` | `8080` / `0.0.0.0` | |
| `SCHEDULER_ENABLED` | `true` | |
| `SCHEDULE_HOUR_UTC` / `SCHEDULE_MINUTE_UTC` | `4` / `0` | |
| `RUN_INTERVAL_HOURS` | `24` | Age that makes a startup catch-up pass run |
| `STARTUP_RUN_DELAY_SECONDS` | `120` | |
| `REQUEST_INTERVAL_MS` | `1000` | Minimum spacing between requests |
| `MAX_IN_FLIGHT` | `3` | Concurrent HTTP requests |
| `NOVEL_CONCURRENCY` / `CHAPTER_CONCURRENCY` | `2` / `2` | |
| `HTTP_TIMEOUT_MS` / `HTTP_MAX_RETRIES` | `30000` / `3` | |
| `MAX_CHAPTERS_PER_NOVEL` | `500` | Per pass |
| `MAX_CHAPTERS_PER_RUN` | `0` (unlimited) | |
| `MISS_RETRY_BASE_HOURS` / `MISS_RETRY_MAX_DAYS` | `12` / `30` | Miss back-off |
| `MIN_CONTENT_CHARS` | `30` | Less visible text than this counts as empty |
| `CIRCUIT_BREAKER_FAILURES` | `5` | Consecutive failures before a novel is skipped for the pass |
| `LOG_LEVEL` | `info` | |

## Development

```sh
npm install
npm test          # parser + planner tests on saved HTML fixtures (test/fixtures)
npm run typecheck
npm run build
```

Deploy: `openship/novels/Dockerfile` (build context is the repo root).
