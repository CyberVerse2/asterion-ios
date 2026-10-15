import base64
import json
from io import BytesIO
from unittest.mock import patch
from urllib.error import HTTPError

import unittest

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

import animixplay


def _encrypt_sources(payload, key=animixplay.PLAYER_ENC_KEY, iv=animixplay.PLAYER_ENC_IV):
    padder = padding.PKCS7(128).padder()
    padded = padder.update(json.dumps(payload).encode()) + padder.finalize()
    encryptor = Cipher(
        algorithms.AES(animixplay._zero_padded(key, 32)),
        modes.CBC(animixplay._zero_padded(iv, 16)),
    ).encryptor()
    blob = encryptor.update(padded) + encryptor.finalize()
    return base64.urlsafe_b64encode(blob).decode().rstrip("=")


class ListingParsingTests(unittest.TestCase):
    def test_listing_content_excludes_sidebar_recommendations(self):
        html = """
        <main>
          <aside class="content">
            <section>
              <div class="piece">
                <a href="https://animixplay.cz/watch/naruto-eybxz/ep-220">
                  <img src="https://images.example/naruto.jpg">
                </a>
                <a data-jp="Naruto">Naruto<</a>
                <span class="type dot">TV<</span>
                <span class="total">220<</span>
              </div>
            </section>
          </aside>
          <aside class="sidebar">
            <a class="piece" href="https://animixplay.cz/watch/unrelated-show">
              <img src="https://images.example/unrelated.jpg">
              <div class="ani-name" data-jp="Unrelated Show">Unrelated Show<</div>
            </a>
          </aside>
        </main>
        """

        results = animixplay._parse_cards(animixplay._listing_content(html))

        self.assertEqual([result.slug for result in results], ["naruto-eybxz"])
        self.assertEqual(results[0].title, "Naruto")

    def test_missing_listing_content_surfaces_markup_change(self):
        with self.assertRaisesRegex(ValueError, "listing content was not found"):
            animixplay._listing_content("<main><p>No listing here</p></main>")


class ListingFetchTests(unittest.TestCase):
    @patch("animixplay.time.sleep")
    @patch("animixplay.urlopen")
    def test_get_retries_a_temporary_502(self, urlopen, sleep):
        html = b"<aside class=\"content\">ok</aside>"
        error = HTTPError(
            "https://animixplay.cz/latest-updated",
            502,
            "Bad Gateway",
            hdrs=None,
            fp=BytesIO(b"error code: 502"),
        )
        urlopen.side_effect = [error, error, _FakeHTTPResponse(html)]

        body = animixplay._get("https://animixplay.cz/latest-updated")

        self.assertEqual(body, '<aside class="content">ok</aside>')
        self.assertEqual(urlopen.call_count, 3)
        self.assertEqual(sleep.call_count, 2)


class _FakeHTTPResponse:
    def __init__(self, body):
        self._body = body

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def read(self):
        return self._body


class PlayerSourceTests(unittest.TestCase):
    PLAYER_URL = "https://megaplay.buzz/stream/s-2/835403/sub?s=tcdn"
    PLAYER_HTML = (
        '<div id="megaplay-player" data-id="177682"></div>'
        '<script src="https://megaplay.buzz/lib/app.main.js?v=2"></script>'
    )
    MASTER = "https://fetch.example/anime/abc/master.m3u8"

    def setUp(self):
        animixplay._player_keys.clear()
        self.addCleanup(animixplay._player_keys.clear)

    def test_decrypts_encrypted_megaplay_sources(self):
        api = {"enc": _encrypt_sources({"file": self.MASTER}), "tracks": [{"file": "a.vtt"}]}

        with patch.object(animixplay, "_get", return_value=self.PLAYER_HTML), \
                patch.object(animixplay, "_get_json", return_value=api) as get_json:
            resolved = animixplay.resolve_source_full(self.PLAYER_URL)

        self.assertEqual(resolved, {"source": self.MASTER, "tracks": [{"file": "a.vtt"}]})
        self.assertEqual(
            get_json.call_args.args[0],
            "https://megaplay.buzz/stream/getSourcesNew?id=177682&type=sub",
        )

    def test_keeps_reading_plain_sources(self):
        api = {"sources": {"file": self.MASTER}, "tracks": []}

        with patch.object(animixplay, "_get", return_value=self.PLAYER_HTML), \
                patch.object(animixplay, "_get_json", return_value=api):
            resolved = animixplay.resolve_source_full(self.PLAYER_URL)

        self.assertEqual(resolved["source"], self.MASTER)

    def test_rereads_the_key_from_the_player_script_after_a_rotation(self):
        api = {"enc": _encrypt_sources({"file": self.MASTER}, key="rotated-key", iv="rotated-iv")}
        script = 'const DOMAINS_ENC_KEY="rotated-key",DOMAINS_ENC_IV="rotated-iv";'

        with patch.object(animixplay, "_get", side_effect=[self.PLAYER_HTML, script]) as get, \
                patch.object(animixplay, "_get_json", return_value=api):
            resolved = animixplay.resolve_source_full(self.PLAYER_URL)

        self.assertEqual(resolved["source"], self.MASTER)
        self.assertEqual(get.call_args.args[0], "https://megaplay.buzz/lib/app.main.js?v=2")
        self.assertEqual(animixplay._player_keys["https://megaplay.buzz"], ("rotated-key", "rotated-iv"))


if __name__ == "__main__":
    unittest.main()
