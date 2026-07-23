import unittest
from urllib.parse import parse_qs, urlparse

import app


class SubtitleProxyTests(unittest.TestCase):
    def test_kotocdn_subtitles_are_routed_through_the_secure_proxy(self):
        source = (
            "https://vidtub.kotocdn.site/media/subtitles/English.vtt"
        )

        tracks = app._proxied_subtitle_tracks(
            [{"file": source, "label": "English", "kind": "captions"}]
        )

        proxied_url = tracks[0]["file"]
        parsed = urlparse(proxied_url)
        self.assertEqual(parsed.path, "/proxy/subtitle")
        self.assertEqual(parse_qs(parsed.query)["url"], [source])

    def test_kotocdn_uses_the_vidtube_provider_context(self):
        headers = app._hls_request_headers(
            "https://vidtub.kotocdn.site/media/subtitles/English.vtt"
        )

        self.assertEqual(headers["Origin"], "https://vidtube.site")
        self.assertEqual(headers["Referer"], "https://vidtube.site/")

    def test_mewstream_uses_the_megaplay_provider_context(self):
        source = "https://cdn.mewstream.buzz/anime/title/master.m3u8"
        headers = app._hls_request_headers(source)

        self.assertTrue(app._is_allowed_video_url(source))
        self.assertEqual(headers["Origin"], "https://megaplay.buzz")
        self.assertEqual(headers["Referer"], "https://megaplay.buzz/")

    def test_megaplay_context_is_preserved_in_rewritten_segments(self):
        proxied_url = app._proxied_hls_path(
            "https://x5y0d.cloudbuzz.lol/anime/title/segment.jpg",
            "https://megaplay.buzz",
        )
        query = parse_qs(urlparse(proxied_url).query)

        self.assertEqual(query["provider"], ["https://megaplay.buzz"])
        headers = app._hls_request_headers(
            query["url"][0],
            query["provider"][0],
        )
        self.assertEqual(headers["Origin"], "https://megaplay.buzz")
        self.assertEqual(headers["Referer"], "https://megaplay.buzz/")

    def test_untrusted_provider_context_is_ignored(self):
        headers = app._hls_request_headers(
            "https://x5y0d.cloudbuzz.lol/anime/title/segment.jpg",
            "https://attacker.example",
        )

        self.assertEqual(headers["Origin"], "https://vidwish.live")

    def test_untrusted_subtitle_hosts_are_not_proxied(self):
        source = "https://example.com/subtitles/English.vtt"

        tracks = app._proxied_subtitle_tracks(
            [{"file": source, "label": "English", "kind": "captions"}]
        )

        self.assertEqual(tracks[0]["file"], source)


if __name__ == "__main__":
    unittest.main()
