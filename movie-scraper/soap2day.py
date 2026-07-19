"""
Soap2Day scraper — Python with requests + BeautifulSoup.
"""

import re
import json
from dataclasses import dataclass, field
from typing import Optional
from urllib.parse import quote_plus, urljoin, urlparse

import requests
from bs4 import BeautifulSoup
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

BASE = "https://uk-soap2day.day"
# Domain rotation (uk and au don't use Cloudflare Turnstile, ww25 does)
DOMAINS = [
    {"url": "https://uk-soap2day.day", "type": "dooplay"},
    {"url": "https://au-soap2day.day", "type": "dooplay"},
]

# Rotating residential proxy (prevents IP-based rate limiting)
PROXY_URL = None  # Set via env var SOAP2DAY_PROXY
import os as _os
if _os.environ.get("SOAP2DAY_PROXY"):
    PROXY_URL = _os.environ["SOAP2DAY_PROXY"]

_current_domain = DOMAINS[0]["url"]


def _use_mirror(url: str) -> str:
    """Rewrite known domains to the current mirror if blocked."""
    if url.startswith(_current_domain):
        return url
    for d in DOMAINS:
        if url.startswith(d["url"]):
            return url
    if "soap2day.day" in url:
        return url.replace("https://ww25.soap2day.day", _current_domain)
    return url


def _switch_domain():
    """Rotate to next available domain."""
    global _current_domain
    for d in DOMAINS:
        if d["url"] == _current_domain:
            idx = DOMAINS.index(d)
            _current_domain = DOMAINS[(idx + 1) % len(DOMAINS)]["url"]
            return
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

# Known direct HLS provider endpoints
XPASS_EMBED = "https://play.xpass.top/e/movie/{imdb_id}"
XPASS_PLAYLIST_BASE = "https://play.xpass.top"

# TTL cache for listing pages (reduces load on discovery layer)
_listing_cache: dict = {}
_LISTING_CACHE_TTL = 300  # 5 minutes

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


@dataclass
class SearchResult:
    id: str
    slug: str
    title: str
    url: str
    image_url: Optional[str] = None
    imdb_rating: Optional[str] = None
    runtime: Optional[str] = None
    year: Optional[str] = None
    type: Optional[str] = None  # "movie" or "tv"
    quality: Optional[str] = None


@dataclass
class Genre:
    slug: str
    title: str


@dataclass
class Episode:
    id: str
    season: int
    number: int
    title: str
    url: str
    thumbnail: Optional[str] = None


@dataclass
class StreamServer:
    server_id: int
    label: str
    quality: str
    embed_url: str


@dataclass
class ShowDetail:
    id: str
    title: str
    slug: str
    url: str
    type: str  # "movie" or "tv"
    image_url: Optional[str] = None
    description: Optional[str] = None
    imdb_rating: Optional[str] = None
    tmdb_rating: Optional[str] = None
    rotten_tomatoes: Optional[str] = None
    metacritic: Optional[str] = None
    genres: list[str] = field(default_factory=list)
    director: Optional[str] = None
    actors: list[str] = field(default_factory=list)
    duration: Optional[str] = None
    release_year: Optional[str] = None
    release_date: Optional[str] = None
    country: Optional[str] = None
    seasons: list[str] = field(default_factory=list)
    streams: list[StreamServer] = field(default_factory=list)


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

_session = requests.Session()
_session.headers.update(HEADERS)

if PROXY_URL:
    _session.proxies = {"http": PROXY_URL, "https": PROXY_URL}

try:
    import cloudscraper as _cs
    _scraper = _cs.create_scraper(
        browser={"browser": "chrome", "platform": "darwin", "mobile": False},
        sess=_session,
    )
    _scraper.headers.update(HEADERS)
    _session = _scraper
except ImportError:
    pass

_retry_policy = Retry(
    total=2,
    connect=2,
    read=2,
    status=2,
    backoff_factor=0.5,
    status_forcelist=(429, 500, 502, 503, 504),
    allowed_methods=frozenset({"GET"}),
    raise_on_status=True,
)
_session.mount("https://", HTTPAdapter(max_retries=_retry_policy))


