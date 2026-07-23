"""
9anime.or.at scraper — pure Python, no external dependencies beyond stdlib.
"""

import re
import json
import base64
from urllib.request import Request, urlopen
from urllib.parse import urlencode, quote_plus
from dataclasses import dataclass, field
from typing import Optional

BASE = "https://9anime.or.at"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

ALL_GENRES = [
    "action", "adult-cast", "adventure", "anthropomorphic", "avant-garde",
    "boys-love", "cgdct", "comedy", "drama", "ecchi", "erotica",
    "fantasy", "girls-love", "gore", "gourmet", "harem", "historical",
    "horror", "isekai", "iyashikei", "josei", "love-status-quo",
    "mahou-shoujo", "martial-arts", "mecha", "military", "music",
    "mystery", "mythology", "organized-crime", "otaku-culture",
    "parody", "performing-arts", "psychological", "reincarnation",
    "romance", "school", "sci-fi", "seinen", "shoujo", "shounen",
    "slice-of-life", "super-power", "supernatural", "suspense",
    "time-travel", "urban-fantasy", "villainess", "visual-arts",
]


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

@dataclass
class Show:
    id: str
    title: str
    slug: str
    japanese_title: Optional[str] = None
    image_url: Optional[str] = None
    description: Optional[str] = None
    type: Optional[str] = None
    status: Optional[str] = None
    genres: list[str] = field(default_factory=list)
    episodes: int = 0
    season: Optional[str] = None
    studio: Optional[str] = None
    date_aired: Optional[str] = None


@dataclass
class Episode:
    id: str
    number: int
    url: str


@dataclass
class StreamSource:
    server_id: str
    type: str          # "sub" or "dub"
    quality: str
    embed_url: str
    direct_url: str = ""


@dataclass
class SearchResult:
    id: str
    title: str
    japanese_title: Optional[str] = None
    image_url: Optional[str] = None
    type: Optional[str] = None        # "SUB" / "DUB"
    episode_label: Optional[str] = None
    url: Optional[str] = None


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _get(url: str) -> str:
    req = Request(url, headers=HEADERS)
    with urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")


def _resolve_redirect(url: str, referer: str = "") -> str:
    """Get the Location header from a 302 without following it."""
    import http.client
    from urllib.parse import urlparse, urljoin

    parsed = urlparse(url)
    conn = http.client.HTTPSConnection(parsed.hostname, timeout=15)
    headers = {
        "User-Agent": HEADERS["User-Agent"],
        "Accept": "*/*",
        "Accept-Language": HEADERS["Accept-Language"],
    }
    if referer:
        headers["Referer"] = referer

    conn.request("HEAD", parsed.path + ("?" + parsed.query if parsed.query else ""), headers=headers)
    resp = conn.getresponse()
    resp.read()  # consume body
    conn.close()

    if resp.status in (301, 302, 303, 307, 308):
        loc = resp.getheader("Location", "")
        if loc:
            if loc.startswith("/"):
                loc = urljoin(url, loc)
            return loc
    return url


def _get_json(url: str) -> dict:
    req = Request(url, headers=HEADERS)
    with urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _re_first(pattern: str, text: str, group: int = 1) -> Optional[str]:
    m = re.search(pattern, text, re.DOTALL)
    if m and len(m.groups()) >= group:
        return m.group(group).strip()
    return None


def _re_all(pattern: str, text: str, group: int = 1) -> list[str]:
    return [m.group(group).strip() for m in re.finditer(pattern, text, re.DOTALL)
            if m and len(m.groups()) >= group]


def _strip_tags(text: str) -> str:
    return re.sub(r"<[^>]+>", "", text).strip()


# ---------------------------------------------------------------------------
# Card parser — shared by search, homepage, genre, filter pages
# ---------------------------------------------------------------------------

