import unittest

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


if __name__ == "__main__":
    unittest.main()
