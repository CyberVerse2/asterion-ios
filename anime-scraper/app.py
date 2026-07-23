"""
9anime browser — Flask app with built-in frontend.
Install: pip install flask
Run:     python app.py
Open:    http://localhost:8080
"""

import logging
import os
import re
from functools import wraps
from urllib.error import HTTPError
from urllib.parse import quote, urljoin, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

import flask
import nineanime
import animixplay
from werkzeug.exceptions import HTTPException

app = flask.Flask(__name__)

ALLOWED_VIDEO_HOSTS = frozenset({
    "my.1anime.site",
    "vidtube.site",
    "megaplay.buzz",
    "vidwish.live",
    "p1.ipstatp.com",
    "p16-ad-sg.ibyteimg.com",
})
ALLOWED_VIDEO_HOST_SUFFIXES = (
    ".anivideo.sbs",
    ".kotocdn.site",
    ".lostproject.club",
    ".nekostream.site",
    ".watching.onl",
    ".cloudbuzz.lol",
)
MAXIMUM_SUBTITLE_SIZE = 5 * 1024 * 1024


def _is_allowed_video_url(value):
    try:
        parsed = urlparse(value)
    except ValueError:
        return False
    hostname = parsed.hostname
    return (
        parsed.scheme == "https"
        and hostname is not None
        and (
            hostname in ALLOWED_VIDEO_HOSTS
            or any(hostname.endswith(suffix) for suffix in ALLOWED_VIDEO_HOST_SUFFIXES)
        )
        and parsed.username is None
        and parsed.password is None
    )


