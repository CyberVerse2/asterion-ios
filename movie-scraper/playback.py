"""Direct media verification and safe proxy helpers."""

from __future__ import annotations

import ipaddress
import os
import re
import socket
from datetime import datetime, timezone
from urllib.parse import quote, urljoin, urlparse

import requests


PUBLIC_BASE_URL = os.environ.get(
    "PUBLIC_BASE_URL",
    "https://asterion-movies.cyberverse.cloud",
).rstrip("/")

UPSTREAM_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
    ),
    "Accept": "*/*",
    "Origin": "https://play.xpass.top",
    "Referer": "https://play.xpass.top/",
}

PLAYLIST_CONTENT_LIMIT = 1_048_576
PROBE_BYTE_LIMIT = 65_536
REQUEST_TIMEOUT = (4, 8)
PLAYLIST_CONTENT_TYPES = (
    "application/vnd.apple.mpegurl",
    "application/x-mpegurl",
    "audio/mpegurl",
    "audio/x-mpegurl",
)


def is_direct_stream(url: str) -> bool:
    normalized = url.lower()
    path = urlparse(normalized).path
    return (
        ".m3u8" in normalized
        or "1x2.space" in normalized
        or "greenplanetstore" in normalized
        or "workers.dev" in normalized
        or path.endswith(".txt")
        or path.endswith(".mp4")
    )


def proxy_url(target: str) -> str:
    return f"{PUBLIC_BASE_URL}/proxy/hls?url={quote(target, safe='')}"


def verify_direct_source(source: dict) -> dict | None:
    target = source.get("embed_url", "")
    if not (source.get("is_hls") or is_direct_stream(target)) or not _is_safe_remote_url(target):
        return None
    try:
        if not _verify_resource(target, depth=0):
            return None
    except requests.RequestException:
        return None

    verified = source.copy()
    verified["is_hls"] = True
    verified["is_verified"] = True
    verified["automatic"] = True
    verified["proxy_url"] = proxy_url(target)
    verified["verified_at"] = datetime.now(timezone.utc).isoformat()
    return verified


def fetch_upstream(target: str, range_header: str | None = None) -> requests.Response:
    if not _is_safe_remote_url(target):
        raise ValueError("Unsafe upstream URL")

    headers = UPSTREAM_HEADERS.copy()
    if range_header:
        headers["Range"] = range_header
    response = requests.get(
        target,
        headers=headers,
        stream=True,
        timeout=REQUEST_TIMEOUT,
        allow_redirects=True,
    )
    redirect_urls = [item.url for item in response.history] + [response.url]
    if not all(_is_safe_remote_url(url) for url in redirect_urls):
        response.close()
        raise ValueError("Unsafe upstream redirect")
    return response


def is_playlist_response(target: str, content_type: str) -> bool:
    normalized_type = content_type.lower().split(";", 1)[0].strip()
    return ".m3u8" in target.lower() or normalized_type in PLAYLIST_CONTENT_TYPES


def rewrite_playlist(body: str, source_url: str) -> str:
    def proxied(reference: str) -> str:
        return proxy_url(urljoin(source_url, reference.strip()))

    rewritten: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped:
            rewritten.append(line)
            continue
        if stripped.startswith("#"):
            rewritten.append(
                re.sub(
                    r'URI=("|\')([^"\']+)(\1)',
                    lambda match: (
                        f"URI={match.group(1)}{proxied(match.group(2))}{match.group(3)}"
                    ),
                    line,
                )
            )
            continue
        rewritten.append(proxied(stripped))
    return "\n".join(rewritten) + ("\n" if body.endswith("\n") else "")


def read_limited(response: requests.Response, limit: int) -> bytes:
    chunks: list[bytes] = []
    size = 0
    for chunk in response.iter_content(chunk_size=16_384):
        if not chunk:
            continue
        remaining = limit - size
        if remaining <= 0:
            break
        chunks.append(chunk[:remaining])
        size += min(len(chunk), remaining)
        if size >= limit:
            break
    return b"".join(chunks)


def _verify_resource(target: str, depth: int) -> bool:
    if depth > 2:
        return False
    response = fetch_upstream(target, range_header="bytes=0-65535")
    try:
        if response.status_code not in (200, 206):
            return False
        content_type = response.headers.get("Content-Type", "")
        data = read_limited(response, PLAYLIST_CONTENT_LIMIT)
    finally:
        response.close()

    if not data:
        return False
    text = data.decode("utf-8", errors="replace")
    if is_playlist_response(target, content_type) or text.lstrip().startswith("#EXTM3U"):
        return _verify_playlist(text, response.url, depth)

    normalized_type = content_type.lower()
    if "text/html" in normalized_type or text.lstrip().lower().startswith("<!doctype html"):
        return False
    return len(data) >= min(PROBE_BYTE_LIMIT, 1_024)


def _verify_playlist(body: str, source_url: str, depth: int) -> bool:
    if not body.lstrip().startswith("#EXTM3U"):
        return False

    key_urls = re.findall(r'#EXT-X-(?:KEY|MAP):[^\n]*URI=["\']([^"\']+)', body)
    for key_url in key_urls[:1]:
        if not _verify_binary(urljoin(source_url, key_url), minimum_bytes=1):
            return False

    references = [
        line.strip()
        for line in body.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if not references:
        return False

    first_reference = urljoin(source_url, references[0])
    return _verify_resource(first_reference, depth + 1)


def _verify_binary(target: str, minimum_bytes: int) -> bool:
    response = fetch_upstream(target, range_header="bytes=0-1023")
    try:
        if response.status_code not in (200, 206):
            return False
        data = read_limited(response, 1_024)
        return len(data) >= minimum_bytes
    finally:
        response.close()


def _is_safe_remote_url(value: str) -> bool:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        return False
    try:
        addresses = socket.getaddrinfo(parsed.hostname, parsed.port or 443, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return False
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        ):
            return False
    return True
