# Asterion for iPhone and iPad

Asterion requires iOS or iPadOS 26 or newer. The app includes novels, anime, movies and TV, football, synced libraries and activity, chapter downloads, widgets, shortcuts, and reading Live Activities.

## Content alerts, offline reading, and reading activity

Account has separate switches for new chapters in saved novels and new episodes in saved anime. Allow notification permission when prompted. The app establishes a silent baseline for each saved title, then sends one notification per title when the available count increases. Tapping an alert opens that title. Checks run on app activation and through Background App Refresh; iOS chooses background timing, so these are periodic local alerts rather than immediate server push notifications. Keep Background App Refresh enabled for Asterion.

Downloads opens a novel's local chapter list and the normal reader without fetching chapter bodies from the network. Continue reading restores the last downloaded chapter and line. Each chapter stays in its own text file; a small manifest preserves novel and chapter identities. Existing downloads also work through cached metadata or stable offline identities. Synthetic offline IDs stay on the device.

Account shows unique chapters read toward the weekly goal, reading time today and this week, and the current daily streak. Weeks start on Monday. Chapter activity combines reading history with local activity; reading time begins tracking with this version, is stored per account on the device, and pauses when the reader is hidden or the app becomes inactive.

## Build configuration

Debug and Release builds use the existing personal Clerk development instance:

```sh
xcodebuild \
    -project Asterion.xcodeproj \
    -scheme Asterion \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    archive
```

The shared user API defaults to `https://asterion-api.cyberverse.cloud/`. Override `USER_API_BASE_URL` at build time only when targeting another compatible deployment.

This project is configured for personal installation, not App Store distribution.

## Paid development signing and Clerk

Add the paid Apple Developer account in Xcode Settings → Apple Accounts. The app and widget targets use team `V6Y7WXX6Z5`; select your paid team for both targets if it differs. The device helper preserves the project's full entitlements, including Associated Domains and the shared App Group.

From the repository root, install on a connected device with:

```sh
tooling/ios/build-install-launch-iphone.sh
tooling/ios/build-install-launch-ipad.sh
```

Set `ASTERION_DEVELOPMENT_TEAM` to override the project team for either script. Xcode may register the connected device and obtain profiles using the signed-in developer account.

In Clerk Dashboard → Native Applications, enable the Native API and register iOS bundle ID `cyberverse.Asterion` with the paid Apple Team ID. The app's Associated Domains entry is `webcredentials:$(CLERK_FRONTEND_API_DOMAIN)`, currently pointing to `poetic-gator-97.clerk.accounts.dev`. The corresponding `/.well-known/apple-app-site-association` response must include the app identifier under `webcredentials.apps`.

When switching Clerk instances, update both `CLERK_PUBLISHABLE_KEY` and `CLERK_FRONTEND_API_DOMAIN` together. Verify sign-in and session restoration on a physical device after obtaining the new profile.
