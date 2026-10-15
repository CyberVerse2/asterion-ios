## Learned User Preferences

- Prefer native Apple navigation (iOS 26 / Liquid Glass) over custom chrome; hide the navigation bar on Reader, Novel Details, and Chapters so those pages blend into content.
- Asterion has no brand: older design artifacts (the crimson star logo, Cormorant/cream styling, `docs/product/app-store/code.jsx`, docs/design QA notes) are stale and are not a visual reference.
- Both apps share one design language, "a dark room where the content is the light": always-dark canvas (#0E0F13), monochrome UI, colour only from artwork (artwork glow behind heroes and detail pages), SF Pro Expanded for page/hero/section titles, SF Mono for numbers, white primary capsule plus smoked secondary buttons, glowing white "light line" progress, red only for live football, green/amber only for state. Use the shared tokens and components in each app's Theme.swift and chrome components rather than one-off styling.
- The reader keeps its own page themes (System follows the device appearance, Parchment, Night); Cormorant Garamond survives only as the reader's "Literary" typeface option.
- Use Clerk for sign-in and Drizzle + PostgreSQL for user data; do not introduce Prisma.
- Execute (build, clean rebuild, implement, and push when asked) instead of only advising; when asked to push, commit uncommitted work first. iOS iteration is typically SweetPad logs plus screenshots.
- Offline downloads should be per-chapter files in an organized Asterion folder, not a single dump; Continue Reading should jump to the last read line and chapter.
- Library must show only titles the user added; Profile "completed" means the user finished the novel, not the catalog publication status.
- Deploy Railway services with Railpacks, not Nixpacks.
- Sign macOS builds so Clerk Keychain access stays trusted across rebuilds; launch the Applications-installed app or DMG instead of a freshly re-signed `build_and_run` copy when the user just wants to open the app.
- Keep Reader wide on iPad; iPad is a supported destination.

## Learned Workspace Facts

- macOS (`apps/macos`, SwiftPM, macOS 26+) is the full novels, anime, movies, TV, and football hub; iOS (`apps/ios`) is a novels-only reader with widget, shortcuts, and Live Activities.
- Shared user API is Fastify + Drizzle in `services/core-api` (default `http://localhost:3001`); Apple clients ship compiled service origins and fall back to `https://asterion-api.cyberverse.cloud/`.
- Catalog and playback scrapers live in `services/anime`, `services/movies`, and `services/football` (Flask); public hosts are `asterion-scraper`, `asterion-movies`, and `asterion-football` on `cyberverse.cloud`. Anime catalog and `/api/health` depend on Redis (`REDIS_URL`).
- Backend services (api, anime, movies, football, plus Postgres and Redis) deploy on the Openship project "Asterion" from `main`, with auto-deploy on push. Each service builds from `openship/<service>/Dockerfile`, and Openship sets each service's start command itself, so gunicorn flags must change in the Openship service config as well as the Dockerfile; `services/<service>/Dockerfile` is not used in production. All four hosts sit behind Cloudflare, which replaces origin 502/504 bodies and headers.
- iOS device install uses SweetPad or `tooling/ios/build-install-launch-iphone.sh` / `build-install-launch-ipad.sh`; macOS uses `apps/macos/script/build_and_run.sh`.
- Chapter bodies can be fetched individually (`/chapters/{id}`); chapter lists are paginated.
- Clerk Native API, associated domains, and a stable code-signing identity are required for auth.
- macOS desktop releases are GitHub releases that attach `Asterion.dmg` from `apps/macos/dist/`.
