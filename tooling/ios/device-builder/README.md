# Asterion Device

A small native macOS helper that lists a connected iPhone or iPad and runs one action: **build, install, and launch** `cyberverse.Asterion`.

This is not the entertainment app in `apps/macos`. Keep it here so product targets stay clean.

## Open / build / run

From this folder:

```sh
cd tooling/ios/device-builder
swift run AsterionDevice
```

Or open `Package.swift` in Xcode and run the `AsterionDevice` scheme.

Compile only:

```sh
swift build
```

Package a local DMG (release binary, Apple Development signature, no sandbox):

```sh
./script/package_dmg.sh
```

That writes `dist/Asterion Device.dmg`. Drag the app to Applications, then open it and hit Build against a connected iPhone or iPad.

macOS 26+ and a local Xcode install are required. The helper is unsigned SwiftPM; it shells out to `xcodebuild` and `devicectl`, so it must not be App Sandboxed.

## What the Build button runs

Repo root is auto-detected by walking up from the current directory / app location looking for `apps/ios/Asterion.xcodeproj`, or via `git rev-parse --show-toplevel`. Override it in the window (defaults to `/Users/thecyberverse/Code/Asterion`). Last selected device is stored in UserDefaults.

Each run uses the signing team and entitlements configured in the Xcode project, including Clerk's Associated Domains and the widget App Group. Add an active paid Apple Developer account in Xcode Settings → Accounts and select its team for both app and widget targets. Personal Teams cannot sign the required Associated Domains capability.

Then, from the repo root, using the device hardware UDID:

```sh
xcodebuild \
  -project apps/ios/Asterion.xcodeproj \
  -scheme Asterion \
  -destination 'id=<hardware-UDID>' \
  -derivedDataPath .artifacts/ios/device/<hardware-UDID> \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build

xcrun devicectl device install app \
  --device <hardware-UDID> \
  .artifacts/ios/device/<hardware-UDID>/Build/Products/Debug-iphoneos/Asterion.app

xcrun devicectl device process launch \
  --device <hardware-UDID> \
  cyberverse.Asterion
```

Cancel sends `SIGTERM` to the `xcodebuild` process group.

Physical iPhone/iPad devices come from `xcrun devicectl list devices --json-output`. The picker shows model + name + UDID so an iPad that advertises itself as “iPhone” stays identifiable. Simulators are omitted. If JSON listing fails, it falls back to `xcrun xctrace list devices` (Devices / Devices Offline only).