def _get(url: str) -> str:
    url = _use_mirror(url)
    resp = _session.get(url, timeout=30)
    if resp.status_code == 403:
        # Domain rotation handles Cloudflare - proxy helps with IP rate limits
        _switch_domain()
        url = _use_mirror(url)
        kwargs = {"timeout": 30}
        if PROXY_URL:
            kwargs["proxies"] = {"http": PROXY_URL, "https": PROXY_URL}
        resp = _session.get(url, **kwargs)
    resp.raise_for_status()
    return resp.text


def _get_json(url: str) -> dict:
    resp = _session.get(url, timeout=30)
    resp.raise_for_status()
    return resp.json()


def _soup(html: str) -> BeautifulSoup:
    return BeautifulSoup(html, "lxml")


def _text(el, default: str = "") -> str:
    return el.get_text(strip=True) if el else default


# ---------------------------------------------------------------------------
# Card parser — shared by listing, search, genre pages
# ---------------------------------------------------------------------------


def _parse_cards(html: str) -> list[SearchResult]:
    soup = _soup(html)
    results: list[SearchResult] = []
    for item in soup.select(".ml-item"):
        mid = item.get("data-movie-id", "0")
        link = item.select_one("a.ml-mask")
        href = link.get("href", "") if link else ""
        img = item.select_one("img.mli-thumb")

        title_candidates = [
            link.get("oldtitle", "") if link else "",
            link.get("title", "") if link else "",
            _text(item.select_one(".mli-info .h2")),
            _text(item.select_one("#hidden_tip .qtip-title")),
            _text(item.select_one(".card-title")),
            img.get("title", "") if img else "",
            img.get("alt", "") if img else "",
        ]
        title = next((candidate.strip() for candidate in title_candidates if candidate and candidate.strip()), "")

        image_url = (img.get("data-original") or img.get("src", "")).strip() if img else None
        imdb_el = item.select_one(".mli-add .imdb")
        imdb_rating = _text(imdb_el) if imdb_el else None
        runtime_el = item.select_one(".mli-add .runtime")
        runtime = _text(runtime_el) if runtime_el else None
        year_el = item.select_one("#hidden_tip a[href*='/release-year/']")
        year = _text(year_el) if year_el else None
        quality_el = item.select_one(".mli-quality")
        quality = _text(quality_el) if quality_el else None
        is_tv = "/series/" in href or "tv" in item.get("class", [])
        results.append(SearchResult(
            id=mid,
            slug=urlparse(href).path.strip("/"),
            title=title or "?",
            url=href,
            image_url=image_url,
            imdb_rating=imdb_rating,
            runtime=runtime,
            year=year,
            quality=quality,
            type="tv" if is_tv else "movie",
        ))
    return results


def _parse_pagination(html: str) -> dict:
    soup = _soup(html)
    pages = soup.select(".pagination li a.page")
    total_pages = 1
    for a in pages:
        try:
            n = int(_text(a))
            total_pages = max(total_pages, n)
        except ValueError:
            pass
    return {"current": 1, "total": total_pages}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def search(query: str) -> list[SearchResult]:
    url = f"{BASE}/?s={quote_plus(query)}"
    return _parse_cards(_get(url))


def genres() -> list[Genre]:
    soup = _soup(_get(BASE))
    results: list[Genre] = []
    seen: set[str] = set()
    for link in soup.select("a[href*='/genre/']"):
        parts = urlparse(link.get("href", "")).path.strip("/").split("/")
        if len(parts) < 2 or parts[-2] != "genre":
            continue
        slug = parts[-1]
        title = _text(link)
        if not slug or not title or slug in seen:
            continue
        seen.add(slug)
        results.append(Genre(slug=slug, title=title))
    return results


import time as _time


def _cached(key: str, ttl: int, fn):
    now = _time.time()
    if key in _listing_cache:
        ts, val = _listing_cache[key]
        if now - ts < ttl:
            return val
    val = fn()
    _listing_cache[key] = (now, val)
    return val


def movies(page: int = 1) -> list[SearchResult]:
    if page <= 1:
        url = f"{BASE}/movies-qfva3/"
    else:
        url = f"{BASE}/movies-qfva3/page/{page}/"
    return _parse_cards(_get(url))


def tv_shows(page: int = 1) -> list[SearchResult]:
    if page <= 1:
        url = f"{BASE}/series/"
    else:
        url = f"{BASE}/series/page/{page}/"
    return _parse_cards(_get(url))


