"""
animixplay.cz scraper — massive catalog (Naruto, One Piece, etc.)
RC4 crypto for AJAX endpoints.
"""

import re
import json
import base64
from urllib.request import Request, urlopen
from urllib.parse import quote_plus, quote, urlencode
from dataclasses import dataclass, field
from typing import Optional

BASE = "https://animixplay.cz"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}
AJAX_HEADERS = {
    **HEADERS,
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "X-Requested-With": "XMLHttpRequest",
    "Referer": BASE + "/",
}


# ---------------------------------------------------------------------------
# Crypto
# ---------------------------------------------------------------------------

def _rc4(key: bytes, data: bytes) -> bytes:
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) % 256
        s[i], s[j] = s[j], s[i]
    i = j = 0
    out = bytearray()
    for b in data:
        i = (i + 1) % 256
        j = (j + s[i]) % 256
        s[i], s[j] = s[j], s[i]
        out.append(b ^ s[(s[i] + s[j]) % 256])
    return bytes(out)


def vrf_encode(value: str) -> str:
    """Compute the vrf parameter for AJAX requests."""
    t = quote_plus(str(value))
    encrypted = _rc4(b"ysJhV6U27FVIjjuk", t.encode())
    b64 = base64.b64encode(encrypted).decode()
    scrambled = list(b64)
    for i in range(len(scrambled)):
        c = ord(scrambled[i])
        r = i % 8
        if r == 1: c += 3
        elif r == 2: c -= 4
        elif r == 4: c -= 2
        elif r == 6: c += 4
        elif r == 0: c -= 3
        elif r == 3: c += 2
        elif r == 5: c += 5
        scrambled[i] = chr(c & 0xFFFF)
    scrambled = "".join(scrambled)
    # ROT13
    result = []
    for ch in scrambled:
        if "a" <= ch <= "z":
            result.append(chr((ord(ch) - 97 + 13) % 26 + 97))
        elif "A" <= ch <= "Z":
            result.append(chr((ord(ch) - 65 + 13) % 26 + 65))
        else:
            result.append(ch)
    return "".join(result)


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
    episodes_count: int = 0
    sub_episodes: int = 0
    dub_episodes: int = 0
    season: Optional[str] = None
    studio: Optional[str] = None
    date_aired: Optional[str] = None
    mal_score: Optional[str] = None


@dataclass
class EpisodeInfo:
    number: int
    server_ids: str = ""  # base64 blob for fetching servers


@dataclass
class StreamSource:
    server: str
    url: str
    quality: str = "HD"


@dataclass
class SearchResult:
    id: str
    title: str
    slug: str
    japanese_title: Optional[str] = None
    image_url: Optional[str] = None
    type: Optional[str] = None
    episodes: Optional[str] = None
    url: Optional[str] = None


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _get(url: str, extra_headers: dict = None) -> str:
    h = {**HEADERS, **(extra_headers or {})}
    req = Request(url, headers=h)
    with urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")


def _get_json(url: str, extra_headers: dict = None) -> dict:
    h = {**AJAX_HEADERS, **(extra_headers or {})}
    req = Request(url, headers=h)
    with urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _re_first(pattern: str, text: str, group: int = 1) -> Optional[str]:
    m = re.search(pattern, text, re.DOTALL)
    if m and len(m.groups()) >= group:
        return m.group(group).strip()
    return None


def _strip_tags(text: str) -> str:
    return re.sub(r"<[^>]+>", "", text).strip()


# ---------------------------------------------------------------------------
# Search & Discovery
# ---------------------------------------------------------------------------

def search(query: str) -> list[SearchResult]:
    return _parse_cards(_get(f"{BASE}/filter?keyword={quote_plus(query)}"))


def popular() -> list[SearchResult]:
    return _parse_cards(_get(f"{BASE}/most-viewed"))


def latest_updated() -> list[SearchResult]:
    return _parse_cards(_get(f"{BASE}/latest-updated"))


def by_genre(genre: str) -> list[SearchResult]:
    return _parse_cards(_get(f"{BASE}/genre/{quote_plus(genre.lower())}"))


def _parse_cards(html: str) -> list[SearchResult]:
    results = []
    for chunk in html.split('class="piece"')[1:]:
        href = _re_first(r'href="([^"]*)"', chunk)
        img = _re_first(r'<img\s+src="([^"]*)"', chunk)
        a_tag = re.search(r'<a[^>]*data-jp="([^"]*)"[^>]*>([^<]+)<', chunk)
        jp, title = (a_tag.group(1), a_tag.group(2)) if a_tag else (None, None)
        if not title:
            title = _re_first(r'class="ani-name"[^>]*>([^<]+)<', chunk)
        ani_type = _re_first(r'class="[^"]*dot"[^>]*>\s*(\w+)\s*<', chunk)
        eps = _re_first(r'class="total">(\d+)<', chunk)
        rid, slug = "", ""
        if href:
            m = re.search(r'/watch/([^/]+)', href)
            if m: slug = m.group(1)
        results.append(SearchResult(
            id=rid, title=title or "?", slug=slug,
            japanese_title=jp, image_url=img,
            type=ani_type, episodes=eps, url=href,
        ))
    return results


# ---------------------------------------------------------------------------
# Show Detail
# ---------------------------------------------------------------------------

