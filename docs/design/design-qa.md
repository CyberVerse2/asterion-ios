# Design QA: Apple TV-style Asterion Home

- Source visual truth: `design-qa-assets/reference-apple-tv.png`
- Implementation screenshot: `design-qa-assets/implementation-home.jpeg`
- Combined comparison: `design-qa-assets/reference-vs-implementation.png`
- Comparison viewport: 1156 × 692 pixels per side
- State: dark appearance, Home selected, dashboard at the top

## Full-view comparison evidence

The reference was cropped from the left edge to the implementation aspect ratio, then both images were scaled to 1156 × 692 and placed side by side. The implementation matches the reference's major structure: one native sidebar, one calm content canvas, compact section headings, five portrait cards plus a partial sixth, vertically stacked horizontal shelves, and a visible vertical scroll position without horizontal scrollbar chrome.

## Focused-region comparison evidence

No additional crop was needed. At the normalized viewport, the sidebar rows, section headings, poster corners, poster metadata, shelf spacing, and edge-peeking card are all readable in the combined comparison.

## Fidelity review

- Fonts and typography: Sidebar and section headings use native system typography. Asterion retains its serif brand face inside Continue cards; this is an intentional product distinction.
- Spacing and layout rhythm: Sidebar proportion, 32-point shelf inset, 18-point card gap, 42-point section gap, and five-card density match the reference closely.
- Colors and visual tokens: The detail canvas uses a softer charcoal token while the sidebar remains system-rendered Liquid Glass.
- Image quality and asset fidelity: All media artwork comes from Asterion's real catalog. Images keep a 2:3 crop with no placeholder or generated replacement.
- Copy and content: Labels reflect Asterion's destinations and catalog rather than copying Apple TV product names.

## Interaction checks

- Native sidebar selection successfully moved from Home to Movies and back to Home.
- Home content and catalog data remained intact after navigation.
- Horizontal shelves are native SwiftUI scroll views with stable item identity and no persistent horizontal scrollbar chrome.
- The automation surface could not synthesize a horizontal trackpad gesture after indicators were set to `never`; physical trackpad momentum remains a manual verification gap.

## Comparison history

### Pass 1

- P1: Posters were roughly 25% too large, reducing visible density to four cards.
- P2: Horizontal scrollbars appeared under every shelf.
- P2: The content canvas was darker than the reference.

### Fixes

- Reduced poster cards to 168 × 252 points.
- Changed horizontal indicator visibility from `hidden` to `never`.
- Added a dedicated soft-charcoal media canvas token.
- Reduced section heading size and increased the shelf leading inset.

### Pass 2

The implementation shows five full posters plus an edge-peeking sixth, no horizontal scrollbar chrome, and a canvas/sidebar balance close to the supplied reference. No actionable P0, P1, or P2 visual differences remain. The landscape Continue cards are intentional because they carry playback progress and episode metadata.

## Follow-up polish

- P3: Confirm horizontal trackpad momentum on physical hardware.
- P3: The Computer Use capture overlays a purple remote-control indicator over the traffic-light area; accessibility inspection confirms the native close, minimize, and full-screen controls remain present.

final result: passed

---

# Design QA: Ambient Theater Detail Page

- Source visual truth: `/Users/thecyberverse/.codex/generated_images/019f7ea3-4252-7a21-af23-367ca1b1205f/exec-d77fa8c2-2f3b-4080-92c0-05203dbc0b1f.png`
- Implementation screenshot: `/private/tmp/asterion-detail-option2-final.png`
- Combined comparison: `/private/tmp/asterion-detail-option2-final-comparison.png`
- Viewport: 1137 × 752 pixels per side
- State: dark appearance, Home-selected detail route, Mushoku Tensei Season 3, four episodes

## Full-view comparison evidence

The selected design and implementation were normalized to the same viewport and placed side by side. The implementation keeps the chosen composition: native sidebar, poster-derived ambient hero, portrait key art, compact title and metadata block, one red primary action, neutral supporting actions, and a horizontal episode shelf.

## Focused-region comparison evidence

No separate crop was needed because the normalized full view keeps the hero controls and episode-card controls readable. The episode shelf starts on the first item, shows an edge-peeking final item, and has no visible horizontal scrollbar.

## Fidelity review

- Fonts and typography: The implementation uses macOS system typography throughout the detail page, preserving the selected design's hierarchy and avoiding the previous serif episode treatment.
- Spacing and layout rhythm: Poster, title, actions, and episode shelf form one compact reading path with no large dead area or full-width call-to-action bar.
- Colors and visual tokens: Red is reserved for Watch. Back, bookmark, download, episode counts, and episode states use neutral high-contrast foregrounds.
- Image quality and asset fidelity: The real catalog poster supplies the hero, ambient backdrop, and episode-card crops. No placeholder artwork is used.
- Copy and content: Existing Asterion metadata and watch-target behavior are preserved. Episode controls retain their downloaded, downloading, retry, and available states.

## Interaction checks

- Opened the title from Home and confirmed the detail route loaded.
- Confirmed Watch, Save, collection Download, each episode, and each episode download state remain exposed to accessibility.
- Confirmed the episode shelf resets to Episode 1 and hides scrollbar chrome.
- The app built, signed, launched, and remained running through the project run script.

## Comparison history

### Pass 1

- P2: The episode shelf restored at its trailing edge, leaving Episode 1 clipped.
- P2: Red on small secondary controls and counts had weak contrast on the charcoal/glass surfaces.
- P2: Per-episode download controls read as heavy rectangular buttons.

### Fixes

- Reset the shelf to its first episode after the content loads.
- Reserved red for the primary Watch action and moved secondary controls to neutral foregrounds.
- Replaced rectangular episode download buttons with compact circular state controls.

### Pass 2

The first episode is fully visible, scrollbar chrome is absent, secondary controls are legible, and the page retains the selected Ambient Theater hierarchy. No actionable P0, P1, or P2 differences remain.

## Follow-up polish

- P3: Real episode thumbnails can replace poster-derived crops if the anime source adds episode artwork later.

final result: passed
