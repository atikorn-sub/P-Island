#!/bin/bash
# Builds "build/P Island.app" with the Command Line Tools (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/P Island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -O -swift-version 5 \
  -target arm64-apple-macos14.0 -sdk "$SDK" \
  -o "$APP/Contents/MacOS/PIsland" \
  Sources/*.swift

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
echo "Built $APP"

# ./build.sh --install  → replace "/Applications/P Island.app" and relaunch it.
if [ "${1:-}" = "--install" ]; then
  pkill -x PIsland || true
  sleep 0.5
  rm -rf "/Applications/P Island.app"
  cp -R "$APP" /Applications/
  open "/Applications/P Island.app"
  echo "Installed /Applications/P Island.app"
fi
