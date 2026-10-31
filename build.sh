#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
APP="$PWD/build/Safari Quick Search.app"
mkdir -p "$APP/Contents/MacOS"
ARCH="$(uname -m)"
xcrun swiftc -swift-version 5 -O -parse-as-library \
  -sdk "${SDKROOT:-$(xcrun --show-sdk-path)}" \
  -target "$ARCH-apple-macosx13.0" \
  -module-cache-path "$PWD/build/module-cache" \
  Sources/*.swift -o "$APP/Contents/MacOS/Safari Quick Search" \
  -framework AppKit -framework SwiftUI -framework Carbon -lsqlite3
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '\nBuilt: %s\n' "$APP"
printf 'Move the app to Applications, launch it, and grant Full Disk Access to that copy.\n'
