"""
Soap2Day browser — Flask API backed by Postgres + Redis.
"""

import logging
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import wraps
from typing import Optional
from urllib.parse import urljoin, urlparse

import flask
import requests as req_lib

import db
import soap2day as scraper

from psycopg2.extras import RealDictCursor

app = flask.Flask(__name__)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

def _json_or_error(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return flask.jsonify(fn(*args, **kwargs))
        except Exception:
            app.logger.exception("API request failed")
            return flask.jsonify({"error": "The request failed."}), 502
    return wrapper


@app.after_request
def add_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/api/health")
def api_health():
    return {"status": "ok"}


@app.route("/api/movies")
@_json_or_error
def api_movies():
    page = int(flask.request.args.get("page", "1"))
    key = f"discovery:movies:page:{page}"
    return _cached_or_scrape(key, lambda: _paginated_result(scraper.movies(page), page, 464))


@app.route("/api/tv")
@_json_or_error
def api_tv():
    page = int(flask.request.args.get("page", "1"))
    key = f"discovery:tv:page:{page}"
    return _cached_or_scrape(key, lambda: _paginated_result(scraper.tv_shows(page), page, 100))


@app.route("/api/trending/movies")
@_json_or_error
def api_trending_movies():
    return _cached_or_scrape("discovery:trending:movies",
                            lambda: _search_result_list(scraper.trending_movies()))


@app.route("/api/trending/tv")
@_json_or_error
def api_trending_tv():
    return _cached_or_scrape("discovery:trending:tv",
                            lambda: _search_result_list(scraper.trending_tv()))


@app.route("/api/popular/movies")
@_json_or_error
def api_popular_movies():
    return _cached_or_scrape("discovery:popular:movies",
                            lambda: _search_result_list(scraper.popular_movies()))


@app.route("/api/popular/tv")
@_json_or_error
def api_popular_tv():
    return _cached_or_scrape("discovery:popular:tv",
                            lambda: _search_result_list(scraper.popular_tv()))


@app.route("/api/search")
@_json_or_error
def api_search():
    q = flask.request.args.get("q", "").strip()
    if not q:
        return []
    key = f"discovery:search:{q.lower()}"
    return _cached_or_scrape(key, lambda: _search_result_list(scraper.search(q)))


@app.route("/api/episodes")
@_json_or_error
def api_episodes():
    page = int(flask.request.args.get("page", "1"))
    key = f"discovery:episodes:page:{page}"
    return _cached_or_scrape(key, lambda: _search_result_list(scraper.episodes_listing(page)))


@app.route("/api/genre/<genre_slug>")
@_json_or_error
def api_genre(genre_slug):
    page = int(flask.request.args.get("page", "1"))
    key = f"discovery:genre:{genre_slug}:page:{page}"
    return _cached_or_scrape(key, lambda: _search_result_list(scraper.by_genre(genre_slug, page)))


@app.route("/api/year/<year>")
@_json_or_error
def api_year(year):
    page = int(flask.request.args.get("page", "1"))
    key = f"discovery:year:{year}:page:{page}"
    return _cached_or_scrape(key, lambda: _search_result_list(scraper.by_release_year(year, page)))


@app.route("/api/show/<path:slug>")
@_json_or_error
def api_show(slug):
    media_type = "tv" if "series/" in slug else "movie"
    cache_key = f"detail:{slug}"

    # Check cache first
    cached = db.cache_get(cache_key)
    if cached:
        return cached

    # Primary: scrape soap2day detail page directly
    detail = None
    try:
        detail = scraper.show_detail(slug)
    except Exception:
        pass

    if detail and detail.streams:
        result = {
            "title": detail.title,
            "slug": slug,
            "type": detail.type or media_type,
            "image_url": detail.image_url,
            "description": detail.description,
            "imdb_rating": _fmt_rating(detail.imdb_rating),
            "tmdb_rating": _fmt_rating(detail.tmdb_rating),
            "rotten_tomatoes": detail.rotten_tomatoes,
            "metacritic": detail.metacritic,
            "genres": detail.genres,
            "director": detail.director,
            "actors": detail.actors,
            "duration": detail.duration,
            "release_year": detail.release_year,
            "release_date": detail.release_date,
            "country": detail.country,
            "seasons": detail.seasons,
            "streams": _stream_list_for_api(detail.streams),
        }
        db.cache_set(cache_key, result, 3600)  # 1 hour
        return result

    # Fallback: try 2embed for metadata + embed
    if detail:
        title_clean = re.sub(r'\s*(?:soap2day|uk|au|watch free online|hd).*$', '', detail.title, flags=re.I).strip()
    else:
        title_clean = re.sub(r'^series/', '', slug).replace('-', ' ').title()

    # Search 2embed for IMDB ID
    imdb_id = None
    try:
        import requests
        from urllib.parse import quote_plus
        for endpoint in ["search", "searchtv"]:
            resp = requests.get(
                f"https://api.2embed.cc/{endpoint}?q={quote_plus(title_clean)}",
                headers={"User-Agent": "Mozilla/5.0"}, timeout=10,
            )
            data = resp.json()
            results = data.get("results", []) if isinstance(data, dict) else data
            if results:
                imdb_id = results[0].get("imdb_id")
                if imdb_id:
                    break
    except Exception:
        pass

    if imdb_id and imdb_id.startswith("tt"):
        result = {
            "title": title_clean,
            "slug": slug,
            "type": media_type,
            "image_url": detail.image_url if detail else None,
            "description": detail.description if detail else None,
            "imdb_rating": _fmt_rating(detail.imdb_rating if detail else None),
            "tmdb_rating": None,
            "rotten_tomatoes": None,
            "metacritic": None,
            "genres": detail.genres if detail else [],
            "director": detail.director if detail else None,
            "actors": detail.actors if detail else [],
            "duration": detail.duration if detail else None,
            "release_year": detail.release_year if detail else None,
            "release_date": detail.release_date if detail else None,
            "country": detail.country if detail else None,
            "seasons": detail.seasons if detail else [],
            "streams": _stream_list_for_api([
                {"server_id": 1, "label": "2Embed", "quality": "1080P",
                 "embed_url": f"https://www.2embed.cc/embed/{imdb_id}"}
            ]),
        }
        db.cache_set(cache_key, result, 3600)
        return result

    # Nothing found
    return {"error": "Not found"}, 404


@app.route("/api/show/<path:slug>/episodes")
@_json_or_error
def api_show_episodes(slug):
    eps = scraper.series_episodes(slug)
    return [e.__dict__ for e in eps]


@app.route("/api/genres")
@_json_or_error
def api_genres():
    return db.get_genres()


@app.route("/proxy/hls")
def proxy_hls():
    """Proxy HLS playlist and TS segments to bypass CORS."""
    target = flask.request.args.get("url", "")
    if not target or not target.startswith("https://"):
        return "Invalid URL", 400

    try:
        resp = req_lib.get(target, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Accept": "*/*",
            "Origin": "https://play.xpass.top",
            "Referer": "https://play.xpass.top/",
        }, stream=True, timeout=30)
    except Exception as e:
        app.logger.exception("HLS proxy fetch failed")
        return f"Upstream error: {e}", 502

    content_type = resp.headers.get("Content-Type", "application/octet-stream")
    is_m3u8 = ".m3u8" in target or "mpegurl" in content_type or "x-mpegURL" in content_type

    if is_m3u8:
        body = resp.text
        base = target.rsplit("/", 1)[0]
        proxy_base = "https://asterion-movies.cyberverse.cloud/proxy/hls?url="
        body = re.sub(
            r'^([^#\s][^\s]*\.(?:m3u8|ts|aac|mp4))',
            lambda m: proxy_base + urljoin(base + "/", m.group(1)),
            body, flags=re.MULTILINE,
        )
        rv = flask.Response(body, content_type=content_type)
        rv.headers["Access-Control-Allow-Origin"] = "*"
        return rv

    def generate():
        try:
            for chunk in resp.iter_content(chunk_size=65536):
                if chunk:
                    yield chunk
        finally:
            resp.close()

    rv = flask.Response(flask.stream_with_context(generate()), content_type=content_type)
    rv.headers["Access-Control-Allow-Origin"] = "*"
    rv.headers["Cache-Control"] = "public, max-age=3600"
    return rv


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _update_db_from_2embed(imdb_id: str, slug: str, metadata: dict):
    """Update the DB row with 2embed metadata (non-blocking)."""
    try:
        pg = db.get_pg()
        with pg.cursor() as cur:
            cur.execute(
                """UPDATE movies SET overview = %s, director = %s,
                   poster_url = COALESCE(movies.poster_url, %s),
                   tmdb_rating = %s, release_date = %s
                   WHERE imdb_id = %s""",
                (metadata.get("overview"), metadata.get("director"),
                 metadata.get("poster"), metadata.get("vote_average"),
                 metadata.get("release_date"), imdb_id),
            )
        # Update genres
        genres = metadata.get("genres", [])
        if genres:
            with pg.cursor() as cur:
                for g in genres:
                    name = g if isinstance(g, str) else g.get("name", "")
                    if name:
                        slug = name.lower().replace(" ", "-")
                        cur.execute("INSERT INTO genres (slug, name) VALUES (%s, %s) ON CONFLICT DO NOTHING", (slug, name))
                        cur.execute("INSERT INTO movie_genres (imdb_id, genre_slug) VALUES (%s, %s) ON CONFLICT DO NOTHING", (imdb_id, slug))
    except Exception:
        pass


def _cached_or_scrape(key: str, fetcher):
    """Redis-backed lazy cache: scrape on miss, cache for 30 days."""
    cached = db.cache_get(key)
    if cached:
        return cached
    result = fetcher()
    db.cache_set(key, result, 30 * 24 * 3600)
    return result


def _pick_best_match(results: list, query: str, title_key: str, year: str = None) -> Optional[str]:
    """Pick the best IMDB ID from search results by title similarity + year match."""
    if not results:
        return None
    query_words = set(query.lower().split())
    best_score = -1
    best_id = None
    for r in results:
        title = (r.get(title_key) or "").lower()
        title_words = set(title.split())
        score = len(query_words & title_words)
        # Bonus for year match
        if year:
            result_year = str(r.get("year") or r.get("first_air_year") or "")
            if result_year == year or (year in result_year):
                score += 2
        if score > best_score:
            best_score = score
            best_id = r.get("imdb_id")
    if best_score >= len(query_words) * 0.5:
        return best_id
    return None


def _fmt_rating(val) -> Optional[str]:
    if val is None:
        return None
    try:
        return str(round(float(val), 1))
    except (ValueError, TypeError):
        return str(val)


def _search_result_list(results) -> list[dict]:
    return [r.__dict__ for r in results]


def _paginated_result(results, page: int, total: int) -> dict:
    return {"page": page, "total_pages": total, "results": [r.__dict__ for r in results]}


def _stream_list_for_api(streams) -> list[dict]:
    seen = set()
    result = []
    for s in streams:
        if isinstance(s, dict):
            d = s.copy()
        else:
            d = s.__dict__.copy()
        url = d.get("embed_url", "")
        # Deduplicate: normalize URL to catch same source
        norm = re.sub(r'(https?://[^/]+).*', r'\1', url)
        norm = norm.replace("www.", "")
        if norm in seen:
            continue
        seen.add(norm)

        is_hls = (
            ".m3u8" in url or "1x2.space" in url or "greenplanetstore" in url
            or "workers.dev" in url or url.endswith(".txt")
        )
        d["is_hls"] = is_hls
        if is_hls:
            d["proxy_url"] = f"https://asterion-movies.cyberverse.cloud/proxy/hls?url={url}"
        result.append(d)

    # Sort: 2embed first, then HLS, then rest
    result.sort(key=lambda s: (
        0 if "2embed.cc" in s.get("embed_url", "") else
        1 if s.get("is_hls") else
        2
    ))
    return result


# ---------------------------------------------------------------------------
# Frontend (SPA)
# ---------------------------------------------------------------------------

INDEX = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Soap2Day Browser</title>
<style>
:root{--bg:#0a0a10;--surface:#141420;--border:#26263a;--text:#e0e0ec;--muted:#7a7a90;--accent:#7c3aed;--accent-dim:#7c3aed22;--green:#22c55e;--orange:#f59e0b;--radius:10px}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Inter,sans-serif;background:var(--bg);color:var(--text);height:100vh;overflow:hidden;display:flex}
a{color:var(--accent);text-decoration:none}
#sidebar{width:360px;min-width:320px;display:flex;flex-direction:column;border-right:1px solid var(--border);background:var(--surface)}
#tabs{display:flex;border-bottom:1px solid var(--border)}
#tabs button{flex:1;background:none;border:none;color:var(--muted);padding:10px;cursor:pointer;font-size:13px;font-weight:600;transition:.15s}
#tabs button:hover,#tabs button.active{color:var(--accent);border-bottom:2px solid var(--accent);margin-bottom:-1px}
#search-bar{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid var(--border)}
#search-bar input{flex:1;background:var(--bg);border:1px solid var(--border);color:var(--text);padding:8px 12px;border-radius:8px;font-size:13px;outline:none}
#search-bar input:focus{border-color:var(--accent)}
#results{flex:1;overflow-y:auto;padding:6px}
.card{display:flex;gap:10px;padding:8px;border-radius:var(--radius);cursor:pointer;transition:background .15s;margin-bottom:2px}
.card:hover{background:var(--accent-dim)}
.card img{width:48px;height:68px;border-radius:6px;object-fit:cover;background:var(--border);flex-shrink:0}
.card-info{flex:1;min-width:0}
.card-info .title{font-size:13px;font-weight:600;line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.card-info .sub{font-size:11px;color:var(--muted);margin-top:2px}
.card .rating{font-size:11px;font-weight:700;color:var(--green);margin-top:2px}
.card .rating.mid{color:var(--orange)}
#main{flex:1;display:flex;flex-direction:column;overflow:hidden}
#player-wrap{background:#000;flex-shrink:0;display:none}
#player-wrap.visible{display:block}
#player-wrap iframe{width:100%;height:440px;border:0;display:block}
#player-wrap video{width:100%;height:440px;display:block;outline:none}
#subtitle-bar{display:none;padding:4px 14px;background:var(--surface);border-bottom:1px solid var(--border);font-size:12px;color:var(--muted);gap:6px;align-items:center;flex-wrap:wrap}
#subtitle-bar select{background:var(--bg);border:1px solid var(--border);color:var(--text);padding:2px 6px;border-radius:4px;font-size:11px}
#subtitle-extlink{color:var(--accent);font-size:11px;margin-left:auto;display:none}
#player-bar{background:var(--surface);border-bottom:1px solid var(--border);display:none}
#player-bar.visible{display:block}
#player-tabs{display:flex;gap:4px;padding:6px 14px;overflow-x:auto}
#player-tabs button{background:var(--bg);border:1px solid var(--border);color:var(--muted);padding:4px 12px;border-radius:6px;font-size:12px;cursor:pointer;white-space:nowrap;transition:.15s}
#player-tabs button:hover,#player-tabs button.active{border-color:var(--accent);color:var(--text)}
#player-extlink{display:block;padding:6px 14px;font-size:12px;color:var(--accent);text-align:center;border-top:1px solid var(--border)}
#player-extlink:hover{text-decoration:underline}
#detail{flex:1;overflow-y:auto;padding:20px 28px}
#detail .hero{display:flex;gap:20px;margin-bottom:16px}
#detail .hero img{width:130px;height:190px;border-radius:var(--radius);object-fit:cover;background:var(--border)}
#detail .hero h2{font-size:20px;margin-bottom:6px}
#detail .hero .meta{font-size:12px;color:var(--muted);margin-bottom:2px}
#detail .hero .desc{font-size:13px;color:var(--muted);line-height:1.5;margin-top:8px;max-height:120px;overflow-y:auto}
#detail .ratings{display:flex;gap:16px;margin-bottom:16px}
#detail .ratings .r{text-align:center}
#detail .ratings .r .val{font-size:18px;font-weight:700}
#detail .ratings .r .lbl{font-size:10px;color:var(--muted);text-transform:uppercase}
.chips{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:12px}
.chip{font-size:11px;padding:3px 8px;border-radius:4px;background:var(--accent-dim);color:var(--accent)}
.placeholder{display:flex;align-items:center;justify-content:center;height:100%;color:var(--muted);font-size:14px;text-align:center}
.loading{color:var(--muted);padding:20px;text-align:center}
</style>
<script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
</head>
<body>
<div id="sidebar">
  <div id="tabs">
    <button data-tab="movies" class="active">Movies</button>
    <button data-tab="tv">TV Shows</button>
    <button data-tab="popular">Popular</button>
    <button data-tab="genres">Genres</button>
  </div>
  <div id="search-bar">
    <input id="search-input" type="text" placeholder="Search movies & TV..." autocomplete="off">
  </div>
  <div id="genre-picker" style="display:none;padding:8px 14px;border-bottom:1px solid var(--border);overflow-x:auto;white-space:nowrap;gap:4px">
  </div>
  <div id="results"><div class="loading">Loading movies...</div></div>
</div>
<div id="main">
  <div id="player-wrap">
    <iframe id="player-frame" allowfullscreen allow="autoplay; encrypted-media; picture-in-picture"></iframe>
    <video id="player-video" controls playsinline crossorigin="anonymous" style="display:none"></video>
  </div>
  <div id="subtitle-bar">
    <span>Subtitles:</span><select id="subtitle-select"></select>
    <a id="subtitle-extlink" href="#" target="_blank" rel="noopener">Open with subtitles →</a>
  </div>
  <div id="player-bar">
    <div id="player-tabs"></div>
    <a id="player-extlink" href="#" target="_blank" rel="noopener">Open in new tab</a>
  </div>
  <div id="detail"><div class="placeholder">Select a title</div></div>
</div>
<script>
const $=s=>document.querySelector(s);const $$=s=>document.querySelectorAll(s);
let currentShow=null,currentStreams=[],activeServer=0,currentTab='movies';
let currentPage=1,totalPages=1,hlsInstance=null;
async function api(path){const r=await fetch(path);return r.json()}
function esc(s){return(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}

function renderCards(items,container,append){
  if(!append)container.innerHTML='';
  if(!items.length&&!append){container.innerHTML='<div class="loading">No results</div>';return}
  var html=items.map(item=>`
    <div class="card" data-slug="${esc(item.slug||'')}" data-title="${esc(item.title)}">
      <img src="${item.image_url||item.poster_url||''}" loading="lazy" onerror="this.style.display='none'">
      <div class="card-info">
        <div class="title">${esc(item.title)}</div>
        ${item.runtime?`<div class="sub">${item.runtime}min</div>`:''}
        ${item.imdb_rating?`<div class="rating ${parseFloat(item.imdb_rating)<7?'mid':''}">IMDb ${item.imdb_rating}</div>`:''}
      </div>
    </div>`).join('');
  container.insertAdjacentHTML('beforeend',html);
  container.querySelectorAll('.card:not([data-bound])').forEach(card=>{
    card.dataset.bound='1';
    card.addEventListener('click',()=>{loadShow(card.dataset.slug);});
  });
}

async function loadShow(slug){
  $('#detail').innerHTML='<div class="loading">Loading...</div>';
  $('#player-frame').src='';$('#player-frame').style.display='none';
  $('#player-video').style.display='none';$('#player-video').src='';
  if(hlsInstance){hlsInstance.destroy();hlsInstance=null;}
  $('#player-wrap').classList.remove('visible');
  $('#player-bar').classList.remove('visible');$('#player-tabs').innerHTML='';
  $('#player-extlink').style.display='none';$('#player-extlink').href='#';
  $('#subtitle-bar').style.display='none';$('#subtitle-select').innerHTML='';
  $('#subtitle-extlink').style.display='none';
  try{
    const show=await api('/api/show/'+slug);
    if(show.error){$('#detail').innerHTML='<div class="placeholder">Not found</div>';return}
    currentShow=show;currentStreams=show.streams||[];activeServer=0;
    renderDetail(show);
    if(currentStreams.length>0)playServer(0);
  }catch(e){$('#detail').innerHTML='<div class="placeholder">Failed to load</div>'}
}

function renderDetail(show){
  const ratings=`
    ${show.imdb_rating?`<div class="r"><div class="val" style="color:${parseFloat(show.imdb_rating)>=7?'var(--green)':'var(--orange)'}">${show.imdb_rating}</div><div class="lbl">IMDb</div></div>`:''}
    ${show.tmdb_rating?`<div class="r"><div class="val">${show.tmdb_rating}</div><div class="lbl">TMDb</div></div>`:''}
    ${show.rotten_tomatoes?`<div class="r"><div class="val" style="color:var(--green)">${show.rotten_tomatoes}%</div><div class="lbl">RT</div></div>`:''}
  `;
  const chips=[...(show.genres||[])].map(g=>`<span class="chip">${esc(g)}</span>`).join('');
  const meta=`${show.duration||''} &middot; ${show.release_year||''}`;
  $('#detail').innerHTML=`
    <div class="hero">
      <img src="${show.image_url||''}" onerror="this.style.display='none'">
      <div><h2>${esc(show.title)}</h2>
        ${show.director?`<div class="meta">Directed by ${esc(show.director)}</div>`:''}
        <div class="meta">${meta}</div>
        ${show.actors&&show.actors.length?`<div class="meta">Starring: ${show.actors.slice(0,5).map(esc).join(', ')}</div>`:''}
        ${show.description?`<div class="desc">${esc(show.description)}</div>`:''}
      </div>
    </div>
    <div class="ratings">${ratings}</div>
    <div class="chips">${chips}</div>`;
  renderServerTabs();
}

function renderServerTabs(){
  if(!currentStreams.length){$('#player-bar').classList.remove('visible');return}
  $('#player-tabs').innerHTML=currentStreams.map((s,i)=>`
    <button data-idx="${i}" data-url="${esc(s.embed_url||'')}" data-hls="${s.is_hls||''}" class="${i===activeServer?'active':''}">${esc(s.is_hls?'🎬 ':'')}${esc(s.label||'Server '+(i+1))} ${esc(s.is_hls?'(HLS)':'('+(s.quality||'HD')+')')}</button>
  `).join('');
  $('#player-bar').classList.add('visible');
  $('#player-tabs').querySelectorAll('button').forEach(btn=>{
    btn.addEventListener('click',()=>{
      activeServer=parseInt(btn.dataset.idx);
      $('#player-tabs').querySelectorAll('button').forEach((b,i)=>b.classList.toggle('active',i===activeServer));
      playServer(parseInt(btn.dataset.idx));
    });
    btn.addEventListener('contextmenu',e=>{e.preventDefault();var u=btn.dataset.url;if(u)window.open(u,'_blank');});
  });
  $('#player-extlink').style.display='block';
  $('#player-extlink').href=currentStreams[0].embed_url||'#';
}

function playServer(idx){
  activeServer=idx;
  if(!currentStreams[idx]||!currentStreams[idx].embed_url)return;
  var s=currentStreams[idx];
  $('#player-tabs').querySelectorAll('button').forEach((b,i)=>b.classList.toggle('active',i===idx));
  $('#player-extlink').href=s.embed_url||'#';
  $('#player-extlink').style.display='block';
  $('#subtitle-bar').style.display='none';$('#subtitle-select').innerHTML='';
  $('#subtitle-extlink').style.display='none';
  if(s.is_hls){
    $('#player-frame').style.display='none';$('#player-frame').src='';
    var v=$('#player-video');v.style.display='block';
    $('#player-wrap').classList.add('visible');
    var subSrc=currentStreams.find(x=>x.label&&x.label.indexOf('2Embed')>=0);
    if(subSrc){$('#subtitle-extlink').href=subSrc.embed_url;$('#subtitle-extlink').style.display='inline'}
    if(window.Hls&&Hls.isSupported()){
      if(hlsInstance)hlsInstance.destroy();
      hlsInstance=new Hls({enableWorker:false});
      hlsInstance.loadSource(s.proxy_url||s.embed_url);
      hlsInstance.attachMedia(v);
      hlsInstance.on(Hls.Events.MANIFEST_PARSED,()=>{
        var t=hlsInstance.subtitleTracks;
        if(t.length>0){
          $('#subtitle-bar').style.display='flex';
          t.forEach((tr,i)=>{
            var o=document.createElement('option');
            o.value=i;o.textContent=tr.name||tr.lang||'Track '+(i+1);
            $('#subtitle-select').appendChild(o);
          });
          $('#subtitle-select').onchange=function(){hlsInstance.subtitleTrack=parseInt(this.value);};
        }
      });
    }else if(v.canPlayType('application/vnd.apple.mpegurl')){v.src=s.proxy_url||s.embed_url;}
  }else{
    if(hlsInstance){hlsInstance.destroy();hlsInstance=null;}
    $('#player-video').style.display='none';$('#player-video').src='';
    $('#player-frame').style.display='block';$('#player-frame').src=s.embed_url;
    $('#player-wrap').classList.add('visible');
  }
}

async function loadTab(tab){
  currentTab=tab;currentPage=1;totalPages=1;
  $('#search-input').value='';
  $('#genre-picker').style.display='none';$('#genre-picker').innerHTML='';
  $$('#tabs button').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));
  $('#results').innerHTML='<div class="loading">Loading...</div>';
  try{
    var url, items;
    if(tab==='movies')url='/api/movies?page=1';
    else if(tab==='tv')url='/api/tv?page=1';
    else if(tab==='popular')url='/api/popular/movies';
    else if(tab==='genres'){
      // Load genre list first
      var genres=await api('/api/genres');
      $('#results').innerHTML='';
      $('#genre-picker').style.display='flex';
      genres.forEach(function(g){
        var b=document.createElement('button');
        b.textContent=g.name;
        b.dataset.slug=g.slug;
        b.style.cssText='background:var(--bg);border:1px solid var(--border);color:var(--muted);padding:4px 12px;border-radius:6px;font-size:12px;cursor:pointer;white-space:nowrap;flex-shrink:0';
        b.onclick=function(){loadGenre(g.slug,g.name);};
        $('#genre-picker').appendChild(b);
      });
      return;
    }
    if(url){
      var data=await api(url);
      items=data.results||data;
      totalPages=data.total_pages||1;
      renderCards(items,$('#results'),false);
      if(currentPage<totalPages)addLoadMore();
    }
  }catch(e){$('#results').innerHTML='<div class="loading">Failed</div>'}
}

async function loadGenre(slug,name){
  currentTab='genres';currentPage=1;
  $('#results').innerHTML='<div class="loading">Loading '+name+'...</div>';
  try{
    var data=await api('/api/genre/'+slug);
    var items=data.results||data;
    totalPages=data.total_pages||1;
    renderCards(items,$('#results'),false);
    if(currentPage<totalPages)addLoadMoreGenre(slug);
  }catch(e){$('#results').innerHTML='<div class="loading">Failed</div>'}
}

function addLoadMoreGenre(slug){
  var btn=document.createElement('button');
  btn.textContent='Load More';
  btn.style.cssText='display:block;width:100%;margin:10px 0;padding:10px;background:var(--surface);border:1px solid var(--border);color:var(--accent);border-radius:8px;cursor:pointer;font-size:13px';
  btn.onclick=async function(){
    btn.textContent='Loading...';btn.disabled=true;
    try{
      var d=await api('/api/genre/'+slug+'?page='+(currentPage+1));
      currentPage=d.page;totalPages=d.total_pages||totalPages;
      renderCards(d.results||d,$('#results'),true);
      if(currentPage<totalPages){btn.textContent='Load More';btn.disabled=false;}
      else btn.remove();
    }catch(e){btn.textContent='Retry';btn.disabled=false;}
  };
  $('#results').appendChild(btn);
}

function addLoadMore(){
  var btn=document.createElement('button');
  btn.textContent='Load More ('+currentPage+'/'+totalPages+')';
  btn.style.cssText='display:block;width:100%;margin:10px 0;padding:10px;background:var(--surface);border:1px solid var(--border);color:var(--accent);border-radius:8px;cursor:pointer;font-size:13px';
  btn.onclick=async function(){
    btn.textContent='Loading...';btn.disabled=true;
    try{
      var u=(currentTab==='movies'?'/api/movies?page=':'/api/tv?page=')+(currentPage+1);
      var d=await api(u);
      currentPage=d.page;totalPages=d.total_pages||totalPages;
      renderCards(d.results||d,$('#results'),true);
      if(currentPage<totalPages){btn.textContent='Load More ('+currentPage+'/'+totalPages+')';btn.disabled=false;}
      else btn.remove();
    }catch(e){btn.textContent='Retry';btn.disabled=false;}
  };
  $('#results').appendChild(btn);
}

let searchTimer=null;
$('#search-input').addEventListener('input',()=>{
  clearTimeout(searchTimer);
  searchTimer=setTimeout(async()=>{
    var q=$('#search-input').value.trim();
    if(q.length<2){loadTab(currentTab);return}
    try{var d=await api('/api/search?q='+encodeURIComponent(q));renderCards(d.results||d,$('#results'),false)}catch(e){}
  },400);
});

$$('#tabs button').forEach(b=>b.addEventListener('click',()=>loadTab(b.dataset.tab)));
loadTab('movies');
</script>
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
    print("🎬 Soap2Day Browser → http://localhost:" + str(port))
    app.run(host="0.0.0.0", port=port, debug=False, threaded=True)
