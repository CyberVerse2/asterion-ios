# Asterion macOS Editorial Redesign QA

- Source visual truth: `docs/design/selected-option-2.png`
- Implementation screenshot: `docs/design/implementation-final-discover.png`
- Combined comparison: `docs/design/design-qa-comparison.png`
- Reader screenshot: `docs/design/reader-final.png`
- Viewport: 1411 × 964 points (2822 × 1928 Retina capture)
- State: Discover, guest session, first Featured novel selected

## Full-view comparison evidence

The implementation matches the source’s three-region composition: restrained sidebar, cover-led editorial catalog, and inspector-width novel detail. Both use warm paper surfaces, dark serif editorial type, oxblood selection and primary action, real cover imagery, lightweight metadata, a readable synopsis, and a five-row chapter preview.

The source mock shows an authenticated profile and a Continue Reading shelf. The captured implementation is intentionally a guest session, so those server-backed states are not shown. The production view renders Continue Reading only from authenticated progress records; no mock or alternate data path was introduced for QA.

## Focused-region comparison evidence

A separate crop was not needed because the original-resolution combined comparison keeps sidebar icons, cover crops, button treatment, synopsis typography, dividers, and chapter-row alignment readable. The reader was inspected separately because it is a distinct window and state.

## Required fidelity surfaces

- Fonts and typography: Literary content uses the system serif family with native sans-serif controls. Hierarchy, wrapping, optical weights, and reader measure match the concept’s editorial intent.
- Spacing and layout rhythm: Sidebar and detail proportions match after constraining the detail column. Shelves maintain a four-cover row at the captured width and reduce responsively without orphan rows or horizontal scrollbars.
- Colors and visual tokens: Paper, surface, ink, muted metadata, border, progress, soft selection, and oxblood action tokens consistently map to the source.
- Image quality and asset fidelity: All visible books use live catalog cover art with correct portrait crops, subtle borders, and restrained shadows. No placeholder art or code-drawn image substitutes are visible.
- Copy and content: Section labels and supporting copy are concise and product-native. Dynamic title, author, synopsis, progress, and chapter content come from the live API.
- Icons and affordances: SF Symbols provide one consistent native icon family. Primary, secondary, selected, disabled, search, and navigation states are visually distinct.
- Accessibility and behavior: Sidebar items, covers, search, chapter rows, reader navigation, text sizing, and export are keyboard/accessibility actions. Text remains selectable in detail and reader surfaces.

## Comparison history

### Pass 1 — blocked

- [P1] The detail pane occupied too much width, compressing the cover shelves and changing the source’s primary hierarchy.
- [P2] Horizontal shelf scrollbars and wrapped orphan tiles made the catalog feel more utilitarian than editorial.
- [P0] Reader opened cached chapter metadata without full chapter text.

Fixes:

- Constrained the detail column to a 400–520 point inspector-like width.
- Replaced scrolling grids with responsive three/four-cover rows.
- Changed the chapter cache to satisfy reader requests only when full content is present.

### Pass 2 — passed

- Post-fix evidence: `docs/design/implementation-final-discover.png`
- The catalog regained the four-cover rhythm, the detail pane matches the selected concept’s proportion, shelf scrollbars are gone, and the reader displays full live chapter text.

## Interaction checks

- Discover and Rankings sidebar navigation
- Search for “Shadow Slave” and single-result state
- Featured selection updates the detail pane
- Start Reading opens an independent reader window
- Reader loads complete chapter content
- Previous/next chapter, text-size, and export controls are exposed
- Signed bundle launches and presents a visible main window

## Follow-up polish

- [P3] Capture the authenticated Continue Reading and profile-footer states when a test account is available.

## Anime Discover and Detail QA — July 18, 2026

- Source visuals: the supplied Anime Discover, feature-card, and detail-header screenshots in this task
- Implementation screenshot: `docs/design/anime-discover-final.jpeg`
- Viewport: 1042 × 768 points
- State: Anime → Discover, live catalog data, selected title with available episodes

### Full-view comparison evidence

Anime Discover now follows the supplied storefront hierarchy: a featured watch surface comes first, followed by a dense Recently Updated poster shelf with episode and SUB/DUB badges. The native app keeps Asterion’s existing sidebar, serif typography, oxblood accent, and three-column proportions instead of importing the source website’s unrelated navigation and announcement banner.