def show_detail(slug: str) -> Show:
    html = _get(f"{BASE}/watch/{slug}")
    rid = _re_first(r'const mangaId = (\d+)', html) or ""
    title = _re_first(r'<h1[^>]*class="ani-name"[^>]*>([^<]+)<', html) or slug
    jp = _re_first(r'data-jp="([^"]*)"', html)
    img = _re_first(r'itemprop="image"[^>]*src="([^"]*)"', html)
    desc = _re_first(r'class="full cts-block"[^>]*>[\s\S]*?<div>([\s\S]*?)</div>', html)
    if desc: desc = _strip_tags(desc)

    meta = {}
    for m in re.finditer(r'<div>([\w\s]+?):</div>\s*<span>([\s\S]*?)</span>', html):
        meta[m.group(1).strip().lower()] = _strip_tags(m.group(2))

    genres = []
    detail_section = re.search(r'class="metadata"([\s\S]*?)</div>\s*</div>\s*</div>', html)
    if detail_section:
        genres = re.findall(r'href="[^"]*/genre/([^/"]+)"', detail_section.group(1))

    sub_eps = int((re.search(r'class="sub">.*?(\d+)', html) or [0, "0"])[1])
    dub_eps = int((re.search(r'class="dub">.*?(\d+)', html) or [0, "0"])[1])

    return Show(
        id=rid, title=title, slug=slug, japanese_title=jp,
        image_url=img, description=desc,
        type=meta.get("type"), status=meta.get("status"),
        genres=genres, episodes_count=int(meta.get("episodes", "0")),
        sub_episodes=sub_eps, dub_episodes=dub_eps,
        season=meta.get("premiered"), studio=meta.get("studios"),
        date_aired=meta.get("date aired"), mal_score=meta.get("mal"),
    )


# ---------------------------------------------------------------------------
# Episodes
# ---------------------------------------------------------------------------

def get_episodes(anime_id: str) -> list[EpisodeInfo]:
    """Fetch all episodes with their server IDs."""
    vrf = vrf_encode(anime_id)
    data = _get_json(f"{BASE}/ajax/episode/list/{anime_id}?vrf={vrf}")
    if data.get("status") != 200:
        return []

    html = data.get("result", "")
    eps = []
    for m in re.finditer(r'data-num="(\d+)"[^>]*data-ids="([^"]*)"', html):
        eps.append(EpisodeInfo(number=int(m.group(1)), server_ids=m.group(2)))
    return eps


def get_stream(anime_id: str, episode: int) -> Optional[str]:
    """Get the direct stream URL for a specific episode."""
    eps = get_episodes(anime_id)
    target = next((e for e in eps if e.number == episode), None)
    if not target or not target.server_ids:
        return None

    vrf = vrf_encode(anime_id)

    # Get server list
    sv_url = f"{BASE}/ajax/server/list?servers={quote(target.server_ids)}&vrf={vrf}"
    sv_data = _get_json(sv_url)
    if sv_data.get("status") != 200:
        return None

    sv_html = sv_data.get("result", "")
    link_id = _re_first(r'data-link-id="([^"]*)"', sv_html)
    if not link_id:
        return None

    # Get stream URL
    stream_url = f"{BASE}/ajax/server?get={quote(link_id)}&vrf={vrf}"
    stream_data = _get_json(stream_url)

    if stream_data.get("status") == 200:
        return stream_data.get("result", {}).get("url")

    return None


def get_all_streams(anime_id: str, episode: int) -> list[StreamSource]:
    """Get all available stream sources for an episode."""
    eps = get_episodes(anime_id)
    target = next((e for e in eps if e.number == episode), None)
    if not target or not target.server_ids:
        return []

    vrf = vrf_encode(anime_id)
    sv_url = f"{BASE}/ajax/server/list?servers={quote(target.server_ids)}&vrf={vrf}"
    sv_data = _get_json(sv_url)

    if sv_data.get("status") != 200:
        return []

    sv_html = sv_data.get("result", "")
    sources = []

    for m in re.finditer(
        r'data-link-id="([^"]*)"[^>]*>\s*(?:<div>)?\s*(?:<span[^>]*>)?\s*([^<\n]+?)\s*(?:</span>)?\s*(?:</div>)?\s*</div>',
        sv_html
    ):
        link_id = m.group(1)
        server_name = m.group(2).strip()
        if not server_name or server_name == '<':
            continue

        stream_url = f"{BASE}/ajax/server?get={quote(link_id)}&vrf={vrf}"
        try:
            stream_data = _get_json(stream_url)
            if stream_data.get("status") == 200:
                url = stream_data.get("result", {}).get("url", "")
                if url:
                    sources.append(StreamSource(server=server_name, url=url))
        except Exception:
            pass

    return sources


def resolve_source(stream_url: str) -> Optional[str]:
    """Resolve a stream URL to its actual M3U8 source.
    Fetches the embed page, extracts data-id, calls getSourcesNew API."""
    try:
        from urllib.request import Request, urlopen
        import re, json

        html = _get(stream_url)
        player_id = _re_first(r'data-id="(\d+)"', html)
        ep_type = stream_url.rstrip("/").rsplit("/", 1)[-1] or "sub"

        if not player_id:
            return None

        api_url = f"{stream_url.split('/stream/')[0]}/stream/getSourcesNew?id={player_id}&type={ep_type}"
        data = _get_json(api_url, {"Referer": stream_url})
        return data.get("sources", {}).get("file")
    except Exception:
        return None
