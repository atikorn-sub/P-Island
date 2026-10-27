#!/bin/bash
# Builds "build.noindex/P Island.app" with the Command Line Tools (no Xcode project needed).
#
#   ./build.sh              build for this Mac (Apple silicon)
#   ./build.sh --install    build, replace "/Applications/P Island.app" and relaunch it
#   ./build.sh --release    universal build (Apple silicon + Intel), then dist/ gets the
#                           .dmg and the YouTube Music extension .zip to upload to GitHub
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
BUILD=build.noindex
APP="$BUILD/P Island.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# The build copy is not the app to launch; keep it out of Launch Services (Launchpad, "Open With").
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

ARCHS="arm64"
if [ "$MODE" = "--release" ]; then ARCHS="arm64 x86_64"; fi

SDK=$(xcrun --sdk macosx --show-sdk-path)
SLICES=()
for ARCH in $ARCHS; do
  echo "Compiling for $ARCH…"
  swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos14.0" -sdk "$SDK" \
    -o "$BUILD/PIsland-$ARCH" \
    Sources/*.swift
  SLICES+=("$BUILD/PIsland-$ARCH")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/PIsland"

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Sign with the self-made "P Island Developer" certificate when it exists. A stable signature lets
# macOS remember granted permissions across rebuilds; an ad-hoc one (-) looks like a new app each time.
IDENTITY="P Island Developer"
# By hash, and only among code-signing identities, so an e-mail certificate of the same name can't be picked.
SIGN_HASH=$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$IDENTITY\"" 'index($0, n) {print $2; exit}')
if [ -n "$SIGN_HASH" ]; then
  codesign --force --sign "$SIGN_HASH" "$APP"
else
  echo "note: no \"$IDENTITY\" certificate, signing ad-hoc (permissions reset on every build)"
  codesign --force --sign - "$APP"
fi
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/PIsland"))"
"$LSREGISTER" -u "$APP" 2>/dev/null || true

if [ "$MODE" = "--install" ]; then
  pkill -x PIsland || true
  sleep 0.5
  rm -rf "/Applications/P Island.app"
  cp -R "$APP" /Applications/
  open "/Applications/P Island.app"
  echo "Installed /Applications/P Island.app"
fi

if [ "$MODE" = "--release" ]; then
  DIST=dist
  STAGE=$BUILD/dmg
  rm -rf "$STAGE" "$DIST"
  mkdir -p "$STAGE" "$DIST"

  # The disk image: the app, a shortcut to Applications to drag it onto, and short instructions.
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cp Resources/dmg/*.txt "$STAGE/"
  hdiutil create -volname "P Island $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov \
    "$DIST/P-Island-$VERSION.dmg" >/dev/null
  rm -rf "$STAGE"

  # The Chrome extension for YouTube Music, ready for "Load unpacked" after unzipping.
  (cd ChromeExtension && zip -qr "../$DIST/P-Island-YouTube-Music-Extension.zip" . -x ".*")

  (cd "$DIST" && shasum -a 256 * > SHA256SUMS.txt)
  echo "Release files in $DIST/:"
  ls -lh "$DIST"
fi
