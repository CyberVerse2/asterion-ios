import unittest
from unittest.mock import patch

import app
from genre_catalog import merge_genres


class GenreCatalogTests(unittest.TestCase):
    def test_merges_database_and_live_source_genres(self):
        database_genres = [
            {"slug": "old-action", "title": "Action"},
            {"slug": "drama", "title": "Drama"},
        ]
        source_genres = [
            {"slug": "current-action", "title": "Action"},
            {"slug": "comedy", "title": "Comedy"},
        ]

        genres = merge_genres(database_genres, source_genres)

        self.assertEqual(
            genres,
            [
                {"slug": "current-action", "title": "Action"},
                {"slug": "comedy", "title": "Comedy"},
                {"slug": "drama", "title": "Drama"},
            ],
        )


class CachedCatalogTests(unittest.TestCase):
    @patch("app.db.cache_set")
    @patch("app.db.cache_get", return_value=None)
    def test_falls_back_to_database_when_scrape_fails(self, _cache_get, cache_set):
        fallback = {"page": 1, "total_pages": 1, "results": [{"title": "Cached"}]}
        with patch.object(app.app.logger, "exception"):
            result = app._cached_or_scrape(
                "discovery:movies:page:1",
                lambda: (_ for _ in ()).throw(RuntimeError("handshake failure")),
                fallback=lambda: fallback,
            )
        self.assertEqual(result, fallback)
        cache_set.assert_not_called()

    @patch("app.db.cache_set")
    @patch("app.db.cache_get", return_value=None)
    def test_does_not_cache_empty_scrape_results(self, _cache_get, cache_set):
        result = app._cached_or_scrape(
            "discovery:movies:page:1",
            lambda: {"page": 1, "total_pages": 1, "results": []},
        )
        self.assertEqual(result, {"page": 1, "total_pages": 1, "results": []})
        cache_set.assert_not_called()

    @patch("app.db.cache_set")
    @patch("app.db.cache_get", return_value=None)
    def test_caches_successful_scrape_results(self, _cache_get, cache_set):
        payload = {"page": 1, "total_pages": 1, "results": [{"title": "Mayday"}]}
        result = app._cached_or_scrape("discovery:movies:page:1", lambda: payload)
        self.assertEqual(result, payload)
        cache_set.assert_called_once()


if __name__ == "__main__":
    unittest.main()