def episodes_listing(page: int = 1) -> list[SearchResult]:
    if page <= 1:
        url = f"{BASE}/episode/"
    else:
        url = f"{BASE}/episode/page/{page}/"
    return _parse_cards(_get(url))


def by_genre(genre_slug: str, page: int = 1) -> list[SearchResult]:
    url = f"{BASE}/genre/{genre_slug}/"
    if page > 1:
        url = f"{BASE}/genre/{genre_slug}/page/{page}/"
    return _parse_cards(_get(url))


def by_release_year(year: str, page: int = 1) -> list[SearchResult]:
    url = f"{BASE}/release-year/{year}/"
    if page > 1:
        url = f"{BASE}/release-year/{year}/page/{page}/"
    return _parse_cards(_get(url))


def trending_movies() -> list[SearchResult]:
    url = f"{BASE}/trending-movies-14-soap2day-qwer1/"
    return _parse_cards(_get(url))


def trending_tv() -> list[SearchResult]:
    url = f"{BASE}/trending-tv-14-days-soap2day-zxcv1/"
    return _parse_cards(_get(url))


def popular_movies() -> list[SearchResult]:
    url = f"{BASE}/top-100-popular-movies-soap2day-jjkk1/"
    return _parse_cards(_get(url))


def popular_tv() -> list[SearchResult]:
    url = f"{BASE}/top-100-popular-tv-soap2day-llkk1/"
    return _parse_cards(_get(url))


# ---------------------------------------------------------------------------
# Detail page parser
# ---------------------------------------------------------------------------


