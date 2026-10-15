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
cd apps/macos
./script/build_and_run.sh
```

The script builds the Swift package, stages `dist/Asterion.app` with its dependency resources, and launches it as a foreground macOS app. Use `--verify` to confirm that the launched process remains active.

Staging requires a valid Apple code-signing identity so Clerk's Keychain access remains trusted across rebuilds. The script selects an Apple Development identity for local builds and a Developer ID Application identity for release packaging, or the identity named by `ASTERION_CODE_SIGN_IDENTITY`.

Run tests with:

```sh
swift test
```

## Package a DMG

```sh
./script/build_and_run.sh --package
```

Packaging builds the release configuration, signs executable code with hardened runtime and secure timestamps, stages `dist/Asterion.app`, creates `dist/Asterion.dmg` with an Applications shortcut, and submits the disk image to Apple for notarization. It requires an Accepted result, staples and validates the ticket, checks Gatekeeper acceptance of the DMG and app, and writes `dist/Asterion.dmg.sha256` after stapling.

Before release packaging, install a Developer ID Application certificate with its private key, supply `ASTERION_CLERK_PUBLISHABLE_KEY=pk_live_...`, and store notarization credentials interactively in Keychain:

```sh
xcrun notarytool store-credentials AsterionNotary
ASTERION_NOTARY_PROFILE=AsterionNotary ./script/build_and_run.sh --package
```

The credentials command asks for your Apple Account, Team ID, and an app-specific password. Keep these credentials in Keychain; do not put them in the repository. The release script uploads the DMG to Apple and waits for a decision. Results are saved in `dist/notarization-result.plist`; no checksum is produced for a rejected submission.

To notarize a build for your own testing with the current Clerk development instance, use `ASTERION_NOTARY_PROFILE=AsterionNotary ./script/build_and_run.sh --package-notarized-development`. It keeps the debug configuration and development Clerk instance, while using Developer ID signing, hardened runtime, secure timestamps, and the same notarization checks. Use `--package` with a production key for public releases.

For development sharing while Clerk still uses a development instance, run:

```sh
./script/build_and_run.sh --package-development
```

This builds the debug configuration with the development Clerk key, signs the app and DMG with the installed Apple Development identity, and performs the same image validation. The stable development signature prevents repeated Keychain authorization prompts across rebuilds on this Mac. It does not submit for notarization. If you explicitly select a Developer ID Application identity with `ASTERION_CODE_SIGN_IDENTITY`, signing uses hardened runtime and secure timestamps, including for this development package.

Set `ASTERION_CLERK_PUBLISHABLE_KEY` to the production Clerk publishable key before packaging. Release exports reject development keys so they cannot be shipped accidentally.

Set `ASTERION_VERSION`, `ASTERION_BUILD_NUMBER`, and `ASTERION_CODE_SIGN_IDENTITY` to override the default `0.3.6`, build `12`, and selected signing identity.

An Apple Development identity produces a local-development DMG. Public distribution requires a Developer ID Application identity, a sealed app bundle with hardened runtime, and Apple notarization.
