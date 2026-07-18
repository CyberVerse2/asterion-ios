"""Validated football data access for Streamed's public API."""

from __future__ import annotations

import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any
from urllib.parse import quote, urljoin

import requests

STREAMED_ORIGIN = "https://streamed.pk"
STREAMED_API = f"{STREAMED_ORIGIN}/api"
MATCH_CACHE_TTL_SECONDS = 60
REQUEST_TIMEOUT_SECONDS = 20


class FootballSourceError(RuntimeError):
    """The football provider failed or returned data outside its contract."""


_session = requests.Session()
_session.headers.update({
    "Accept": "application/json",
    "User-Agent": "Asterion-Football/1.0",
})
_cache_lock = threading.Lock()
_match_cache: dict[str, tuple[float, list[dict[str, Any]]]] = {}


def _required_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise FootballSourceError(f"The source returned an invalid {field}.")
    return value


def _optional_team(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise FootballSourceError("The source returned an invalid team.")

    name = _required_string(value.get("name"), "team name")
    badge = value.get("badge") or ""
    if not isinstance(badge, str):
        raise FootballSourceError("The source returned an invalid team badge.")
    badge_url = (
        f"{STREAMED_API}/images/badge/{quote(badge, safe='')}.webp"
        if badge
        else None
    )
    return {"name": name, "badge": badge, "badgeURL": badge_url}


def _source(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        raise FootballSourceError("The source returned an invalid stream provider.")
    return {
        "source": _required_string(value.get("source"), "stream provider"),
        "id": _required_string(value.get("id"), "stream provider id"),
    }


def _match(value: Any, live_ids: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise FootballSourceError("The source returned an invalid match.")

    match_id = _required_string(value.get("id"), "match id")
    date = value.get("date")
    if not isinstance(date, (int, float)) or isinstance(date, bool):
        raise FootballSourceError("The source returned an invalid match date.")

    popular = value.get("popular")
    if not isinstance(popular, bool):
        raise FootballSourceError("The source returned an invalid popularity flag.")

    raw_sources = value.get("sources")
    if not isinstance(raw_sources, list):
        raise FootballSourceError("The source returned invalid stream providers.")

    raw_teams = value.get("teams")
    if raw_teams is not None and not isinstance(raw_teams, dict):
        raise FootballSourceError("The source returned invalid teams.")

    poster = value.get("poster")
    if poster is not None and not isinstance(poster, str):
        raise FootballSourceError("The source returned an invalid poster.")

    return {
        "id": match_id,
        "title": _required_string(value.get("title"), "match title"),
        "category": _required_string(value.get("category"), "match category"),
        "date": int(date),
        "poster": poster,
        "posterURL": urljoin(STREAMED_ORIGIN, poster) if poster else None,
        "popular": popular,
        "isLive": match_id in live_ids,
        "teams": (
            {
                "home": _optional_team(raw_teams.get("home")),
                "away": _optional_team(raw_teams.get("away")),
            }
            if raw_teams is not None
            else None
        ),
        "sources": [_source(item) for item in raw_sources],
    }


def _get_json(path: str) -> Any:
    try:
        response = _session.get(
            f"{STREAMED_API}{path}",
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()
    except (requests.RequestException, ValueError) as error:
        raise FootballSourceError(f"The football source failed for {path}.") from error


def _match_feed(path: str) -> list[dict[str, Any]]:
    with _cache_lock:
        cached = _match_cache.get(path)
        if cached and time.monotonic() - cached[0] < MATCH_CACHE_TTL_SECONDS:
            return cached[1]

    payload = _get_json(path)
    if not isinstance(payload, list):
        raise FootballSourceError("The source returned an invalid match list.")

    # Validate the stable upstream shape before a successful response is cached.
    for item in payload:
        _match(item, set())

    with _cache_lock:
        # Streamed's live feed can briefly return an empty snapshot between
        # populated responses. Other match feeds use an empty list as a stable
        # result and can be cached normally.
        if payload or path != "/matches/live":
            _match_cache[path] = (time.monotonic(), payload)
    return payload


def _live_raw() -> list[dict[str, Any]]:
    return [
        item
        for item in _match_feed("/matches/live")
        if str(item.get("category", "")).lower() == "football"
    ]


def _normalized(matches: list[dict[str, Any]], live: list[dict[str, Any]]) -> list[dict[str, Any]]:
    live_ids = {_required_string(item.get("id"), "live match id") for item in live}
    return sorted((_match(item, live_ids) for item in matches), key=lambda item: item["date"])


def _merged_matches(*feeds: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for feed in feeds:
        for item in feed:
            match_id = _required_string(item.get("id"), "match id")
            merged[match_id] = item
    return list(merged.values())


def matches() -> list[dict[str, Any]]:
    scheduled = _match_feed("/matches/football")
    live = _live_raw()
    return _normalized(_merged_matches(scheduled, live), live)


def live_matches() -> list[dict[str, Any]]:
    live = _live_raw()
    return _normalized(live, live)


def popular_matches() -> list[dict[str, Any]]:
    popular = _match_feed("/matches/football/popular")
    live = _live_raw()
    popular_live = [item for item in live if item.get("popular") is True]
    return _normalized(_merged_matches(popular, popular_live), live)


def _stream(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise FootballSourceError("The source returned an invalid stream.")

    stream_number = value.get("streamNo")
    if not isinstance(stream_number, int) or isinstance(stream_number, bool):
        raise FootballSourceError("The source returned an invalid stream number.")
    hd = value.get("hd")
    if not isinstance(hd, bool):
        raise FootballSourceError("The source returned an invalid HD flag.")
    viewers = value.get("viewers")
    if viewers is not None and (not isinstance(viewers, int) or isinstance(viewers, bool)):
        raise FootballSourceError("The source returned an invalid viewer count.")

    return {
        "id": _required_string(value.get("id"), "stream id"),
        "streamNo": stream_number,
        "language": value.get("language") if isinstance(value.get("language"), str) else "",
        "hd": hd,
        "embedUrl": _required_string(value.get("embedUrl"), "embed URL"),
        "source": _required_string(value.get("source"), "stream source"),
        "viewers": viewers,
    }


def _streams_for_source(source: dict[str, str]) -> list[dict[str, Any]]:
    payload = _get_json(
        f"/stream/{quote(source['source'], safe='')}/{quote(source['id'], safe='')}"
    )
    if not isinstance(payload, list):
        raise FootballSourceError("The source returned an invalid stream list.")
    return [_stream(item) for item in payload]


def resolve_streams(sources: list[dict[str, str]]) -> list[dict[str, Any]]:
    validated_sources = [_source(item) for item in sources]
    if not validated_sources:
        raise FootballSourceError("This match has no stream providers.")

    streams: list[dict[str, Any]] = []
    failures: list[Exception] = []
    with ThreadPoolExecutor(max_workers=min(len(validated_sources), 8)) as executor:
        futures = [executor.submit(_streams_for_source, source) for source in validated_sources]
        for future in as_completed(futures):
            try:
                streams.extend(future.result())
            except FootballSourceError as error:
                failures.append(error)

    if not streams:
        cause = failures[0] if failures else None
        raise FootballSourceError("No stream provider responded for this match.") from cause

    unique: dict[tuple[str, int], dict[str, Any]] = {}
    for stream in streams:
        unique[(stream["embedUrl"], stream["streamNo"])] = stream
    return list(unique.values())


def clear_cache() -> None:
    """Clear successful source responses; used by tests and process maintenance."""
    with _cache_lock:
        _match_cache.clear()
