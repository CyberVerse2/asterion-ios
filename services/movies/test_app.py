import gzip
import io
import unittest
from unittest.mock import patch

import requests
from requests.structures import CaseInsensitiveDict
from urllib3 import HTTPResponse

import app
import db
import playback
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


def _upstream(status, body=b"", headers=None, url="https://cdn.example/media"):
    """Build a streamed requests.Response the way fetch_upstream returns it."""
    response = requests.Response()
    response.status_code = status
    response.headers = CaseInsensitiveDict(headers or {})
    response.url = url
    response.raw = HTTPResponse(
        body=io.BytesIO(body),
        headers=headers or {},
        status=status,
        preload_content=False,
        decode_content=True,
    )
    return response


class HLSProxyTests(unittest.TestCase):
    def setUp(self):
        self.client = app.app.test_client()
        sleep = patch("playback.time.sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

    def get(self, target, **kwargs):
        return self.client.get("/proxy/hls", query_string={"url": target}, **kwargs)

    @patch("playback.fetch_upstream")
    def test_upstream_gateway_timeout_becomes_a_labelled_503(self, fetch):
        fetch.side_effect = lambda *a, **k: _upstream(504, b"error code: 504")

        response = self.get("https://cdn.example/master.m3u8")

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["X-Upstream-Status"], "504")
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertEqual(fetch.call_count, playback.PROXY_ATTEMPTS)

    @patch("playback.fetch_upstream")
    def test_retries_a_transient_upstream_failure(self, fetch):
        fetch.side_effect = [
            requests.ReadTimeout(),
            _upstream(200, b"#EXTM3U\nseg-1.ts\n", url="https://cdn.example/a/index.m3u8"),
        ]

        response = self.get("https://cdn.example/a/index.m3u8")

        self.assertEqual(response.status_code, 200)
        self.assertIn(playback.proxy_url("https://cdn.example/a/seg-1.ts"), response.get_data(as_text=True))
        self.assertEqual(fetch.call_args.kwargs["timeout"], playback.PROXY_TIMEOUT)

    @patch("playback.fetch_upstream", side_effect=requests.ReadTimeout())
    def test_reports_repeated_timeouts(self, _fetch):
        response = self.get("https://cdn.example/master.m3u8")

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["X-Upstream-Status"], "timeout")

    @patch("playback.fetch_upstream")
    def test_does_not_rewrite_upstream_error_bodies(self, fetch):
        fetch.return_value = _upstream(403, b"<html>access denied: expired</html>")

        response = self.get("https://cdn.example/master.m3u8")

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.get_data(as_text=True), "Upstream returned 403")
        self.assertEqual(fetch.call_count, 1)

    @patch("playback.fetch_upstream")
    def test_rejects_html_served_as_a_playlist(self, fetch):
        fetch.return_value = _upstream(
            200, b"<!doctype html><p>gone</p>", url="https://cdn.example/master.m3u8",
        )

        response = self.get("https://cdn.example/master.m3u8")

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["X-Upstream-Status"], "invalid-playlist")

    @patch("playback.fetch_upstream")
    def test_sniffs_compressed_playlists_without_an_m3u8_extension(self, fetch):
        body = gzip.compress(b"#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"/k\"\n/seg/1\n")
        fetch.return_value = _upstream(
            200,
            body,
            {"Content-Type": "text/plain", "Content-Encoding": "gzip", "Content-Length": str(len(body))},
            url="https://mol.example/playlist/abc",
        )

        response = self.get("https://mol.example/playlist/abc")
        text = response.get_data(as_text=True)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content_type, "application/vnd.apple.mpegurl")
        self.assertIn(playback.proxy_url("https://mol.example/seg/1"), text)
        self.assertIn(f'URI="{playback.proxy_url("https://mol.example/k")}"', text)

    @patch("playback.fetch_upstream")
    def test_drops_length_headers_for_decoded_bodies(self, fetch):
        payload = b"\x47" * 5000
        body = gzip.compress(payload)
        fetch.return_value = _upstream(
            200,
            body,
            {"Content-Type": "video/mp2t", "Content-Encoding": "gzip", "Content-Length": str(len(body))},
        )

        response = self.get("https://cdn.example/seg.ts")

        self.assertEqual(response.get_data(), payload)
        self.assertNotEqual(response.headers.get("Content-Length"), str(len(body)))

    @patch("playback.fetch_upstream")
    def test_streams_ranged_segments_with_their_headers(self, fetch):
        payload = b"\x89PNG" + b"\x00" * 1020
        fetch.return_value = _upstream(
            206,
            payload,
            {
                "Content-Type": "image/png",
                "Content-Length": str(len(payload)),
                "Content-Range": f"bytes 0-1023/{len(payload) * 4}",
                "Accept-Ranges": "bytes",
            },
        )

        response = self.get("https://cdn.example/seg-1", headers={"Range": "bytes=0-1023"})

        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.get_data(), payload)
        self.assertEqual(response.headers["Content-Length"], str(len(payload)))
        self.assertEqual(response.headers["Content-Range"], f"bytes 0-1023/{len(payload) * 4}")
        self.assertEqual(response.headers["Cache-Control"], "public, max-age=3600")
        self.assertEqual(fetch.call_args.args[1], "bytes=0-1023")

    @patch("playback.fetch_upstream")
    def test_refuses_oversized_playlists_instead_of_truncating(self, fetch):
        body = b"#EXTM3U\n" + b"seg.ts\n" * (playback.PLAYLIST_CONTENT_LIMIT // 7 + 1)
        fetch.return_value = _upstream(200, body, url="https://cdn.example/index.m3u8")

        response = self.get("https://cdn.example/index.m3u8")

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["X-Upstream-Status"], "playlist-too-large")



class PlaylistRewriteTests(unittest.TestCase):
    def test_drops_stray_uri_lines_after_media_tags(self):
        body = (
            "#EXTM3U\n"
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="English",URI="audio-en.m3u8"\n'
            "audio-en.m3u8\n"
            "\n"
            '#EXT-X-STREAM-INF:BANDWIDTH=800000,AUDIO="a"\n'
            "video-720.m3u8\n"
        )
        rewritten = playback.rewrite_playlist(body, "https://cdn.example/movie/master.m3u8")
        uri_lines = [line for line in rewritten.splitlines() if line and not line.startswith("#")]
        self.assertEqual(len(uri_lines), 1)
        self.assertIn("video-720.m3u8", uri_lines[0])
        self.assertIn("audio-en.m3u8", rewritten.splitlines()[1])

    def test_keeps_every_segment_in_media_playlists(self):
        body = "#EXTM3U\n#EXTINF:6.0,\nseg1.ts\n#EXTINF:6.0,\nseg2.ts\n#EXT-X-ENDLIST\n"
        rewritten = playback.rewrite_playlist(body, "https://cdn.example/movie/index.m3u8")
        uri_lines = [line for line in rewritten.splitlines() if line and not line.startswith("#")]
        self.assertEqual(len(uri_lines), 2)


if __name__ == "__main__":
    unittest.main()
