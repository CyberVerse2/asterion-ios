from io import BytesIO
from unittest.mock import patch
from urllib.error import HTTPError

import unittest

import animixplay


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


if __name__ == "__main__":
    unittest.main()
