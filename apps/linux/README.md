# Asterion for Linux (AppImage)

Desktop JVM client. Phase 1 is a shell wired to the Android app's platform-free `core/` (same contracts, paragraph rule, API clients). Phase 2 adds the Compose Multiplatform window in `desktop/`; packaging already ships whatever `installDist` produces.

`core/` is shared by reference (`settings.gradle.kts` points `:core` at `../android/core`) — no code is duplicated.

## Run

```sh
../android/gradlew -Pasterion.version=0.1.0 :desktop:run
../android/gradlew -Pasterion.version=0.1.0 :desktop:run --args="--verify"
```

Needs JDK 21 (core's parity tests segment graphemes like Swift only on 21+).

## Tests

```sh
../android/gradlew -Pasterion.version=0.1.0 :core:test :desktop:test
```

## Package an AppImage

```sh
script/package.sh 0.1.0
```

Builds + tests, smoke-tests the installed launcher (`--verify`), stages `dist/AppDir`, and writes `dist/Asterion-0.1.0-x86_64.AppImage` + `.sha256` via `appimagetool` (fetched once to `~/.cache/asterion/`). Add `--publish` to also create the `linux-v0.1.0` GitHub release; push the tag yourself.

Needs `packaging/asterion.png` (512px) for a real icon — currently a warned-about placeholder.

## Next (phase 2)

1. Add `org.jetbrains.compose` plugin + `compose.desktop` UI in `desktop/`, reusing `core/` clients.
2. Replace Android-only pieces: Room → SQLDelight/Room-desktop, WorkManager → coroutines downloader (same `Asterion/...` layout), Media3 → VLCJ/MPV, Clerk → REST + browser OAuth with tokens in `~/.config/asterion/`.
3. Wire `apps/web` `/releases.json` + download page and in-app update check to the `linux-v*` releases.
