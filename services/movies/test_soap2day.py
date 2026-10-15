import base64
import hashlib
import json
import unittest
from unittest.mock import patch

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

import soap2day


BUILD = "spv3-build-1787821613-50e5fc97c9dce367"
DATA_PATH = "/data/movie/27205"
TOKEN = "djN8L2RhdGEvbW92aWUvMjcyMDV8.c77e54cd"


def _obfuscate(text):
    standard = base64.b64encode(text.encode()).decode().rstrip("=")
    return standard.translate(str.maketrans(
        soap2day._STANDARD_ALPHABET, soap2day._OBFUSCATOR_ALPHABET,
    ))


def _encrypt_backups(backups, build=BUILD):
    key = hashlib.sha256(f"spv3-data-response|{build}|{DATA_PATH}|{TOKEN}".encode()).digest()
    nonce = b"\x01" * 12
    blob = nonce + AESGCM(key).encrypt(nonce, json.dumps(backups).encode(), None)
    return base64.urlsafe_b64encode(blob).decode().rstrip("=")


class FakeResponse:
    def __init__(self, text):
        self.text = text

    def raise_for_status(self):
        pass

    def json(self):
        return json.loads(self.text)


class ParseCardsTests(unittest.TestCase):
    def test_reads_current_card_title_year_and_metadata(self):
        html = """
        <div class="ml-item ml-item-post" data-movie-id="568145">
          <a class="ml-mask jt" href="https://ww25.soap2day.day/obsession-soap2day/">
            <img alt="Obsession" class="lazy thumb mli-thumb"
                 data-original="https://images.example/obsession.jpg">
            <span class="mli-info"><span class="h2">Obsession</span></span>
          </a>
          <span class="mli-quality">HD</span>
          <div class="mli-add">
            <span class="imdb">8.0</span>
            <span class="runtime">1h 48min</span>
          </div>
          <div id="hidden_tip">
            <div class="qtip-title">Obsession</div>
            <a href="https://ww25.soap2day.day/release-year/2026/">2026</a>
          </div>
        </div>
        """

        result = soap2day._parse_cards(html)

        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].title, "Obsession")
        self.assertEqual(result[0].slug, "obsession-soap2day")
        self.assertEqual(result[0].year, "2026")
        self.assertEqual(result[0].imdb_rating, "8.0")
        self.assertEqual(result[0].runtime, "1h 48min")
        self.assertEqual(result[0].quality, "HD")
        self.assertEqual(result[0].type, "movie")

    def test_uses_tip_title_when_visible_title_is_missing(self):
        html = """
        <div class="ml-item" data-movie-id="42">
          <a class="ml-mask" href="https://ww25.soap2day.day/series/example-show/">
            <img class="mli-thumb" src="https://images.example/example.jpg">
          </a>
          <div id="hidden_tip"><div class="qtip-title">Example Show</div></div>
        </div>
        """

        result = soap2day._parse_cards(html)

        self.assertEqual(result[0].title, "Example Show")
        self.assertEqual(result[0].slug, "series/example-show")
        self.assertEqual(result[0].type, "tv")

    def test_uses_image_alt_as_final_source_title(self):
        html = """
        <div class="ml-item" data-movie-id="7">
          <a class="ml-mask" href="https://ww25.soap2day.day/example-movie/">
            <img alt="Example Movie" class="mli-thumb" src="poster.jpg">
          </a>
        </div>
        """

        result = soap2day._parse_cards(html)

        self.assertEqual(result[0].title, "Example Movie")
        self.assertIsNone(result[0].year)

    def test_reads_unique_genres_from_navigation(self):
        html = """
        <nav>
          <a href="https://ww25.soap2day.day/genre/action-3scq8/">Action</a>
          <a href="https://ww25.soap2day.day/genre/drama-d89qv/">Drama</a>
          <a href="https://ww25.soap2day.day/genre/action-3scq8/">Action</a>
        </nav>
        """
        original_get = soap2day._get
        soap2day._get = lambda _: html
        try:
            genres = soap2day.genres()
        finally:
            soap2day._get = original_get

        self.assertEqual(
            [(genre.slug, genre.title) for genre in genres],
            [("action-3scq8", "Action"), ("drama-d89qv", "Drama")],
        )

    def test_reads_seasons_and_episode_paths(self):
        html = """
        <div class="tvseason">
          <a class="les-title"><strong>Season 2</strong></a>
          <div class="les-content">
            <a href="https://ww25.soap2day.day/episode/example-season-2-episode-1/">Episode 1 - HD</a>
            <a href="https://ww25.soap2day.day/episode/example-season-2-episode-2/">Episode 2 - HD</a>
          </div>
        </div>
        <div class="tvseason">
          <a class="les-title"><strong>Season 1</strong></a>
          <div class="les-content">
            <a href="https://ww25.soap2day.day/episode/example-season-1-episode-1/">Episode 1 - HD</a>
          </div>
        </div>
        """
        original_get = soap2day._get
        soap2day._get = lambda _: html
        try:
            episodes = soap2day.series_episodes("series/example")
        finally:
            soap2day._get = original_get

        self.assertEqual([(episode.season, episode.number) for episode in episodes], [(2, 1), (2, 2), (1, 1)])
        self.assertEqual(episodes[0].id, "episode/example-season-2-episode-1")
        self.assertEqual(episodes[0].title, "Episode 1")


