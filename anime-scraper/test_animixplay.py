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


if __name__ == "__main__":
    unittest.main()
