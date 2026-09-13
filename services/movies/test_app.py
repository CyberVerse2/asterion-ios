import unittest
from unittest.mock import patch

import app
import db
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

    @patch("app.db.get_movie_list", return_value={"results": []})
    @patch("app.db.get_popular", return_value={"results": [{"id": "1", "slug": "mayday", "title": "Mayday"}]})
    def test_trending_uses_database_titles(self, _get_popular, _get_movie_list):
        self.assertEqual(
            app._database_titles("movie"),
            [{"id": "1", "slug": "mayday", "title": "Mayday"}],
        )


class DatabaseTitleTests(unittest.TestCase):
    def test_maps_poster_and_year_for_the_app(self):
        title = db._row_to_title({
            "imdb_id": "tt123",
            "tmdb_id": None,
            "title": "Mayday",
            "slug": "mayday",
            "poster_url": "https://img.example/mayday.jpg",
            "release_year": 2024,
            "runtime": "1h 40min",
            "imdb_rating": 8.2,
            "type": "movie",
        })
        self.assertEqual(title["id"], "tt123")
        self.assertEqual(title["year"], "2024")
        self.assertEqual(title["image_url"], "https://img.example/mayday.jpg")
        self.assertEqual(title["imdb_rating"], "8.2")


if __name__ == "__main__":
    unittest.main()