class MirrorRotationTests(unittest.TestCase):
    def tearDown(self):
        soap2day._current_domain = soap2day.DOMAINS[0]["url"]

    def test_rewrites_au_host_to_the_active_mirror(self):
        soap2day._current_domain = "https://ww25.soap2day.day"
        self.assertEqual(
            soap2day._use_mirror("https://au-soap2day.day/series/"),
            "https://ww25.soap2day.day/series/",
        )
        self.assertEqual(
            soap2day._use_mirror("https://ww25.soap2day.day/movies-qfva3/"),
            "https://ww25.soap2day.day/movies-qfva3/",
        )

    def test_detects_cloudflare_security_check_pages(self):
        self.assertTrue(soap2day._looks_blocked(
            "<title>Soap2Day — Security Check</title>"
            "<script src='/cdn-cgi/challenge-platform/h/g/orchestrate'></script>"
        ))
        self.assertFalse(soap2day._looks_blocked("<div class='ml-item'>Mayday</div>"))

    def test_get_rotates_off_a_tls_failure(self):
        calls = []

        def fake_plain(url, timeout=12):
            calls.append(url)
            if "ww25.soap2day.day" in url:
                raise soap2day.requests.exceptions.SSLError("handshake failure")
            return f"ok:{url}"

        original_plain = soap2day._plain_get
        soap2day._plain_get = fake_plain
        soap2day._current_domain = "https://ww25.soap2day.day"
        try:
            html = soap2day._get("https://ww25.soap2day.day/movies-qfva3/")
        finally:
            soap2day._plain_get = original_plain
            soap2day._current_domain = soap2day.DOMAINS[0]["url"]

        self.assertEqual(html, "ok:https://au-soap2day.day/movies-qfva3/")
        self.assertTrue(any("ww25.soap2day.day" in url for url in calls))
        self.assertTrue(any("au-soap2day.day" in url for url in calls))


class XpassResolverTests(unittest.TestCase):
    def setUp(self):
        soap2day._xpass_build_cache.update(value=None, expires=0.0)
        self.addCleanup(soap2day._xpass_build_cache.update, value=None, expires=0.0)

    def test_decodes_the_obfuscator_string_table(self):
        script = f"function a(){{const t=['{_obfuscate("/static/AbcXyz.js?t=1")}','{_obfuscate(BUILD)}'];}}"

        self.assertEqual(
            soap2day._decode_obfuscated_strings(script),
            ["/static/AbcXyz.js?t=1", BUILD],
        )

    def test_decrypts_the_server_list(self):
        backups = [{"name": "TIK 1", "url": "/mdata/a/1/playlist.json"}]

        self.assertEqual(
            soap2day._decrypt_xpass_payload(_encrypt_backups(backups), BUILD, DATA_PATH, TOKEN),
            backups,
        )

    def test_resolves_sources_through_the_encrypted_server_list(self):
        backups = [
            {"name": "TIK 1", "url": "/mdata/a/1/playlist.json"},
            {"name": "TAP 1", "url": "/mdata/b/0/playlist.json"},
            {"name": "VRK 1", "url": "/vrk/movie/27205/playlist.json"},
        ]
        pages = {
            "/e/movie/tt1375666": (
                '<script src="/static/mainmini.js?v=1"></script>'
                f'<script>var dataUrl="{DATA_PATH}?autostart=false&token={TOKEN}";</script>'
                "<script>var backups=[]</script>"
            ),
            "/static/mainmini.js": f"var s=['{_obfuscate('/static/AbcXyz.js?t=1')}'];",
            "/static/AbcXyz.js": f"var s=['{_obfuscate(BUILD)}'];",
            DATA_PATH: _encrypt_backups(backups),
            "/mdata/a/1/playlist.json": json.dumps({"playlist": [{"sources": [
                {"file": "https://tik.example/master.m3u8", "label": "TIK 2"},
            ]}]}),
            "/mdata/b/0/playlist.json": json.dumps({"playlist": [{"sources": [
                {"file": "/video/error", "label": "TAP 1"},
            ]}]}),
            "/vrk/movie/27205/playlist.json": json.dumps({"playlist": [{"sources": [
                {"file": "https://proxy.example/m3u8-proxy?url=x", "label": "VRK 1"},
            ]}]}),
        }

        def fake_get(url, headers=None, timeout=None):
            return FakeResponse(pages[soap2day.urlparse(url).path])

        with patch.object(soap2day._session, "get", side_effect=fake_get):
            sources = soap2day.get_hls_sources("tt1375666")

        self.assertEqual(
            [(s.label, s.embed_url, s.is_hls) for s in sources],
            [
                ("TIK 1: TIK 2", "https://tik.example/master.m3u8", True),
                ("VRK 1: VRK 1", "https://proxy.example/m3u8-proxy?url=x", True),
            ],
        )
        self.assertEqual(soap2day._xpass_build_cache["value"], BUILD)

    def test_rediscovers_the_build_when_the_cached_one_is_stale(self):
        soap2day._xpass_build_cache.update(value="spv3-build-1-0", expires=float("inf"))
        backups = [{"name": "TIK 1", "url": "/mdata/a/1/playlist.json"}]
        embed_html = f'<script src="/static/mainmini.js"></script><script>var dataUrl="{DATA_PATH}?token={TOKEN}";</script>'

        with patch.object(soap2day, "_xpass_get", return_value=FakeResponse(_encrypt_backups(backups))), \
                patch.object(soap2day, "_discover_xpass_build", return_value=BUILD) as discover:
            self.assertEqual(soap2day._xpass_backups(embed_html, "https://play.xpass.top/e/movie/tt1"), backups)

        discover.assert_called_once()


if __name__ == "__main__":
    unittest.main()