The service supplies portrait posters rather than landscape backdrops. The feature card therefore treats the live poster as a sharp inset over an atmospheric crop of the same real artwork. This preserves image quality and produces a deliberate composition without stretching the poster or adding an unrelated asset source.

### Focused-region comparison evidence

- Feature card: the former oversized color footer, truncated secondary line, and accidental blurred side fill were replaced with a compact editorial card. The title, episode/type badges, carousel controls, poster, and Watch action all remain readable at the 527-point catalog-column width.
- Detail header: the Anime title scale changed from 28 to 22 points, the poster from 156 × 224 to 138 × 198 points, and the horizontal gap from 24 to 20 points. Long titles now remain visually connected to season, studio, status, and episode metadata.
- Catalog density: covers retain the same size and shelf rhythm as Novels while Discover adds the overlay badges from the supplied Anime reference.

### Data and interaction checks

- The live `/api/amp/latest`, `/api/amp/popular`, `/api/amp/releases`, and `/api/amp/genre/<genre>` endpoints support paged shelves.
- Discover, Popular, New Releases, Genres, and search request additional pages when the final visible card appears.
- Page results remove duplicate IDs; a failed page shows an explicit retry action.
- Search uses `/api/amp/search`; a live Naruto query returns the full franchise result set instead of only current-season titles.
- Carousel dots change the featured title, Watch now opens the title and starts its latest episode, and detail episode rows start playback.
- Release season is shown from the API’s `season` field. No unsupported franchise-season relationship is inferred.

### Comparison history

#### Pass 1 — needs revision

- [P1] Discover stopped at the API convenience endpoint’s first batch.
- [P1] The feature card forced portrait art into a landscape-and-footer composition and truncated long titles.
- [P1] The detail title inherited a Novel scale that was too large for long Anime names.

#### Pass 2 — passed

- Catalog browsing now continues through paged filter results.
- The feature card uses a compact live-art composition with functional carousel and playback controls.
- The detail header remains readable at the minimum supported window width.
- No P0, P1, or P2 visual issues remain in the final comparison.

### Anime Player window

- Player screenshot: `docs/design/anime-player-final.jpeg`
- Long-episode screenshot: `docs/design/anime-player-long-episodes-final.jpeg`
- Long-episode source comparison: `docs/design/anime-player-long-episodes-comparison.png`
- Viewport: 1080 × 700 points
- State: live direct stream, Naruto: Shippuden episode 86 selected from 500 episodes

Watching now opens a separate task window, matching the Novel reader’s behavior. The catalog remains available behind the player instead of expanding and displacing the detail page.

The video is the dominant surface. A low-contrast 44-point control strip exposes only the episode position, episode-list toggle, previous/next actions, and source menu. The episode sidebar is closed by default. Short shows use the original compact 250-point list; shows with more than 40 episodes open a 410-point number grid based on the supplied reference.

The focused source comparison confirms the long-show navigator preserves the reference’s strongest behaviors: 100-episode ranges, backward/forward range controls, dense number tiles, exact-number lookup, and a clear current-episode state. The implementation keeps the grid inside a restrained player drawer so it does not compete with the video, uses Asterion’s oxblood selection instead of importing the reference site’s blue, and scrolls the chosen episode into view.

Interaction checks:

- The requested episode begins automatically from Discover, the detail Watch action, or an episode row.
- The complete available episode list opens from the top-left toggle and remains selectable in the player.
- Long shows divide episodes into 100-item ranges; the menu and arrow controls move between those ranges.
- Entering an exact episode number changes to the correct range, starts that episode, and keeps its selected tile visible.
- Previous is enabled when an earlier episode exists; Next disables at the final episode.
- Direct playback, alternate source selection, native video controls, and fullscreen remain available.
- The episode sidebar starts hidden and can be reopened with one button.
- Window-route state survives SwiftUI scene encoding; the route round-trip is covered by the macOS test suite.
- A 500-episode live show and the 001–100 → episode 86 search path were checked in the signed app. The range model is covered by the macOS test suite.

final result: passed
