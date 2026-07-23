import os
import unittest
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse
from unittest.mock import patch

import app


class SubtitleProxyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.previous_signing_key = os.environ.get("MEDIA_PROXY_SIGNING_KEY")
        os.environ["MEDIA_PROXY_SIGNING_KEY"] = "test-key-" + ("a" * 32)

    @classmethod
    def tearDownClass(cls):
        if cls.previous_signing_key is None:
            os.environ.pop("MEDIA_PROXY_SIGNING_KEY", None)
        else:
            os.environ["MEDIA_PROXY_SIGNING_KEY"] = cls.previous_signing_key

    def test_kotocdn_subtitles_are_routed_through_the_secure_proxy(self):
        source = (
            "https://vidtub.kotocdn.site/media/subtitles/English.vtt"
        )

        tracks = app._proxied_subtitle_tracks(
            [{"file": source, "label": "English", "kind": "captions"}],
            "https://vidtube.site",
        )

        proxied_url = tracks[0]["file"]
        parsed = urlparse(proxied_url)
        self.assertEqual(parsed.path, "/proxy/subtitle")
        self.assertEqual(parse_qs(parsed.query)["url"], [source])
        self.assertIn("signature", parse_qs(parsed.query))

    def test_kotocdn_uses_the_vidtube_provider_context(self):
        headers = app._hls_request_headers("https://vidtube.site")

        self.assertEqual(headers["Origin"], "https://vidtube.site")
        self.assertEqual(headers["Referer"], "https://vidtube.site/")

    def test_mewstream_uses_the_megaplay_provider_context(self):
        source = "https://cdn.mewstream.buzz/anime/title/master.m3u8"
        provider = app._provider_origin(
            "https://megaplay.buzz/stream/s-2/735790/sub"
        )
        headers = app._hls_request_headers(provider)

        self.assertTrue(app._is_safe_signed_target(source))
        self.assertEqual(provider, "https://megaplay.buzz")
        self.assertEqual(headers["Origin"], "https://megaplay.buzz")
        self.assertEqual(headers["Referer"], "https://megaplay.buzz/")

    def test_megaplay_context_is_preserved_in_rewritten_segments(self):
        proxied_url = app._proxied_hls_path(
            "https://x5y0d.cloudbuzz.lol/anime/title/segment.jpg",
            "https://megaplay.buzz",
        )
        query = parse_qs(urlparse(proxied_url).query)

        self.assertEqual(query["provider"], ["https://megaplay.buzz"])
        headers = app._hls_request_headers(query["provider"][0])
        self.assertEqual(headers["Origin"], "https://megaplay.buzz")
        self.assertEqual(headers["Referer"], "https://megaplay.buzz/")

    def test_unsafe_provider_context_is_rejected(self):
        self.assertIsNone(
            app._provider_origin("http://provider.example/stream/episode")
        )
        with self.assertRaises(ValueError):
            app._hls_request_headers("http://provider.example")

    def test_proxy_token_rejects_tampering_and_expiry(self):
        path = app._signed_proxy_path(
            "https://cdn.example/media/master.m3u8",
            "https://provider.example",
            expires=2_000,
        )

        with app.app.test_request_context(path):
            self.assertEqual(
                app._verified_proxy_request("/proxy/m3u8", now=1_999),
                (
                    "https://cdn.example/media/master.m3u8",
                    "https://provider.example",
                ),
            )
            self.assertIsNone(
                app._verified_proxy_request("/proxy/m3u8", now=2_001)
            )

        tampered = path.replace("master.m3u8", "private.m3u8")
        with app.app.test_request_context(tampered):
            self.assertIsNone(
                app._verified_proxy_request("/proxy/m3u8", now=1_999)
            )

        with app.app.test_request_context(path):
            self.assertIsNone(
                app._verified_proxy_request("/proxy/ts", now=1_999)
            )

    def test_proxy_signing_key_is_required(self):
        with patch.dict(os.environ, {"MEDIA_PROXY_SIGNING_KEY": ""}):
            with self.assertRaises(RuntimeError):
                app._signed_proxy_path(
                    "https://cdn.example/media/master.m3u8",
                    "https://provider.example",
                )

    def test_signed_targets_reject_local_and_credentialed_urls(self):
        self.assertFalse(
            app._is_safe_signed_target("https://127.0.0.1/metadata")
        )
        self.assertFalse(
            app._is_safe_signed_target("https://user:secret@example.com/video")
        )
        self.assertFalse(
            app._is_safe_signed_target("https://example.com:8443/video")
        )

    def test_stream_response_derives_provider_from_embed_url(self):
        stream = SimpleNamespace(
            server="Vidstream-2",
            url="https://megaplay.buzz/stream/s-2/735790/sub",
            quality="HD",
        )
        resolved = {
            "source": "https://cdn.mewstream.buzz/anime/title/master.m3u8",
            "tracks": [{
                "file": "https://subs.lostproject.club/title/English.vtt",
                "label": "English",
            }],
        }

        with patch.object(app.animixplay, "get_all_streams", return_value=[stream]), \
                patch.object(app.animixplay, "resolve_source_full", return_value=resolved):
            response = app.app.test_client().get("/api/amp/stream/8945/3")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()[0]
        source_query = parse_qs(urlparse(payload["source"]).query)
        track_query = parse_qs(urlparse(payload["tracks"][0]["file"]).query)
        self.assertEqual(source_query["provider"], ["https://megaplay.buzz"])
        self.assertEqual(track_query["provider"], ["https://megaplay.buzz"])

    def test_new_public_subtitle_hosts_do_not_need_an_allowlist(self):
        source = "https://example.com/subtitles/English.vtt"

        tracks = app._proxied_subtitle_tracks(
            [{"file": source, "label": "English", "kind": "captions"}],
            "https://vidtube.site",
        )

        parsed = urlparse(tracks[0]["file"])
        self.assertEqual(parsed.path, "/proxy/subtitle")
        self.assertEqual(parse_qs(parsed.query)["url"], [source])


if __name__ == "__main__":
    unittest.main()