def _parse_cards(html: str) -> list[SearchResult]:
    """Parse film-list grid cards from any listing page."""
    results: list[SearchResult] = []
    chunks = html.split('class="flw-item item-qtip"')[1:]

    for chunk in chunks:
        rid = _re_first(r'data-id="(\d+)"', chunk) or "0"

        img = _re_first(r'data-src="([^"]*)"[^>]*class="film-poster-img"', chunk) or \
              _re_first(r'src="([^"]*)"[^>]*class="film-poster-img[^"]*"', chunk)

        title = _re_first(r'class="dynamic-name"[^>]*>([^<]+)</a>', chunk) or \
                _re_first(r'alt="([^"]*)"[^>]*class="film-poster-img"', chunk) or "?"

        jp = _re_first(r'data-jname="([^"]*)"', chunk)
        ep_label = _re_first(r'tick-eps">([^<]+)<', chunk)

        href = _re_first(r'<a\s+href="([^"]*)"[^>]*class="film-poster-ahref"', chunk) or \
               _re_first(r'<a\s+href="([^"]*)"[^>]*class="dynamic-name"', chunk)

        typ = "DUB" if "tick-dub" in chunk else ("SUB" if "tick-sub" in chunk else None)

        results.append(SearchResult(
            id=rid, title=title, japanese_title=jp, image_url=img,
            type=typ, episode_label=ep_label, url=href,
        ))
    return results


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def search(query: str) -> list[SearchResult]:
    url = f"{BASE}/?s={quote_plus(query)}"
    return _parse_cards(_get(url))


def recently_updated() -> list[SearchResult]:
    return _parse_cards(_get(BASE))


def by_genre(genre: str) -> list[SearchResult]:
    return _parse_cards(_get(f"{BASE}/genres/{genre.lower()}/"))


def by_season(slug: str) -> list[SearchResult]:
    return _parse_cards(_get(f"{BASE}/season/{slug.lower()}/"))


def filtered(sort: str = "", type_: str = "", status: str = "", genre: str = "", page: int = 1) -> list[SearchResult]:
    """Filter listing. sort: popular|trending|views|rating|recentlyUpdated|recentlyAdded"""
    params = []
    if sort: params.append(f"sort={sort}")
    if type_: params.append(f"type={type_}")
    if status: params.append(f"status={status}")
    if genre: params.append(f"genre={genre}")
    if page > 1: params.append(f"paged={page}")
    qs = "&".join(params)
    url = f"{BASE}/filter/" + (f"?{qs}" if qs else "")
    return _parse_cards(_get(url))


def popular() -> list[SearchResult]:
    return filtered(sort="popular")


def trending() -> list[SearchResult]:
    return filtered(sort="trending")


def top_rated() -> list[SearchResult]:
    return filtered(sort="rating")


def recently_added() -> list[SearchResult]:
    return filtered(sort="recentlyAdded")


def show_detail(slug: str) -> Show:
    html = _get(f"{BASE}/anime/{slug}/")
    sid = _re_first(r'data-series="(\d+)"', html) or slug

    title = _re_first(r'<h2 class="film-name dynamic-name"[^>]*data-jname="([^"]*)"', html) or \
            _re_first(r'<h2 class="film-name dynamic-name"[^>]*>([^<]+)<', html) or \
            slug.replace("-", " ").title()

    jp = _re_first(r'data-jname="([^"]*)"', html)
    jp = jp if jp != title else None
    img = _re_first(r'<img[^>]*src="([^"]*)"[^>]*class="film-poster-img"', html)
    desc = _re_first(r'<p class="shorting">([\s\S]*?)</p>', html)
    desc = _strip_tags(desc) if desc else None

    # Meta extraction
    meta = {}
    for m in re.finditer(
        r'<div class="item">\s*<div class="item-title">([^<]+)</div>\s*<div class="item-content">([\s\S]*?)</div>',
        html
    ):
        key = re.sub(r":$", "", m.group(1).strip()).lower()
        val = _strip_tags(m.group(2))
        meta[key] = val

    # Genres — scope to the detail section only
    detail_section = html
    dm = re.search(r'<div class="anime-detail">([\s\S]*?)<div class="clearfix"></div>\s*</div>\s*</div>', html)
    if dm:
        detail_section = dm.group(1)
    genres = _re_all(r'href="[^"]*/genres/([^/"]+)/"', detail_section)
    ep_total = 0
    ep_match = re.search(r"Ep\s+\d+/(\d+)", html)
    if ep_match:
        ep_total = int(ep_match.group(1))

    return Show(
        id=sid, title=title, slug=slug, japanese_title=jp,
        image_url=img, description=desc, type=meta.get("type"),
        status=meta.get("status"), genres=genres, episodes=ep_total,
        season=meta.get("premiered"), studio=meta.get("studios"),
        date_aired=meta.get("date aired"),
    )


