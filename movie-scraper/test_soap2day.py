import unittest

import soap2day


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


if __name__ == "__main__":
    unittest.main()