def show_detail(slug: str) -> Optional[ShowDetail]:
    """Parse a movie or TV show detail page. Slug is the URL path segment."""
    page_url = f"{BASE}/{slug.strip('/')}/"
    html = _get(page_url)
    soup = _soup(html)

    post_id = ""
    body_class = soup.body.get("class", [])
    for c in body_class:
        m = re.match(r"postid-(\d+)", c)
        if m:
            post_id = m.group(1)
            break

    title_el = soup.select_one("h1[itemprop=name]") or soup.select_one(".mvic-desc h3") or soup.select_one("h1")
    title = _text(title_el) if title_el else slug.replace("-", " ").title()

    is_tv = soup.select_one(".mvici-left p:has(strong:-soup-contains('TV'))") is not None
    is_tv = is_tv or soup.select_one(".seasons") is not None
    is_tv = is_tv or soup.select_one(".episodes-list") is not None
    is_tv = is_tv or soup.select_one(".tvseason") is not None

    image_url = None
    splash_el = soup.select_one(".splash-image")
    if splash_el:
        style = splash_el.get("style", "")
        m = re.search(r"url\(['\"]?([^)'\"']+)", style)
        if m:
            image_url = m.group(1)
    if not image_url:
        img_el = soup.select_one(".mvic-thumb img[itemprop=image]")
        if img_el:
            image_url = img_el.get("src") or img_el.get("data-original", "")

    desc_el = soup.select_one("p.f-desc") or soup.select_one(".entry-content p")
    description = _text(desc_el) if desc_el else None

    imdb_el = soup.select_one(".imdb_r [itemprop=ratingValue]")
    imdb_rating = _text(imdb_el) if imdb_el else None
    if not imdb_rating:
        imdb_el = soup.find("span", class_="imdb-r")
        imdb_rating = _text(imdb_el) if imdb_el else None

    tmdb_rating = None
    rt_rating = None
    metacritic_rating = None
    for p in soup.select(".mvic-desc p, .mvici-left p, .mvici-right p, .mvic-info p"):
        strong = p.select_one("strong")
        if not strong:
            continue
        key = _text(strong).lower().rstrip(":")
        val_el = p.select_one(".imdb-r")
        val = _text(val_el) if val_el else ""
        if "tmdb" in key:
            tmdb_rating = val or None
        elif "rotten" in key:
            rt_rating = val or None
        elif "metacritic" in key:
            metacritic_rating = val or None

    genres: list[str] = []
    genre_els = soup.select(".mvici-left a[rel='category tag']")
    for a in genre_els:
        g = _text(a)
        if g and g not in genres:
            genres.append(g)

    director = None
    dir_el = soup.select_one(".mvici-left [itemprop=director] [itemprop=name] a")
    if not dir_el:
        dir_p = soup.select_one(".mvici-left p:-soup-contains('Director')")
        if dir_p:
            dir_el = dir_p.select_one("a[rel=tag]")
    if dir_el:
        director = _text(dir_el)

    actors: list[str] = []
    actors_p = soup.select_one(".mvici-left p:-soup-contains('Actors')")
    if actors_p:
        for a in actors_p.select("a[rel=tag]"):
            name = _text(a)
            if name:
                actors.append(name)

    duration = None
    dur_el = soup.select_one(".mvici-right [itemprop=duration]")
    if dur_el:
        duration = _text(dur_el)
    if not duration:
        dur_p = soup.select_one(".mvici-right p:-soup-contains('Duration')")
        if dur_p:
            duration = re.sub(r"Duration:\s*", "", _text(dur_p)).strip() or None

    release_year = None
    yr_el = soup.select_one(".mvici-right a[href*='release-year']")
    if yr_el:
        release_year = _text(yr_el)

    release_date = None
    rd_el = soup.select_one(".mvici-right [itemprop=dateCreated]")
    if rd_el:
        release_date = _text(rd_el)

    country = None
    country_p = soup.select_one(".mvici-right p:-soup-contains('Country')")
    if country_p:
        country_a = country_p.select_one("a")
        if country_a:
            country = _text(country_a)

    seasons: list[str] = []
    for seas_el in soup.select(".tvseason .les-title strong, .seasons a, .season-item"):
        s = _text(seas_el)
        if s:
            seasons.append(s)

    streams: list[StreamServer] = []
    for tab_li in soup.select(".player_nav .idTabs li"):
        server_strong = tab_li.select_one("strong")
        server_label = _text(server_strong) if server_strong else ""
        server_num = 0
        m_n = re.search(r"Server\s*(\d+)", server_label, re.I)
        if m_n:
            server_num = int(m_n.group(1))
        quality_a = tab_li.select_one(".les-content a")
        quality = _text(quality_a) if quality_a else ""
        tab_href = quality_a.get("href", "") if quality_a else ""
        tab_id = tab_href.lstrip("#") if tab_href.startswith("#") else ""
        if tab_id and tab_href:
            tab_div = soup.select_one(f"#{tab_id}")
            if tab_div:
                iframe = tab_div.select_one("iframe")
                if iframe:
                    embed_url = iframe.get("data-src") or iframe.get("src", "")
                    streams.append(StreamServer(
                        server_id=server_num,
                        label=server_label,
                        quality=quality,
                        embed_url=embed_url,
                    ))

    # Enrich: parse vidapi.xyz first embed for internal sub-servers
    if streams:
        first_server = streams[0]
        if "vidapi.xyz" in first_server.embed_url:
            internal = _parse_vidapi_internal(first_server.embed_url, len(streams) + 1)
            streams.extend(internal)

    # Fetch direct HLS/m3u8 sources via xpass.top
    imdb_id = _extract_imdb_id(html)
    tmdb_id = _extract_tmdb_id(html)

    # Enrich metadata from 2embed API (no Cloudflare, full JSON API)
    if imdb_id:
        enriched = _enrich_from_2embed(imdb_id)
        if enriched:
            if enriched.get("title") and title == slug.replace("-", " ").title():
                title = enriched["title"]
            if not description and enriched.get("overview"):
                description = enriched["overview"]
            if not imdb_rating and enriched.get("vote_average"):
                imdb_rating = str(round(enriched["vote_average"], 1))
            if not director and enriched.get("director"):
                director = enriched["director"]
            if not actors and enriched.get("cast"):
                actors = enriched["cast"][:10]
            if not image_url and enriched.get("poster"):
                image_url = enriched["poster"]

    if imdb_id:
        hls_sources = get_hls_sources(imdb_id)
        streams[:0] = hls_sources
        # Add clean embed players with proper IDs
        clean_embeds = [
            ("2Embed (JW+Subs)", f"https://www.2embed.cc/embed/{imdb_id}"),
        ]
        if tmdb_id:
            clean_embeds += [
                ("VidCore (NextJS)", f"https://vidcore.net/movie/{tmdb_id}"),
                ("VidNest (Ad-Free)", f"https://vidnest.fun/movie/{tmdb_id}?autostart=true"),
                ("Peachify", f"https://peachify.top/embed/movie/{tmdb_id}?autostart=true"),
            ]
        for label, embed_url in clean_embeds:
            if not any(embed_url in s.embed_url for s in streams):
                streams.insert(len(hls_sources), StreamServer(
                    server_id=0,
                    label=label,
                    quality="Direct Player",
                    embed_url=embed_url,
                ))  # prepend HLS before embed servers
    # Renumber sequentially
    for i, s in enumerate(streams):
        s.server_id = i + 1

    return ShowDetail(
        id=post_id,
        title=title,
        slug=slug,
        url=page_url,
        type="tv" if is_tv else "movie",
        image_url=image_url,
        description=description,
        imdb_rating=imdb_rating,
        tmdb_rating=tmdb_rating,
        rotten_tomatoes=rt_rating,
        metacritic=metacritic_rating,
        genres=genres,
        director=director,
        actors=actors,
        duration=duration,
        release_year=release_year,
        release_date=release_date,
        country=country,
        seasons=seasons,
        streams=streams,
    )


