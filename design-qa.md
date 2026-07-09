# Floating Shell Design QA

**Source visual truth**

- `/var/folders/61/_gpbs9bd52vgc9hwvjtng_pm0000gn/T/codex-clipboard-df52cc90-feee-475f-9e75-b62ac262cb9a.png`
- The source establishes the real Rankings content and the inconsistent shell geometry to correct. The intended transformation is a detached, consistently curved toolbar, sidebar, catalog pane, and detail pane.

**Implementation evidence**

- `/var/folders/61/_gpbs9bd52vgc9hwvjtng_pm0000gn/T/com.openai.sky.CUAService/Asterion Screenshot 2026-07-09 at 11.51.59 PM.jpeg`
- Combined comparison inspected at `/tmp/asterion-floating-shell-comparison.jpg`.
- Viewport: 1223 × 768 points after normalizing the source to the implementation capture.
- State: Rankings selected, expanded sidebar, Shadow Slave detail visible.

**Full-view comparison evidence**

- The source uses a flush rectangular toolbar, a partially rounded sidebar, and sharp shared boundaries between catalog and detail.
- The implementation preserves the same information architecture, content density, imagery, typography, and Crimson interaction color while placing all three workspace surfaces on a soft cool-gray canvas.
- Twelve-point outer and inter-panel gutters remain visible on every edge. Workspace panes use a consistent 18-point continuous radius, and catalog controls are contained by the middle panel header.
- Expanded and compact sidebar states were exercised in the running app. Neither state overlaps the toolbar, catalog, or detail pane, and the graphite gap remains stable.

**Focused region comparison evidence**

- A separate crop was unnecessary because the normalized full-view comparison renders every outer corner and inter-panel boundary clearly. The requested change concerns shell geometry rather than small asset or typography fidelity.

**Required fidelity surfaces**

- Fonts and typography: Literata hierarchy and SF Pro utility text are unchanged; no new wrapping or truncation was introduced.
- Spacing and layout rhythm: panel gutters, radii, and outer insets are consistent; catalog and detail measures remain bounded in fullscreen.
- Colors and visual tokens: the existing white, cool-gray, and Crimson palette is preserved; a slightly deeper cool gray provides structural separation without introducing a dark-shell theme.
- Image quality and asset fidelity: supplied cover art, logo mark, and avatar assets remain unchanged, correctly scaled, and clipped by their existing components.
- Copy and content: navigation, search, metadata, synopsis, chapters, and actions are unchanged. Reading progress remains runtime data and may differ between captures.

**Findings**

- No actionable P0, P1, or P2 issues remain.

**Open Questions**

- None.

**Implementation Checklist**

- [x] Move section, refresh, and search controls into the middle panel header.
- [x] Give sidebar, catalog, and detail their own consistent rounded shells.
- [x] Make each shell own a full-height surface independent of child safe-area insets.
- [x] Extend the split view into the hidden titlebar area and reserve sidebar content clearance for window controls.
- [x] Expose cool-gray gutters between every surface and around the window perimeter.
- [x] Adapt split visibility and sidebar width for narrow windows so no secondary pane is left as a sliver.
- [x] Verify expanded and compact sidebar states in the running app.
- [x] Preserve navigation, refresh, search, selection, scrolling, and account actions.

**Comparison history**

- Initial source finding: mixed rounded and sharp edges made the sidebar and panes feel attached inconsistently.
- First implementation finding: a window-wide toolbar and black structural canvas created a second, overly dark visual language.
- Fix: moved section, refresh, and search controls into the middle panel; replaced the black canvas with the existing cool-gray family; removed the native top bar; expanded the workspace into the released top safe area.
- Post-fix evidence: the final live capture and compact/expanded checks show complete surface separation, a cohesive light palette, full use of the window, and no overlap or clipped corners.

**Follow-up Polish**

- No blocking follow-up polish identified.

final result: passed
