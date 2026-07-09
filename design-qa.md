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

final result: passed