def episodes(series_id: str) -> list[Episode]:
    url = f"{BASE}/wp-json/9animetv/v1/episodes/{series_id}"
    data = _get_json(url)

    if not data.get("status"):
        return []

    ep_html = data.get("pages", "")
    eps: list[Episode] = []
    for m in re.finditer(
        r'<a\s+href="([^"]*)"[^>]*class="[^"]*ep-item[^"]*"[^>]*data-number="(\d+)"[^>]*data-id="(\d+)"',
        ep_html
    ):
        ep_url = m.group(1)
        num = int(m.group(2))
        ep_id = m.group(3)
        eps.append(Episode(id=ep_id, number=num, url=ep_url))
    return eps


def episode_streams(episode_id: str) -> list[StreamSource]:
    url = f"{BASE}/ajax/episode/servers?id={episode_id}"
    data = _get_json(url)

    if not data.get("status"):
        return []

    html = data.get("html", "")
    servers: list[StreamSource] = []

    for m in re.finditer(
        r'<div\s+class="[^"]*server-item[^"]*"\s+data-type="([^"]*)"\s+'
        r'data-id="([^"]*)"\s+data-server-id="([^"]*)"\s+data-embed="([^"]*)"',
        html
    ):
        stype = m.group(1)
        server_id = m.group(3)
        embed_b64 = m.group(4)

        embed_url = ""
        direct_url = ""
        try:
            decoded = base64.b64decode(embed_b64).decode("utf-8")
            if server_id in ("1", "4"):
                sep = "&" if "?" in decoded else "?"
                decoded += f"{sep}autoPlay=1&oa=0"
            embed_url = decoded

            # Derive direct stream URL for 1anime.site embeds
            # /stream/{token} redirects to /videos/{file}.mp4 (needs Referer)
            # Follow the redirect to get the raw MP4 URL (no Referer needed)
            tok_match = re.search(r"my\.1anime\.site/play/([a-f0-9]+)", decoded)
            if tok_match:
                stream_url = f"https://my.1anime.site/stream/{tok_match.group(1)}"
                try:
                    direct_url = _resolve_redirect(stream_url, referer=decoded)
                except Exception:
                    direct_url = stream_url  # fallback
        except Exception:
            embed_url = ""

        # Quality from nearby <a> tag
        quality = "HD"
        qm = re.search(r'<a[^>]*class="btn"[^>]*>([^<]+)</a>', html)
        if qm:
            quality = qm.group(1).strip()

        servers.append(StreamSource(
            server_id=server_id, type=stype, quality=quality, embed_url=embed_url,
            direct_url=direct_url,
        ))

    return servers


def get_episode_stream(episode_id: str) -> Optional[str]:
    """Convenience: return the first available embed URL for an episode."""
    streams = episode_streams(episode_id)
    for s in streams:
        if s.embed_url:
            return s.embed_url
    return None


# ===================================================================
# Quick CLI test
# ===================================================================
if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "recent":
        print("=== Recently Updated ===")
        for r in recently_updated()[:10]:
            print(f"  [{r.type or '?'}] {r.title}  ({r.episode_label or '?'})  id={r.id}")
    elif len(sys.argv) > 1 and sys.argv[1] == "search":
        q = " ".join(sys.argv[2:]) or "solo leveling"
        print(f"=== Search: {q} ===")
        for r in search(q)[:10]:
            print(f"  [{r.type or '?'}] {r.title}  id={r.id}")
    elif len(sys.argv) > 1 and sys.argv[1] == "stream":
        ep_id = sys.argv[2] if len(sys.argv) > 2 else "1716"
        url = get_episode_stream(ep_id)
        print(f"Stream URL for episode {ep_id}: {url}")
    else:
        print("Usage: python nineanime.py [recent|search <query>|stream <ep_id>]")
        print()
        print("↑ Quick test — use app.py to browse & watch in a browser.")
