# Asterion for macOS

A native macOS 26+ port of Asterion for reading novels and watching anime. It is a standalone SwiftPM app and does not compile the iOS target, widgets, Live Activities, or UIKit code.

## Desktop experience

- A top-level Novels/Anime switch with independent navigation for each catalog
- Native three-column navigation for novel discovery, rankings, library, and account
- Adaptive macOS appearance with native Liquid Glass navigation, toolbars, and controls
- Searchable novel and anime catalogs backed by their production Asterion services
- Selection-driven novel details with chapters and synced library state
- Anime Discover with a playable feature carousel, paged Updated, Popular, New Releases, and Genre shelves from Asterion's Animixplay-backed API
- Separate, focus-first Anime Player windows with a closed-by-default episode list, previous/next navigation, and direct or embedded playback
- Separate reader windows powered by SwiftUI `WebView`/`WebPage`, with facing pages, chapter navigation, selectable text, themes, text sizing, and plain-text export
- Clerk authentication and cross-device library/progress sync
- macOS Settings and keyboard navigation (`⌘⇧1`/`⌘⇧2` for content modes and `⌘1` onward for the active sidebar)

## Build and run

```sh
cd AsterionMac
./script/build_and_run.sh
```

The script builds the Swift package, stages `dist/Asterion.app` with its dependency resources, and launches it as a foreground macOS app. Use `--verify` to confirm that the launched process remains active.

Staging requires a valid Apple code-signing identity so Clerk's Keychain access remains trusted across rebuilds. The script uses the first installed code-signing identity, or the identity named by `ASTERION_CODE_SIGN_IDENTITY`.

Run tests with:

```sh
swift test
```

## Package a DMG

```sh
./script/build_and_run.sh --package
```

Packaging builds the release configuration, stages `dist/Asterion.app`, creates `dist/Asterion.dmg` with an Applications shortcut, signs the disk image, mounts it read-only, validates its contents and executable identity, and writes `dist/Asterion.dmg.sha256`.

For development sharing while Clerk still uses a development instance, run:

```sh
./script/build_and_run.sh --package-development
```

This builds the debug configuration with the development Clerk key, signs the app and DMG with the installed Apple Development identity, and performs the same image validation. The stable development signature prevents repeated Keychain authorization prompts across rebuilds on this Mac. It does not add hardened runtime or notarization.

Set `ASTERION_CLERK_PUBLISHABLE_KEY` to the production Clerk publishable key before packaging. Release exports reject development keys so they cannot be shipped accidentally.

Set `ASTERION_VERSION`, `ASTERION_BUILD_NUMBER`, and `ASTERION_CODE_SIGN_IDENTITY` to override the default `0.1.0`, build `1`, and selected signing identity.

An Apple Development identity produces a local-development DMG. Public distribution requires a Developer ID Application identity, a sealed app bundle with hardened runtime, and Apple notarization.
