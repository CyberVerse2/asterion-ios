"""Asterion Football API."""

from functools import wraps

import flask

import streamed

app = flask.Flask(__name__)


def _football_response(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return flask.jsonify({"success": True, "data": fn(*args, **kwargs)})
        except streamed.FootballSourceError as error:
            app.logger.exception("Football source request failed")
            return flask.jsonify({"success": False, "error": str(error)}), 502

    return wrapper


@app.after_request
def add_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    return response


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/api/matches")
@_football_response
def matches():
    return streamed.matches()


@app.get("/api/matches/live")
@_football_response
def live_matches():
    return streamed.live_matches()


@app.get("/api/matches/popular")
@_football_response
def popular_matches():
    return streamed.popular_matches()


@app.post("/api/streams")
def streams():
    body = flask.request.get_json(silent=True)
    if not isinstance(body, dict):
        return {"success": False, "error": "A JSON request body is required."}, 400

    match_id = body.get("matchId")
    home_team = body.get("homeTeam")
    away_team = body.get("awayTeam")
    sources = body.get("sources")
    if (
        not isinstance(match_id, str)
        or not match_id.strip()
        or not isinstance(home_team, str)
        or not isinstance(away_team, str)
        or not isinstance(sources, list)
    ):
        return {"success": False, "error": "Invalid stream request."}, 400

    try:
        resolved = streamed.resolve_streams(sources)
    except streamed.FootballSourceError as error:
        app.logger.exception("Football stream request failed")
        return {"success": False, "error": str(error)}, 502

    return {
        "success": True,
        "data": {
            "streams": resolved,
            "matchId": match_id,
            "homeTeam": home_team,
            "awayTeam": away_team,
        },
    }
