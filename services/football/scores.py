"""Live scores for the big leagues from football-data.org, attached to Streamed fixtures.

Streamed lists matches and streams but no scores. football-data.org's free plan covers the
top European leagues and the Champions League with scores a few minutes behind; the paid
"Livescores" plan is the same API in real time (set FOOTBALL_DATA_REALTIME=true then).
Without FOOTBALL_DATA_TOKEN the module is off and matches carry no score.
"""

from __future__ import annotations

import logging
import os
import re
import threading
import time
import unicodedata
from datetime import datetime, timedelta, timezone
from typing import Any

import requests

API_URL = "https://api.football-data.org/v4/matches"
REQUEST_TIMEOUT_SECONDS = 10
# The free plan allows 10 calls a minute; each worker makes at most one a minute while
# matches are on and one every five minutes otherwise.
LIVE_TTL_SECONDS = 60
IDLE_TTL_SECONDS = 5 * 60
ERROR_TTL_SECONDS = 2 * 60
KICKOFF_WINDOW_SECONDS = 2 * 60 * 60
MIN_TEAM_SIMILARITY = 0.5

_STATUS = {
    "SCHEDULED": "scheduled",
    "TIMED": "scheduled",
    "IN_PLAY": "live",
    "PAUSED": "halftime",
    "FINISHED": "finished",
    "AWARDED": "finished",
    "SUSPENDED": "suspended",
    "POSTPONED": "postponed",
    "CANCELLED": "cancelled",
}
_SOON_SECONDS = 15 * 60

# Words that say "this is a club" rather than which club.
_FILLER = {
    "fc", "afc", "cf", "sc", "ac", "as", "ss", "ssc", "cd", "ud", "rc", "rcd", "sd", "club",
    "de", "del", "la", "the", "calcio", "fk", "sk", "bk", "sv", "vfb", "vfl", "tsg", "bsc",
    "fsv", "osc", "ogc", "stade", "and", "us", "aj", "sco",
}
# Common names that share no word with the official one.
_ALIASES = {
    "spurs": "tottenham",
    "wolves": "wolverhampton",
    "inter": "internazionale",
    "munich": "munchen",
    "psg": "paris",
    "atleti": "atletico",
    "barca": "barcelona",
    "gladbach": "monchengladbach",
    "rennes": "rennais",
}

log = logging.getLogger(__name__)
_session = requests.Session()
_lock = threading.Lock()
_cache: tuple[float, float, list[dict[str, Any]]] | None = None  # (fetched_at, ttl, matches)


def token() -> str | None:
    value = os.environ.get("FOOTBALL_DATA_TOKEN", "").strip()
    return value or None


def enabled() -> bool:
    return token() is not None


def _realtime() -> bool:
    return os.environ.get("FOOTBALL_DATA_REALTIME", "").strip().lower() in {"1", "true", "yes", "on"}


# Matching ------------------------------------------------------------------------------------

def _tokens(*names: str | None) -> set[str]:
    words: set[str] = set()
    for name in names:
        if not name:
            continue
        plain = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
        for word in re.split(r"[^a-z0-9]+", plain):
            if not word or word.isdigit() or word in _FILLER:
                continue
            words.add(_ALIASES.get(word, word))
    return words


def _same_word(a: str, b: str) -> bool:
    return a == b or (len(a) >= 5 and len(b) >= 5 and a[:5] == b[:5])


def team_similarity(ours: set[str], theirs: set[str]) -> float:
    """Share of the shorter name's words found in the other name."""
    if not ours or not theirs:
        return 0.0
    shared = sum(1 for word in ours if any(_same_word(word, other) for other in theirs))
    return shared / min(len(ours), len(theirs))


def _split_title(title: str) -> tuple[str, str] | None:
    parts = re.split(r"\s+(?:vs\.?|v|-)\s+", title, maxsplit=1, flags=re.IGNORECASE)
    return (parts[0], parts[1]) if len(parts) == 2 else None


def _our_teams(match: dict[str, Any]) -> tuple[set[str], set[str]] | None:
    teams = match.get("teams") or {}
    home = (teams.get("home") or {}).get("name")
    away = (teams.get("away") or {}).get("name")
    if not home or not away:
        split = _split_title(match.get("title") or "")
        if not split:
            return None
        home, away = split
    return _tokens(home), _tokens(away)


def _their_team(team: dict[str, Any] | None) -> set[str]:
    team = team or {}
    return _tokens(team.get("name"), team.get("shortName"), team.get("tla"))