def _parse_vidapi_internal(embed_url: str, start_id: int) -> list[StreamServer]:
    """Extract internal sub-servers from a vidapi.xyz embed page."""
    try:
        html = _get(embed_url)
    except Exception:
        return []
    soup = _soup(html)
    servers: list[StreamServer] = []
    for i, btn in enumerate(soup.select(".server-btn")):
        src = btn.get("data-src", "")
        name_el = btn.select_one(".server-name")
        sub_el = btn.select_one(".server-sub")
        name = _text(name_el) if name_el else f"Sub-Server {i+1}"
        sub_label = _text(sub_el) if sub_el else ""
        servers.append(StreamServer(
            server_id=start_id + i,
            label=f"VidAPI: {name}",
            quality=sub_label or "HD",
            embed_url=src if src.startswith("http") else f"https://vidapi.xyz{src}" if src.startswith("/") else src,
        ))
    return servers


def _extract_imdb_id(html: str) -> Optional[str]:
    """Extract IMDB ID from page HTML or embed URLs."""
    for pattern in [r'/imdb/(tt\d+)', r'/embed/imdb/(tt\d+)', r'video_id=(tt\d+)',
                    r'imdb=(tt\d+)', r'"imdb_id"\s*:\s*"(tt\d+)"']:
        m = re.search(pattern, html)
        if m:
            return m.group(1)
    return None


_2EMBED_API = "https://api.2embed.cc"
_2embed_cache: dict[str, dict] = {}


def _enrich_from_2embed(imdb_id: str) -> Optional[dict]:
    """Fetch rich metadata from 2embed API (Cloudflare-free, Apache)."""
    if imdb_id in _2embed_cache:
        return _2embed_cache[imdb_id]
    try:
        resp = _session.get(f"{_2EMBED_API}/movie?imdb_id={imdb_id}", timeout=15)
        resp.raise_for_status()
        data = resp.json()
        result = {
            "title": data.get("title"),
            "overview": data.get("overview"),
            "vote_average": data.get("vote_average"),
            "poster": data.get("poster"),
            "director": None,
            "cast": [],
        }
        for c in data.get("crew", []):
            if c.get("job") == "Director":
                result["director"] = c.get("name")
                break
        for c in data.get("cast", [])[:15]:
            result["cast"].append(c.get("name", ""))
        _2embed_cache[imdb_id] = result
        return result
    except Exception:
        return None


def _extract_tmdb_id(html: str) -> Optional[str]:
    """Extract TMDB ID from page HTML or embed URLs."""
    for pattern in [r'/movie/(\d{4,8})', r'tmdb[=_](\d{4,8})',
                    r'"tmdb_id"\s*:\s*(\d{4,8})']:
        m = re.search(pattern, html)
        if m:
            return m.group(1)
    return None


