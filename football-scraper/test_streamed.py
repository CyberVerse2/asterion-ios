import unittest
from unittest.mock import Mock, patch

import app as football_app
import streamed


def response(payload, status=200):
    result = Mock()
    result.json.return_value = payload
    result.raise_for_status.side_effect = None
    if status >= 400:
        result.raise_for_status.side_effect = streamed.requests.HTTPError(str(status))
    return result


class StreamedTests(unittest.TestCase):
    def setUp(self):
        streamed.clear_cache()

    @patch.object(streamed._session, "get")
    def test_optional_teams_and_arbitrary_sources_are_supported(self, get):
        fixture = {
            "id": "fixture-1",
            "title": "Home vs Away",
            "category": "football",
            "date": 1_784_330_000_000,
            "popular": True,
            "teams": None,
            "sources": [{"source": "charlie", "id": "stream-1"}],
        }
        get.side_effect = [response([fixture]), response([])]

        result = streamed.matches()

        self.assertEqual(result[0]["teams"], None)
        self.assertEqual(result[0]["sources"][0]["source"], "charlie")
        self.assertFalse(result[0]["isLive"])

    @patch.object(streamed._session, "get")
    def test_live_feed_marks_football_matches_live(self, get):
        fixture = {
            "id": "fixture-2",
            "title": "United vs City",
            "category": "football",
            "date": 1_784_330_000_000,
            "poster": "/api/images/proxy/poster.webp",
            "popular": False,
            "teams": {
                "home": {"name": "United", "badge": "badge+home"},
                "away": {"name": "City", "badge": "badge-away"},
            },
            "sources": [{"source": "admin", "id": "fixture-2"}],
        }
        get.return_value = response([fixture])

        result = streamed.live_matches()

        self.assertTrue(result[0]["isLive"])
        self.assertEqual(
            result[0]["teams"]["home"]["badgeURL"],
            "https://streamed.pk/api/images/badge/badge%2Bhome.webp",
        )
        self.assertEqual(
            result[0]["posterURL"],
            "https://streamed.pk/api/images/proxy/poster.webp",
        )

    @patch.object(streamed._session, "get")
    def test_empty_match_snapshot_is_not_cached(self, get):
        fixture = {
            "id": "fixture-after-empty",
            "title": "Home vs Away",
            "category": "football",
            "date": 1_784_330_000_000,
            "popular": False,
            "sources": [{"source": "echo", "id": "fixture-after-empty"}],
        }
        get.side_effect = [response([]), response([fixture])]

        self.assertEqual(streamed._match_feed("/matches/live"), [])
        self.assertEqual(
            streamed._match_feed("/matches/live")[0]["id"],
            "fixture-after-empty",
        )
        self.assertEqual(get.call_count, 2)

    @patch.object(streamed._session, "get")
    def test_empty_schedule_snapshot_is_cached(self, get):
        get.return_value = response([])

        self.assertEqual(streamed._match_feed("/matches/football"), [])
        self.assertEqual(streamed._match_feed("/matches/football"), [])
        self.assertEqual(get.call_count, 1)

    @patch.object(streamed._session, "get")
    def test_schedule_includes_live_football_matches(self, get):
        fixture = {
            "id": "live-fixture",
            "title": "United vs City",
            "category": "football",
            "date": 1_784_330_000_000,
            "popular": False,
            "sources": [{"source": "echo", "id": "live-fixture"}],
        }
        get.side_effect = [response([]), response([fixture])]

        result = streamed.matches()

        self.assertEqual([match["id"] for match in result], ["live-fixture"])
        self.assertTrue(result[0]["isLive"])

    @patch.object(streamed._session, "get")
    def test_popular_includes_popular_live_football_matches(self, get):
        fixture = {
            "id": "popular-live-fixture",
            "title": "United vs City",
            "category": "football",
            "date": 1_784_330_000_000,
            "popular": True,
            "sources": [{"source": "echo", "id": "popular-live-fixture"}],
        }
        get.side_effect = [response([]), response([fixture])]

        result = streamed.popular_matches()

        self.assertEqual([match["id"] for match in result], ["popular-live-fixture"])
        self.assertTrue(result[0]["isLive"])

    @patch.object(streamed._session, "get")
    def test_streams_keep_working_provider_when_another_fails(self, get):
        def result(url, **_kwargs):
            if "/admin/" in url:
                return response([], status=503)
            return response([
                {
                    "id": "stream-1",
                    "streamNo": 1,
                    "language": "English",
                    "hd": True,
                    "embedUrl": "https://embed.example/stream-1",
                    "source": "echo",
                    "viewers": 42,
                }
            ])

        get.side_effect = result
        streams = streamed.resolve_streams([
            {"source": "admin", "id": "bad"},
            {"source": "echo", "id": "good"},
        ])

        self.assertEqual(len(streams), 1)
        self.assertEqual(streams[0]["source"], "echo")


class RouteTests(unittest.TestCase):
    def setUp(self):
        football_app.app.config.update(TESTING=True)
        self.client = football_app.app.test_client()

    def test_invalid_stream_request_is_rejected(self):
        result = self.client.post("/api/streams", json={})
        self.assertEqual(result.status_code, 400)
        self.assertFalse(result.get_json()["success"])

    @patch("app.streamed.resolve_streams")
    def test_teamless_match_can_resolve_streams(self, resolve_streams):
        resolve_streams.return_value = [
            {
                "id": "stream-1",
                "streamNo": 1,
                "language": "English",
                "hd": True,
                "embedUrl": "https://embed.example/stream-1",
                "source": "echo",
                "viewers": None,
            }
        ]

        result = self.client.post(
            "/api/streams",
            json={
                "matchId": "teamless-match",
                "homeTeam": None,
                "awayTeam": None,
                "sources": [{"source": "echo", "id": "teamless-match"}],
            },
        )

        self.assertEqual(result.status_code, 200)
        self.assertIsNone(result.get_json()["data"]["homeTeam"])
        self.assertIsNone(result.get_json()["data"]["awayTeam"])

    @patch("app.streamed.popular_matches")
    def test_source_failure_is_visible(self, popular_matches):
        popular_matches.side_effect = streamed.FootballSourceError("Provider unavailable.")
        result = self.client.get("/api/matches/popular")
        self.assertEqual(result.status_code, 502)
        self.assertEqual(result.get_json()["error"], "Provider unavailable.")


if __name__ == "__main__":
    unittest.main()
