# Asterion for macOS

A native macOS 15+ port of the Asterion reader. It is a standalone SwiftPM app and does not compile the iOS target, widgets, Live Activities, or UIKit code.

## Desktop experience

- Native three-column navigation for Discover, Rankings, Library, and Account
- Searchable catalog backed by the production Asterion API
- Selection-driven novel details with chapters and synced library state
- Separate reader windows with chapter navigation, selectable text, text sizing, and plain-text export
- Clerk authentication and cross-device library/progress sync
- macOS Settings and keyboard navigation (`⌘1` through `⌘4`)

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

Set `ASTERION_VERSION`, `ASTERION_BUILD_NUMBER`, and `ASTERION_CODE_SIGN_IDENTITY` to override the default `0.1.0`, build `1`, and selected signing identity.

An Apple Development identity produces a local-development DMG. Public distribution requires a Developer ID Application identity, a sealed app bundle with hardened runtime, and Apple notarization.