def get_hls_sources(imdb_id: str) -> list[StreamServer]:
    """Fetch direct HLS/m3u8 sources via xpass.top playlist API."""
    if not imdb_id or not imdb_id.startswith("tt"):
        return []
    try:
        embed_html = _get(XPASS_EMBED.format(imdb_id=imdb_id))
    except Exception:
        return []

    playlist_urls = re.findall(r'"([^"]*playlist\.json[^"]*)"', embed_html)
    if not playlist_urls:
        return []

    servers: list[StreamServer] = []
    seen = set()
    server_idx = 100

    # Also extract server names from the backups array
    server_names = {}
    for m in re.finditer(r'"name":"([^"]*)","url":"([^"]*playlist\.json[^"]*)"', embed_html):
        server_names[m.group(2)] = m.group(1)

    for path in playlist_urls:
        full_url = path if path.startswith("http") else XPASS_PLAYLIST_BASE + path
        name = server_names.get(path, "HLS")

        try:
            resp = _session.get(full_url, timeout=15)
            resp.raise_for_status()
            data = resp.json()
        except Exception:
            continue

        for pl in data.get("playlist", []):
            for src in pl.get("sources", []):
                file_url = src.get("file", "")
                if not file_url or "error" in file_url or file_url in seen:
                    continue
                seen.add(file_url)
                servers.append(StreamServer(
                    server_id=server_idx,
                    label=f"{name}: {src.get('label', '')}",
                    quality="HLS Direct",
                    embed_url=file_url,
                ))
                server_idx += 1
    return servers


# ---------------------------------------------------------------------------
# TV Series episode list
# ---------------------------------------------------------------------------


def series_episodes(slug: str) -> list[Episode]:
    """Extract episode list from a TV series detail page."""
    page_url = f"{BASE}/{slug.strip('/')}/"
    html = _get(page_url)
    soup = _soup(html)
    eps: list[Episode] = []
    for season_el in soup.select(".tvseason"):
        season_title = _text(season_el.select_one(".les-title strong"))
        season_match = re.search(r"(\d+)", season_title)
        season_number = int(season_match.group(1)) if season_match else 0

        for ep_el in season_el.select(".les-content a[href]"):
            ep_url = ep_el.get("href", "")
            ep_title = _text(ep_el) or ep_el.get("title", "")
            ep_match = re.search(r"Episode\s*(\d+)", ep_title, re.I)
            if not ep_match:
                continue
            episode_number = int(ep_match.group(1))
            eps.append(Episode(
                id=urlparse(ep_url).path.strip("/"),
                season=season_number,
                number=episode_number,
                title=f"Episode {episode_number}",
                url=ep_url,
            ))
    return eps


# ===================================================================
# Quick CLI test
# ===================================================================
if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "movies":
        print("=== Movies (page 1) ===")
        for r in movies()[:10]:
            print(f"  [{r.type}] {r.title}  IMDB={r.imdb_rating}  {r.runtime}  id={r.id}")
    elif len(sys.argv) > 1 and sys.argv[1] == "tv":
        print("=== TV Shows (page 1) ===")
        for r in tv_shows()[:10]:
            print(f"  [{r.type}] {r.title}  id={r.id}")
    elif len(sys.argv) > 1 and sys.argv[1] == "search":
        q = " ".join(sys.argv[2:]) or "batman"
        print(f"=== Search: {q} ===")
        for r in search(q)[:10]:
            print(f"  [{r.type}] {r.title}  {r.url}  id={r.id}")
    elif len(sys.argv) > 1 and sys.argv[1] == "detail":
        slug = sys.argv[2] if len(sys.argv) > 2 else "evil-dead-burn-soap2day"
        print(f"=== Detail: {slug} ===")
        d = show_detail(slug)
        if d:
            print(f"  Title: {d.title}")
            print(f"  Type: {d.type}")
            print(f"  IMDB: {d.imdb_rating}  TMDB: {d.tmdb_rating}  RT: {d.rotten_tomatoes}")
            print(f"  Director: {d.director}")
            print(f"  Actors: {', '.join(d.actors[:5])}")
            print(f"  Genres: {', '.join(d.genres[:5])}")
            print(f"  Duration: {d.duration}")
            print(f"  Servers: {len(d.streams)}")
            for s in d.streams:
                print(f"    Server {s.server_id}: {s.quality} → {s.embed_url[:80]}...")
        else:
            print("  Not found")
    else:
        print("Usage: python soap2day.py [movies|tv|search <query>|detail <slug>]")
