## Learned User Preferences

- Prefer native Apple navigation (iOS 26 / Liquid Glass) over custom chrome; hide the navigation bar on Reader, Novel Details, and Chapters so those pages blend into content.
- Treat `docs/product/app-store/code.jsx` and user screenshots as the visual source of truth for iOS; implement missed pieces from that reference rather than inventing UI.
- Keep the app custom typeface on every page title and chrome; do not fall back to Roboto or the system font.
- Use Clerk for sign-in and Drizzle + PostgreSQL for user data; do not introduce Prisma.
- Execute (build, clean rebuild, implement, and push when asked) instead of only advising; iOS iteration is typically SweetPad logs plus screenshots.
- Offline downloads should be per-chapter files in an organized Asterion folder, not a single dump; Continue Reading should jump to the last read line and chapter.
- Library must show only titles the user added; Profile "completed" means the user finished the novel, not the catalog publication status.
- Deploy Railway services with Railpacks, not Nixpacks.
- Sign macOS builds so Clerk Keychain access stays trusted across rebuilds; avoid unsigned launches that re-prompt for the keychain.
- Keep Reader wide on iPad; iPad is a supported destination.

## Learned Workspace Facts

- macOS (`apps/macos`, SwiftPM, macOS 26+) is the full novels, anime, movies, TV, and football hub; iOS (`apps/ios`) is a novels-only reader with widget, shortcuts, and Live Activities.
- Shared user API is Fastify + Drizzle in `services/core-api` (default `http://localhost:3001`); Apple clients ship compiled service origins and fall back to `https://asterion-api.cyberverse.cloud/`.
- Catalog and playback scrapers live in `services/anime`, `services/movies`, and `services/football` (Flask); each exposes `/api/health`.
- iOS device install uses SweetPad or `tooling/ios/build-install-launch-iphone.sh` / `build-install-launch-ipad.sh`; macOS uses `apps/macos/script/build_and_run.sh`.
- Chapter bodies can be fetched individually (`/chapters/{id}`); chapter lists are paginated.
- Clerk Native API, associated domains, and a stable code-signing identity are required for auth.
