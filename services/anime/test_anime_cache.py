import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import app
from anime_cache import AnimeCache, AnimeCacheError


class FakeLock:
    def __init__(self):
        self.acquired = False

    def acquire(self, blocking=True):
        self.acquired = True
        return True

    def release(self):
        self.acquired = False


class FakeRedis:
    def __init__(self):
        self.values = {}
        self.ttls = {}
        self.ping_count = 0

    def ping(self):
        self.ping_count += 1
        return True

    def get(self, key):
        return self.values.get(key)

    def setex(self, key, ttl, value):
        self.values[key] = value
        self.ttls[key] = ttl

    def lock(self, key, timeout, blocking_timeout):
        return FakeLock()


class AnimeCacheTests(unittest.TestCase):
    def test_cache_miss_is_loaded_once_then_reused(self):
        client = FakeRedis()
        cache = AnimeCache(client)
        calls = []

        first = cache.get_or_load(
            "show:test",
            300,
            lambda: calls.append("loaded") or {"id": "123"},
        )
        second = cache.get_or_load(
            "show:test",
            300,
            lambda: calls.append("loaded-again") or {"id": "456"},
        )

        self.assertEqual(first, {"id": "123"})
        self.assertEqual(second, {"id": "123"})
        self.assertEqual(calls, ["loaded"])
        self.assertEqual(
            client.ttls["asterion:anime:v1:show:test"],
            300,
        )

    def test_invalid_cached_json_is_reported(self):
        client = FakeRedis()
        client.values["asterion:anime:v1:show:test"] = "{"
        cache = AnimeCache(client)

        with self.assertRaisesRegex(AnimeCacheError, "invalid data"):
            cache.get_json("show:test")


class AnimeEndpointCacheTests(unittest.TestCase):
    def setUp(self):
        self.client = FakeRedis()
        self.cache = AnimeCache(self.client)
        self.client_app = app.app.test_client()

    def test_show_detail_is_cached_and_records_status(self):
        show = SimpleNamespace(
            id="7457",
            slug="sample",
            title="Sample",
            status="Finished Airing",
        )

        with patch.object(app, "anime_cache", return_value=self.cache), \
                patch.object(app.animixplay, "show_detail", return_value=show) as loader:
            first = self.client_app.get("/api/amp/show/sample")
            second = self.client_app.get("/api/amp/show/sample")

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(loader.call_count, 1)
        status_payload = self.client.values[
            "asterion:anime:v1:status:7457"
        ]
        self.assertEqual(json.loads(status_payload), "Finished Airing")

    def test_completed_show_episodes_use_long_cache_lifetime(self):
        self.cache.set_json(
            "status:7457",
            "Finished Airing",
            app.SHOW_CACHE_TTL_SECONDS,
        )
        episode = SimpleNamespace(number=1)

        with patch.object(app, "anime_cache", return_value=self.cache), \
                patch.object(app.animixplay, "get_episodes", return_value=[episode]) as loader:
            first = self.client_app.get("/api/amp/episodes/7457")
            second = self.client_app.get("/api/amp/episodes/7457")

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(loader.call_count, 1)
        self.assertEqual(
            self.client.ttls["asterion:anime:v1:episodes:7457"],
            app.COMPLETED_EPISODES_CACHE_TTL_SECONDS,
        )

    def test_health_reports_redis_readiness(self):
        with patch.object(app, "anime_cache", return_value=self.cache):
            response = self.client_app.get("/api/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"status": "ok", "redis": "ok"})
        self.assertEqual(self.client.ping_count, 1)


if __name__ == "__main__":
    unittest.main()