class _RestrictedRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not _is_allowed_video_url(newurl):
            raise HTTPError(newurl, 502, "Blocked video redirect", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


video_opener = build_opener(_RestrictedRedirectHandler())


def _hls_request_headers(target):
    hostname = (urlparse(target).hostname or "").lower()
    if hostname == "vidwish.live" or hostname.endswith(
        (".anivideo.sbs", ".watching.onl", ".cloudbuzz.lol")
    ):
        provider_origin = "https://vidwish.live"
    elif hostname == "mt.nekostream.site":
        provider_origin = "https://vidtube.site"
    elif (
        hostname == "megaplay.buzz"
        or hostname == "mewstream.buzz"
        or hostname.endswith(".mewstream.buzz")
        or hostname == "p16-ad-sg.ibyteimg.com"
        or hostname.endswith(".lostproject.club")
        or hostname.endswith(".nekostream.site")
    ):
        provider_origin = "https://megaplay.buzz"
    else:
        provider_origin = "https://vidtube.site"

    return {
        "User-Agent": "Mozilla/5.0",
        "Origin": provider_origin,
        "Referer": provider_origin + "/",
    }


def _proxied_hls_path(resource_url):
    endpoint = "/proxy/m3u8" if ".m3u8" in resource_url.lower() else "/proxy/ts"
    return f"{endpoint}?url={quote(resource_url, safe='')}"


def _rewrite_hls_attribute_urls(line, playlist_url):
    def replace_uri(match):
        resource_url = urljoin(playlist_url, match.group(1))
        return f'URI="{_proxied_hls_path(resource_url)}"'

    return re.sub(r'URI="([^"]+)"', replace_uri, line)


def _proxied_subtitle_tracks(tracks):
    proxied = []
    for track in tracks:
        item = dict(track)
        source = item.get("file", "")
        if _is_allowed_video_url(source):
            item["file"] = f"/proxy/subtitle?url={quote(source, safe='')}"
        proxied.append(item)
    return proxied

# ---------------------------------------------------------------------------
# API endpoints
# ---------------------------------------------------------------------------

def _json_or_error(fn):
    """Return scraper results as JSON without exposing internal failures."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return flask.jsonify(fn(*args, **kwargs))
        except HTTPException:
            raise
        except Exception:
            app.logger.exception("Anime scraper request failed")
            return flask.jsonify({"error": "The anime source request failed."}), 502
    return wrapper


@app.after_request
def add_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    return response


@app.route("/api/health")
def api_health():
    return {"status": "ok"}


@app.route("/api/recent")
@_json_or_error
def api_recent():
    return [r.__dict__ for r in nineanime.recently_updated()]


@app.route("/api/popular")
@_json_or_error
def api_popular():
    return [r.__dict__ for r in nineanime.popular()]


@app.route("/api/trending")
@_json_or_error
def api_trending():
    return [r.__dict__ for r in nineanime.trending()]


@app.route("/api/top-rated")
@_json_or_error
def api_top_rated():
    return [r.__dict__ for r in nineanime.top_rated()]


@app.route("/api/recently-added")
@_json_or_error
def api_recently_added():
    return [r.__dict__ for r in nineanime.recently_added()]


@app.route("/api/filter")
@_json_or_error
def api_filter():
    return [r.__dict__ for r in nineanime.filtered(
        sort=flask.request.args.get("sort", ""),
        type_=flask.request.args.get("type", ""),
        status=flask.request.args.get("status", ""),
        genre=flask.request.args.get("genre", ""),
        page=int(flask.request.args.get("page", "1")),
    )]


@app.route("/api/search")
@_json_or_error
def api_search():
    q = flask.request.args.get("q", "").strip()
    if not q:
        return []
    return [r.__dict__ for r in nineanime.search(q)]


@app.route("/api/show/<slug>")
@_json_or_error
def api_show(slug):
    return nineanime.show_detail(slug).__dict__


@app.route("/api/episodes/<series_id>")
@_json_or_error
def api_episodes(series_id):
    return [e.__dict__ for e in nineanime.episodes(series_id)]


@app.route("/api/genre/<genre>")
@_json_or_error
def api_genre(genre):
    return [r.__dict__ for r in nineanime.by_genre(genre)]


@app.route("/api/season/<slug>")
@_json_or_error
def api_season(slug):
    return [r.__dict__ for r in nineanime.by_season(slug)]


@app.route("/api/genres")
@_json_or_error
def api_genres():
    return nineanime.ALL_GENRES


@app.route("/api/stream/<episode_id>")
@_json_or_error
def api_stream(episode_id):
    sources = nineanime.episode_streams(episode_id)
    result = []
    for s in sources:
        d = dict(s.__dict__)
        if d.get("direct_url"):
            d["direct_url"] = f"/proxy/video?url={d['direct_url']}"
        result.append(d)
    return result


# ---------------------------------------------------------------------------
# Animixplay API
# ---------------------------------------------------------------------------

def _positive_page_arg():
    return max(1, int(flask.request.args.get("page", "1")))

@app.route("/api/amp/search")
@_json_or_error
def api_amp_search():
    q = flask.request.args.get("q", "").strip()
    if not q:
        return []
    return [r.__dict__ for r in animixplay.search(q, page=_positive_page_arg())]


@app.route("/api/amp/popular")
@_json_or_error
def api_amp_popular():
    return [r.__dict__ for r in animixplay.popular(page=_positive_page_arg())]


@app.route("/api/amp/latest")
@_json_or_error
def api_amp_latest():
    return [r.__dict__ for r in animixplay.latest_updated(page=_positive_page_arg())]


@app.route("/api/amp/releases")
@_json_or_error
def api_amp_releases():
    return [r.__dict__ for r in animixplay.new_releases(page=_positive_page_arg())]


@app.route("/api/amp/genre/<genre>")
@_json_or_error
def api_amp_genre(genre):
    if genre not in animixplay.ALL_GENRES:
        return flask.abort(404)
    return [r.__dict__ for r in animixplay.by_genre(genre, page=_positive_page_arg())]


@app.route("/api/amp/season")
@_json_or_error
def api_amp_season():
    season = flask.request.args.get("season", "").strip().lower()
    if season not in {"winter", "spring", "summer", "fall"}:
        return flask.abort(400, description="season must be winter, spring, summer, or fall")

    try:
        year = int(flask.request.args.get("year", ""))
    except ValueError:
        return flask.abort(400, description="year must be a number")
    if not 1900 <= year <= 2100:
        return flask.abort(400, description="year must be between 1900 and 2100")

    return [
        result.__dict__
        for result in animixplay.by_season(
            season=season,
            year=year,
            page=_positive_page_arg(),
        )
    ]


@app.route("/api/amp/type/<anime_type>")
@_json_or_error
def api_amp_type(anime_type):
    anime_type = anime_type.strip().lower()
    if anime_type not in animixplay.ALL_TYPES:
        return flask.abort(404)
    return [
        result.__dict__
        for result in animixplay.by_type(anime_type, page=_positive_page_arg())
    ]


@app.route("/api/amp/status/<status>")
@_json_or_error
def api_amp_status(status):
    status = status.strip().lower()
    if status not in animixplay.ALL_STATUSES:
        return flask.abort(404)
    return [
        result.__dict__
        for result in animixplay.by_status(status, page=_positive_page_arg())
    ]


@app.route("/api/amp/schedule")
@_json_or_error
def api_amp_schedule():
    try:
        timezone_hours = float(flask.request.args.get("tz", "0"))
    except ValueError:
        return flask.abort(400, description="tz must be a number of hours from GMT")
    if not -12 <= timezone_hours <= 14:
        return flask.abort(400, description="tz must be between -12 and 14")

    return [
        {
            "label": day.label,
            "entries": [entry.__dict__ for entry in day.entries],
        }
        for day in animixplay.weekly_schedule(timezone_hours)
    ]


@app.route("/api/amp/genres")
def api_amp_genres():
    return flask.jsonify(animixplay.ALL_GENRES)


@app.route("/api/amp/show/<slug>")
@_json_or_error
def api_amp_show(slug):
    return animixplay.show_detail(slug).__dict__


@app.route("/api/amp/episodes/<anime_id>")
@_json_or_error
def api_amp_episodes(anime_id):
    eps = animixplay.get_episodes(anime_id)
    return [
        {"id": f"{anime_id}:{e.number}", "anime_id": anime_id, "number": e.number}
        for e in eps
    ]


@app.route("/api/amp/seasons/<anime_id>")
@_json_or_error
def api_amp_seasons(anime_id):
    return [season.__dict__ for season in animixplay.related_seasons(anime_id)]


@app.route("/api/amp/stream/<anime_id>/<int:episode>")
@_json_or_error
def api_amp_stream(anime_id, episode):
    sources = animixplay.get_all_streams(anime_id, episode)
    result = []
    for s in sources:
        full = animixplay.resolve_source_full(s.url) or {}
        result.append({
            "server": s.server,
            "url": s.url,
            "quality": s.quality,
            "source": full.get("source"),
            "tracks": _proxied_subtitle_tracks(full.get("tracks", [])),
        })
    return result


@app.route("/proxy/video")
def proxy_video():
    """Proxy remote video to avoid CORS issues. Streams the MP4 through us."""
    target = flask.request.args.get("url", "")
    if not _is_allowed_video_url(target):
        return "invalid video url", 400

    range_header = flask.request.headers.get("Range", "")
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Accept": "*/*",
        "Referer": "https://my.1anime.site/",
    }
    if range_header:
        headers["Range"] = range_header

    req = Request(target, headers=headers)
    try:
        resp = video_opener.open(req, timeout=30)
    except Exception:
        app.logger.exception("Video proxy request failed")
        return "video source unavailable", 502

    status = resp.status
    content_type = resp.headers.get("Content-Type", "video/mp4")
    content_length = resp.headers.get("Content-Length", "")
    content_range = resp.headers.get("Content-Range", "")

    def generate():
        while True:
            chunk = resp.read(65536)
            if not chunk:
                break
            yield chunk
        resp.close()

    rv = flask.Response(flask.stream_with_context(generate()), status=status)
    rv.headers["Content-Type"] = content_type
    rv.headers["Accept-Ranges"] = "bytes"
    if content_length:
        rv.headers["Content-Length"] = content_length
    if content_range:
        rv.headers["Content-Range"] = content_range
    rv.headers["Cache-Control"] = "no-cache"
    return rv


@app.route("/proxy/m3u8")
def proxy_m3u8():
    """Proxy HLS M3U8 playlists — rewrites segment URLs."""
    target = flask.request.args.get("url", "")
    if not target or not _is_allowed_video_url(target):
        return "invalid url", 400

    req = Request(target, headers=_hls_request_headers(target))
    try:
        resp = video_opener.open(req, timeout=15)
        content = resp.read().decode("utf-8", errors="replace")
    except Exception:
        return "m3u8 unavailable", 502

    lines = []
    for line in content.splitlines():
        s = line.strip()
        if s.startswith("#"):
            line = _rewrite_hls_attribute_urls(line, target)
        elif s:
            line = _proxied_hls_path(urljoin(target, s))
        lines.append(line)

    rv = flask.Response("\n".join(lines))
    rv.headers["Content-Type"] = "application/vnd.apple.mpegurl"
    rv.headers["Access-Control-Allow-Origin"] = "*"
    rv.headers["Cache-Control"] = "no-cache"
    return rv


@app.route("/proxy/ts")
def proxy_ts():
    """Proxy HLS .ts segments."""
    target = flask.request.args.get("url", "")
    if not target or not _is_allowed_video_url(target):
        return "invalid url", 400

    req = Request(target, headers=_hls_request_headers(target))
    try:
        resp = video_opener.open(req, timeout=15)
        rv = flask.Response(flask.stream_with_context(iter(lambda: resp.read(65536), b"")))
        rv.headers["Content-Type"] = resp.headers.get("Content-Type", "video/mp2t")
        rv.headers["Access-Control-Allow-Origin"] = "*"
        rv.headers["Cache-Control"] = "no-cache"
        return rv
    except Exception:
        return "segment unavailable", 502


@app.route("/proxy/subtitle")
def proxy_subtitle():
    """Proxy provider-protected WebVTT subtitles through the API origin."""
    target = flask.request.args.get("url", "")
    if not target or not _is_allowed_video_url(target):
        return "invalid subtitle url", 400

    req = Request(target, headers=_hls_request_headers(target))
    try:
        with video_opener.open(req, timeout=15) as resp:
            content_length = resp.headers.get("Content-Length")
            if content_length and int(content_length) > MAXIMUM_SUBTITLE_SIZE:
                return "subtitle too large", 413
            content = resp.read(MAXIMUM_SUBTITLE_SIZE + 1)
    except Exception:
        app.logger.exception("Subtitle proxy request failed")
        return "subtitle unavailable", 502

    if len(content) > MAXIMUM_SUBTITLE_SIZE:
        return "subtitle too large", 413

    rv = flask.Response(content, mimetype="text/vtt")
    rv.headers["Access-Control-Allow-Origin"] = "*"
    rv.headers["Cache-Control"] = "private, max-age=3600"
    return rv


# ---------------------------------------------------------------------------
# Frontend
# ---------------------------------------------------------------------------

INDEX = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>9anime Browser</title>
<style>
:root {
  --bg: #0f0f14;
  --surface: #1a1a24;
  --border: #2a2a3a;
  --text: #e4e4ec;
  --muted: #8888a0;
  --accent: #7c3aed;
  --accent-dim: #7c3aed22;
  --radius: 10px;
}
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Inter, sans-serif;
  background: var(--bg); color: var(--text);
  height: 100vh; overflow: hidden; display: flex;
}
a { color: var(--accent); text-decoration: none; }

/* --- Sidebar --- */
#sidebar {
  width: 380px; min-width: 340px;
  display: flex; flex-direction: column;
  border-right: 1px solid var(--border);
  background: var(--surface);
}
#search-bar {
  display: flex; align-items: center; gap: 6px;
  padding: 14px; border-bottom: 1px solid var(--border);
  flex-wrap: wrap;
}
#search-bar input {
  flex: 1; min-width: 140px; background: var(--bg); border: 1px solid var(--border);
  color: var(--text); padding: 8px 12px; border-radius: 8px;
  font-size: 14px; outline: none;
}
#search-bar input:focus { border-color: var(--accent); }
#source-toggle {
  display: flex; border-radius: 6px; overflow: hidden; border: 1px solid var(--border);
  flex-shrink: 0;
}
#source-toggle button {
  background: transparent; border: none; color: var(--muted);
  padding: 6px 10px; font-size: 11px; font-weight: 600; cursor: pointer; transition: .15s;
}
#source-toggle button.active {
  background: var(--accent); color: #fff;
}
#results {
  flex: 1; overflow-y: auto; padding: 8px;
}
.card {
  display: flex; gap: 12px; padding: 8px; border-radius: var(--radius);
  cursor: pointer; transition: background .15s; margin-bottom: 2px;
}
.card:hover { background: var(--accent-dim); }
.card img {
  width: 56px; height: 80px; border-radius: 6px; object-fit: cover;
  background: var(--border); flex-shrink: 0;
}
.card-info { flex: 1; min-width: 0; }
.card-info .title { font-size: 14px; font-weight: 600; line-height: 1.3; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.card-info .sub { font-size: 12px; color: var(--muted); margin-top: 3px; }
.badges { display: flex; gap: 4px; margin-top: 4px; }
.badge {
  font-size: 10px; font-weight: 600; padding: 2px 6px;
  border-radius: 4px; line-height: 1.3;
}
.badge-sub { background: #3b82f622; color: #60a5fa; }
.badge-dub { background: #f59e0b22; color: #fbbf24; }
.badge-eps { background: var(--accent-dim); color: #a78bfa; }

/* --- Main content --- */
#main {
  flex: 1; display: flex; flex-direction: column; overflow: hidden;
}
#player-wrap { background: #000; flex-shrink: 0; display: none; }
#player-wrap.visible { display: block; }
#player-wrap iframe { width: 100%; height: 450px; border: 0; display: block; }
#player-wrap video { width: 100%; height: 450px; display: block; outline: none; }
#source-label {
  background: var(--surface); border-bottom: 1px solid var(--border);
  padding: 6px 14px; font-size: 12px; color: var(--muted);
  display: none;
}
#source-label.visible { display: block; }
.server-link {
  color: var(--accent); cursor: pointer; margin-left: 8px;
  font-size: 12px; text-decoration: underline;
}
#detail {
  flex: 1; overflow-y: auto; padding: 20px 28px;
}
#detail .hero { display: flex; gap: 20px; margin-bottom: 20px; }
#detail .hero img { width: 140px; height: 200px; border-radius: var(--radius); object-fit: cover; }
#detail .hero h2 { font-size: 22px; margin-bottom: 8px; }
#detail .hero .meta { font-size: 13px; color: var(--muted); margin-bottom: 4px; }
#detail .hero .desc { font-size: 13px; color: var(--muted); line-height: 1.5; margin-top: 8px; }
#detail .episodes { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 6px; }
#detail .ep-btn {
  background: var(--surface); border: 1px solid var(--border);
  color: var(--text); padding: 8px 12px; border-radius: 6px;
  font-size: 13px; cursor: pointer; text-align: left; transition: .15s;
}
#detail .ep-btn:hover { border-color: var(--accent); background: var(--accent-dim); }
#detail .ep-btn.active { border-color: var(--accent); background: var(--accent-dim); color: #c4b5fd; }
.placeholder {
  display: flex; align-items: center; justify-content: center;
  height: 100%; color: var(--muted); font-size: 15px; text-align: center;
}
.loading { color: var(--muted); padding: 20px; text-align: center; }
</style>
</head>
<body>

<div id="sidebar">
  <div id="search-bar">
    <div id="source-toggle">
      <button data-src="amp" class="active">Animixplay</button>
      <button data-src="9a">9anime</button>
    </div>
    <input id="search-input" type="text" placeholder="Search anime..." autocomplete="off">
  </div>
  <div id="results"><div class="loading">Loading...</div></div>
</div>

<div id="main">
  <div id="player-wrap">
    <iframe id="player-frame" allowfullscreen allow="autoplay; encrypted-media; picture-in-picture" style="display:none"></iframe>
    <video id="player-video" controls playsinline crossorigin="anonymous" style="display:none"></video>
  </div>
  <div id="source-label"></div>
  <div id="detail">
    <div class="placeholder">Select an anime from the left to start watching</div>
  </div>
</div>

<script>
// ── Helpers ──
const $ = s => document.querySelector(s);
const $$ = s => document.querySelectorAll(s);

async function api(path) {
  const r = await fetch(path);
  return r.json();
}

// ── Source ──
let source = 'amp';

$$('#source-toggle button').forEach(b => {
  b.addEventListener('click', () => {
    $$('#source-toggle button').forEach(x => x.classList.remove('active'));
    b.classList.add('active');
    source = b.dataset.src;
    currentShow = null; currentEpisodes = [];
    $('#detail').innerHTML = '<div class="placeholder">Select an anime from the left</div>';
    $('#player-wrap').classList.remove('visible');
    $('#player-frame').src = '';
    $('#player-video').src = '';
    loadBrowse();
  });
});

// ── State ──
let currentShow = null;
let currentEpisodes = [];
let activeEpisodeId = null;

// ── Render cards ──
function renderCards(items, container) {
  if (!items.length) {
    container.innerHTML = '<div class="loading">No results</div>';
    return;
  }
  container.innerHTML = items.map(item => `
    <div class="card" data-id="${item.id}" data-title="${esc(item.title)}" data-url="${esc(item.url||'')}">
      <img src="${item.image_url || ''}" loading="lazy" onerror="this.style.display='none'">
      <div class="card-info">
        <div class="title">${esc(item.title)}</div>
        ${item.japanese_title ? `<div class="sub">${esc(item.japanese_title)}</div>` : ''}
        <div class="badges">
          ${item.type ? `<span class="badge ${item.type==='DUB'?'badge-dub':'badge-sub'}">${item.type}</span>` : ''}
          ${item.episode_label ? `<span class="badge badge-eps">${esc(item.episode_label)}</span>` : ''}
        </div>
      </div>
    </div>
  `).join('');

  container.querySelectorAll('.card').forEach(card => {
    card.addEventListener('click', () => loadShow(card.dataset.id, card.dataset.url, card.dataset.title));
  });
}

function esc(s) { return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

function copyToClipboard(text) {
  navigator.clipboard.writeText(text).then(() => {
    alert('M3U8 URL copied! Use: yt-dlp <url>');
  }).catch(() => {
    prompt('Copy this URL:', text);
  });
}

// ── Load show ──
async function loadShow(id, url, title) {
  const detail = $('#detail');
  detail.innerHTML = '<div class="loading">Loading...</div>';

  if (source === 'amp') {
    // Animixplay: extract slug from URL
    let slug = '';
    if (url) { const m = url.match(/\/watch\/([^/]+)/); if (m) slug = m[1]; }
    try {
      const show = await api('/api/amp/show/' + slug);
      const eps = await api('/api/amp/episodes/' + show.id);
      currentShow = show;
      currentEpisodes = eps;
      renderDetailAmp(show, eps);
    } catch(e) { detail.innerHTML = '<div class="placeholder">Failed to load</div>'; }
  } else {
    // 9anime
    let slug = '';
    if (url) { const m = url.match(/\/anime\/([^/]+)/); if (m) slug = m[1]; }
    if (!slug) slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
    try {
      const show = await api('/api/show/' + slug);
      const eps = await api('/api/episodes/' + show.id);
      currentShow = show;
      currentEpisodes = eps;
      renderDetail(show, eps);
    } catch(e) { detail.innerHTML = '<div class="placeholder">Failed to load</div>'; }
  }
}

// ── Render animixplay detail ──
function renderDetailAmp(show, eps) {
  $('#detail').innerHTML = `
    <div class="hero">
      <img src="${show.image_url || ''}" onerror="this.style.display='none'">
      <div>
        <h2>${esc(show.title)}</h2>
        ${show.japanese_title ? `<div class="meta">${esc(show.japanese_title)}</div>` : ''}
        <div class="meta">
          ${show.type||'?'} &middot; ${show.status||'?'} &middot; ${show.episodes_count||eps.length} eps
          ${show.sub_episodes ? ' &middot; Sub:'+show.sub_episodes : ''}
          ${show.dub_episodes ? ' &middot; Dub:'+show.dub_episodes : ''}
          ${show.mal_score ? ' &middot; MAL:'+show.mal_score : ''}
        </div>
        <div class="meta">${(show.genres||[]).join(', ')}</div>
        ${show.description ? `<div class="desc">${esc(show.description)}</div>` : ''}
      </div>
    </div>
    <div class="episodes">
      ${eps.slice(0, 50).map(ep => `
        <button class="ep-btn" data-ep-id="${show.id}" data-ep-num="${ep.number}">Ep ${ep.number}</button>
      `).join('')}
    </div>
  `;
  $$('.ep-btn').forEach(btn => {
    btn.addEventListener('click', () => playEpisodeAmp(btn.dataset.epId, btn.dataset.epNum));
  });
}

// ── Play animixplay ──
async function playEpisodeAmp(animeId, epNum) {
  $$('.ep-btn').forEach(b => b.classList.remove('active'));
  const btn = document.querySelector(`.ep-btn[data-ep-num="${epNum}"]`);
  if (btn) btn.classList.add('active');

  try {
    const sources = await api('/api/amp/stream/' + animeId + '/' + epNum);
    if (!sources.length) { alert('No stream available'); return; }

    ampServerSources = sources;
    ampServerIndex = 0;

    // Show player with first server in iframe
    showAmpPlayer(0);

    let html = `<strong>Ep ${epNum}</strong> &middot; ${sources.length} servers: `;
    sources.forEach((s, i) => {
      html += `<span class="server-link" onclick="showAmpPlayer(${i})" style="${i===0?'color:#fff;':''}">${esc(s.server)}</span> `;
    });
    if (sources[0].source) {
      html += `<br><span class="server-link" onclick="copyToClipboard('${esc(sources[0].source)}')">📋 copy m3u8</span>`;
      html += ` <span style="font-size:11px;color:var(--muted)">→ yt-dlp &lt;url&gt;</span>`;
    }
    $('#source-label').innerHTML = html;
  } catch(e) { console.error('Stream error:', e); alert('Failed to load stream: ' + (e.message || e)); }
}

let ampServerSources = [];
let ampServerIndex = 0;
let hls = null;

function showAmpPlayer(idx) {
  ampServerIndex = idx;
  const src = ampServerSources[idx];
  if (!src) return;

  $('#player-wrap').classList.add('visible');
  $('#source-label').classList.add('visible');

  // Try direct M3U8 playback first
  if (src.source && typeof Hls !== 'undefined' && Hls.isSupported()) {
    $('#player-frame').style.display = 'none';
    $('#player-frame').src = '';
    $('#player-video').style.display = 'block';

    if (hls) { hls.destroy(); hls = null; }
    const m3u8Url = '/proxy/m3u8?url=' + encodeURIComponent(src.source);
    hls = new Hls({ enableWorker: false });

    // Clear existing tracks
    const tracks = $('#player-video').querySelectorAll('track');
    tracks.forEach(t => t.remove());

    // Add subtitle tracks if available
    if (src.tracks && src.tracks.length) {
      src.tracks.forEach((track, i) => {
        const trackEl = document.createElement('track');
        trackEl.kind = track.kind || 'subtitles';
        trackEl.label = track.label || 'English';
        trackEl.srclang = track.srclang || 'en';
        trackEl.src = track.file;
        trackEl.default = track.default || i === 0;
        $('#player-video').appendChild(trackEl);
      });
    }

    hls.loadSource(m3u8Url);
    hls.attachMedia($('#player-video'));
    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      $('#player-video').play().catch(() => {});
    });
    hls.on(Hls.Events.ERROR, (ev, data) => {
      console.error('HLS error:', data);
      if (data.fatal) {
        hls.destroy(); hls = null;
        $('#player-video').style.display = 'none';
        $('#source-label').innerHTML += ' <span class="server-link" onclick="showAmpPlayer(' + ((ampServerIndex + 1) % ampServerSources.length) + ')">try next server</span>';
      }
    });
  } else {
    // Embed player
    $('#player-video').style.display = 'none';
    $('#player-video').src = '';
    $('#player-frame').style.display = 'block';
    $('#player-frame').setAttribute('allow', 'autoplay; encrypted-media; fullscreen');
    $('#player-frame').src = src.url;
  }

  // Update server list highlight
  $$('#source-label .server-link').forEach((el, i) => {
    el.style.color = i === idx ? '#fff' : '';
  });
}

// ── Browse (based on source) ──
async function loadBrowse() {
  try {
    let items;
    if (source === 'amp') {
      items = await api('/api/amp/popular');
    } else {
      items = await api('/api/recent');
    }
    renderCards(items, $('#results'));
  } catch(e) {
    $('#results').innerHTML = '<div class="loading">Failed to load</div>';
  }
}

// ── Old 9anime functions (kept for source=9a) ──

// ── Render detail ──
function renderDetail(show, eps) {
  $('#detail').innerHTML = `
    <div class="hero">
      <img src="${show.image_url || ''}" onerror="this.style.display='none'">
      <div>
        <h2>${esc(show.title)}</h2>
        ${show.japanese_title ? `<div class="meta">${esc(show.japanese_title)}</div>` : ''}
        <div class="meta">
          ${show.type||'?'} &middot; ${show.status||'?'} &middot; ${show.episodes||eps.length} eps
          ${show.season ? ' &middot; '+esc(show.season) : ''}
          ${show.studio ? ' &middot; '+esc(show.studio) : ''}
        </div>
        <div class="meta">${(show.genres||[]).join(', ')}</div>
        ${show.description ? `<div class="desc">${esc(show.description)}</div>` : ''}
      </div>
    </div>
    <div class="episodes">
      ${eps.map(ep => `
        <button class="ep-btn" data-ep-id="${ep.id}" data-ep-num="${ep.number}">
          Ep ${ep.number}
        </button>
      `).join('')}
    </div>
  `;

  $$('.ep-btn').forEach(btn => {
    btn.addEventListener('click', () => playEpisode(btn.dataset.epId, btn.dataset.epNum));
  });
}

// ── Play ──
async function playEpisode(epId, epNum) {
  $$('.ep-btn').forEach(b => b.classList.remove('active'));
  const btn = document.querySelector(`.ep-btn[data-ep-id="${epId}"]`);
  if (btn) btn.classList.add('active');
  activeEpisodeId = epId;

  try {
    const sources = await api('/api/stream/' + epId);
    // Prefer direct stream URL (no ads), fall back to embed
    const direct = sources.find(s => s.direct_url);
    const embed = sources.find(s => s.embed_url);

    $('#player-frame').style.display = 'none';
    $('#player-video').style.display = 'none';
    $('#player-wrap').classList.remove('visible');
    $('#source-label').classList.remove('visible');
    $('#player-frame').src = '';
    $('#player-video').src = '';

    if (direct) {
      $('#player-video').src = direct.direct_url;
      $('#player-video').style.display = 'block';
      $('#player-wrap').classList.add('visible');
      $('#source-label').classList.add('visible');
      $('#source-label').innerHTML = `Direct stream (no ads)${embed ? ` &middot; <span class="server-link" onclick="playEmbed('${esc(embed.embed_url)}')">switch to embed</span>` : ''}`;
    } else if (embed) {
      $('#player-frame').src = embed.embed_url;
      $('#player-frame').style.display = 'block';
      $('#player-wrap').classList.add('visible');
      $('#source-label').classList.add('visible');
      $('#source-label').innerHTML = 'Embed player (may show ads)';
    } else {
      alert('No stream available for this episode');
    }
  } catch (e) {
    alert('Failed to load stream');
  }
}

function playEmbed(url) {
  $('#player-video').style.display = 'none';
  $('#player-video').src = '';
  $('#player-frame').src = url;
  $('#player-frame').style.display = 'block';
  $('#source-label').innerHTML = 'Embed player (may show ads)';
}

// ── Search ──
let searchTimer = null;
$('#search-input').addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(async () => {
    const q = $('#search-input').value.trim();
    if (q.length < 2) { loadBrowse(); return; }
    try {
      const endpoint = source === 'amp' ? '/api/amp/search?q=' : '/api/search?q=';
      const items = await api(endpoint + encodeURIComponent(q));
      renderCards(items, $('#results'));
    } catch(e) {}
  }, 400);
});

// ── Initial load ──
loadBrowse();
</script>
<script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
</body>
</html>"""


@app.route("/")
def index():
    return flask.Response(INDEX, mimetype="text/html")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    logging.basicConfig(level=logging.INFO)
    print(f"🎬 9anime Browser — http://localhost:{port}")
    app.run(host="0.0.0.0", port=port, debug=False)