def _kickoff_seconds(value: Any) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def find_fixture(match: dict[str, Any], fixtures: list[dict[str, Any]]) -> dict[str, Any] | None:
    """The football-data fixture for a Streamed match: same kickoff (within two hours) and
    both teams recognisably the same, home as home. The best pairing wins."""
    ours = _our_teams(match)
    date = match.get("date")
    if not ours or not isinstance(date, (int, float)):
        return None
    kickoff = date / 1000
    best: tuple[float, dict[str, Any]] | None = None
    for fixture in fixtures:
        theirs = _kickoff_seconds(fixture.get("utcDate"))
        if theirs is None or abs(theirs - kickoff) > KICKOFF_WINDOW_SECONDS:
            continue
        home = team_similarity(ours[0], _their_team(fixture.get("homeTeam")))
        away = team_similarity(ours[1], _their_team(fixture.get("awayTeam")))
        if home < MIN_TEAM_SIMILARITY or away < MIN_TEAM_SIMILARITY:
            continue
        score = home + away
        if best is None or score > best[0]:
            best = (score, fixture)
    return best[1] if best else None


def score_for(fixture: dict[str, Any]) -> dict[str, Any]:
    status = _STATUS.get(str(fixture.get("status")), "scheduled")
    full_time = ((fixture.get("score") or {}).get("fullTime")) or {}
    home, away = full_time.get("home"), full_time.get("away")
    has_score = isinstance(home, int) and isinstance(away, int)
    if status in {"live", "halftime", "finished", "suspended"} and not has_score:
        home, away = 0, 0
        has_score = True
    minute = fixture.get("minute")
    injury = fixture.get("injuryTime")
    return {
        "home": home if has_score else None,
        "away": away if has_score else None,
        "status": status,
        "minute": minute if isinstance(minute, int) and status == "live" else None,
        "injuryTime": injury if isinstance(injury, int) and status == "live" else None,
        "competition": ((fixture.get("competition") or {}).get("name")) or None,
        "delayed": not _realtime(),
        "updatedAt": fixture.get("lastUpdated"),
    }


# Fetching ------------------------------------------------------------------------------------

def _ttl_for(fixtures: list[dict[str, Any]], now: float) -> float:
    for fixture in fixtures:
        status = _STATUS.get(str(fixture.get("status")))
        kickoff = _kickoff_seconds(fixture.get("utcDate"))
        if status in {"live", "halftime"}:
            return LIVE_TTL_SECONDS
        if status == "scheduled" and kickoff is not None and 0 <= kickoff - now <= _SOON_SECONDS:
            return LIVE_TTL_SECONDS
    return IDLE_TTL_SECONDS


def _fetch(api_token: str) -> list[dict[str, Any]]:
    today = datetime.now(timezone.utc).date()
    response = _session.get(
        API_URL,
        params={
            "dateFrom": (today - timedelta(days=1)).isoformat(),
            "dateTo": (today + timedelta(days=1)).isoformat(),
        },
        headers={"X-Auth-Token": api_token, "Accept": "application/json"},
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    fixtures = payload.get("matches") if isinstance(payload, dict) else None
    if not isinstance(fixtures, list):
        raise ValueError("football-data.org returned no match list")
    return [item for item in fixtures if isinstance(item, dict)]


def fixtures() -> list[dict[str, Any]]:
    """Recent and upcoming big-league fixtures, cached; empty when off or failing."""
    global _cache
    api_token = token()
    if not api_token:
        return []
    now = time.time()
    with _lock:
        if _cache and now - _cache[0] < _cache[1]:
            return _cache[2]
    try:
        result = _fetch(api_token)
        ttl = _ttl_for(result, now)
    except (requests.RequestException, ValueError) as error:
        log.warning("football-data.org request failed: %s", error)
        result, ttl = (_cache[2] if _cache else []), ERROR_TTL_SECONDS
    with _lock:
        _cache = (now, ttl, result)
    return result


def attach(matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Adds `score` (or None) to each match. Never raises: scores are a garnish."""
    try:
        known = fixtures()
    except Exception:  # noqa: BLE001 - a scores failure must not take match lists down
        log.exception("Attaching scores failed")
        known = []
    for match in matches:
        fixture = find_fixture(match, known) if known else None
        match["score"] = score_for(fixture) if fixture else None
    return matches


def clear_cache() -> None:
    global _cache
    with _lock:
        _cache = None
