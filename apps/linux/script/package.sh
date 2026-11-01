#!/usr/bin/env bash
# Packages the Linux desktop app as an AppImage, the same way the Mac DMG and
# Android APK ship: a GitHub release with the artifact and its sha256.
#
#   apps/linux/script/package.sh 0.1.0            # build and verify into apps/linux/dist/
#   apps/linux/script/package.sh 0.1.0 --publish  # also create GitHub release linux-v0.1.0
#
# Needs JDK 21. Downloads appimagetool once to ~/.cache/asterion/appimagetool.
# Reuses the Android Gradle wrapper so no second wrapper is vendored.
# Local only: this script never pushes; --publish only creates the release
# from the local commit (caller pushes the tag by hand).
set -euo pipefail

VERSION="${1:?usage: package.sh MAJOR.MINOR.PATCH [--publish]}"
PUBLISH="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version must be MAJOR.MINOR.PATCH" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APPDIR="$DIST/AppDir"
GRADLEW="$ROOT/../android/gradlew"
TAG="linux-v$VERSION"
REPO="CyberVerse2/asterion-ios"
NOTES="$ROOT/release-notes/$VERSION.md"
APPIMAGETOOL="${ASTERION_APPIMAGETOOL:-$HOME/.cache/asterion/appimagetool}"

[[ -x "$GRADLEW" ]] || { echo "error: no wrapper at $GRADLEW" >&2; exit 1; }
command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }

# 1. Build + test. Core contract tests run here, so a broken paragraph rule
#    or fixture never reaches the AppImage.
"$GRADLEW" --console=plain -q -p "$ROOT" -Pasterion.version="$VERSION" :core:test :desktop:test :desktop:installDist

INSTALL="$ROOT/desktop/build/install/asterion"
[[ -x "$INSTALL/bin/asterion" ]] || { echo "error: $INSTALL/bin/asterion missing" >&2; exit 1; }

# 2. Smoke-test the installed launcher before packaging.
"$INSTALL/bin/asterion" --verify

# 3. Stage the AppDir.
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/icons/hicolor/512x512/apps" "$APPDIR/usr/share/applications"
cp -r "$INSTALL/bin" "$INSTALL/lib" "$APPDIR/usr/"
ln -sf usr/bin/asterion "$APPDIR/AppRun"
cp "$ROOT/packaging/asterion.desktop" "$APPDIR/asterion.desktop"
cp "$ROOT/packaging/asterion.desktop" "$APPDIR/usr/share/applications/asterion.desktop"
# TODO(phase 2): ship a real 512px icon. Placeholder keeps appimagetool/lint happy.
if [[ -f "$ROOT/packaging/asterion.png" ]]; then
  cp "$ROOT/packaging/asterion.png" "$APPDIR/usr/share/icons/hicolor/512x512/apps/asterion.png"
  cp "$ROOT/packaging/asterion.png" "$APPDIR/asterion.png"
else
  echo "warn: packaging/asterion.png missing, AppImage will use a fallback icon" >&2
fi

# 4. Fetch appimagetool once.
if [[ ! -x "$APPIMAGETOOL" ]]; then
  mkdir -p "$(dirname "$APPIMAGETOOL")"
  curl -fsSL -o "$APPIMAGETOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$APPIMAGETOOL"
fi

# 5. Build the AppImage.
mkdir -p "$DIST"
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$DIST/Asterion-${VERSION}-x86_64.AppImage"
(cd "$DIST" && shasum -a 256 "Asterion-${VERSION}-x86_64.AppImage" > "Asterion-${VERSION}-x86_64.AppImage.sha256")
ls -la "$DIST/Asterion-${VERSION}-x86_64.AppImage"

if [[ "$PUBLISH" != "--publish" ]]; then
  echo "Built $DIST/Asterion-${VERSION}-x86_64.AppImage. Re-run with --publish to create GitHub release $TAG."
  exit 0
fi

[[ -s "$NOTES" ]] || { echo "error: write release notes at $NOTES before publishing" >&2; exit 1; }
git -C "$ROOT" diff --quiet || { echo "error: commit your changes before publishing" >&2; exit 1; }
BODY="$(cat "$NOTES")

Install: download the .AppImage, make it executable (chmod +x), and run it. Later versions are offered inside the app under Account → About → Check for updates."
gh release create "$TAG" "$DIST/Asterion-${VERSION}-x86_64.AppImage" "$DIST/Asterion-${VERSION}-x86_64.AppImage.sha256" \
  --repo "$REPO" --title "Asterion for Linux $VERSION" --notes "$BODY" --latest=false
echo "Published $TAG (push the tag yourself: git push origin $TAG)"
