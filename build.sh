#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
APP="$PWD/build/Safari Quick Search.app"
mkdir -p "$APP/Contents/MacOS"
ARCH="$(uname -m)"
xcrun swiftc -swift-version 5 -O -parse-as-library \
  -sdk "${SDKROOT:-$(xcrun --show-sdk-path)}" \
  -target "$ARCH-apple-macosx26.0" \
  -module-cache-path "$PWD/build/module-cache" \
  Sources/*.swift -o "$APP/Contents/MacOS/Safari Quick Search" \
  -framework AppKit -framework SwiftUI -framework Carbon -lsqlite3
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
# Resolve the same version variables Xcode reads, without changing the app filename.
APP_VERSION=$(awk '$1 == "MARKETING_VERSION" { print $3 }' Config/Version.xcconfig)
APP_BUILD=$(awk '$1 == "CURRENT_PROJECT_VERSION" { print $3 }' Config/Version.xcconfig)
[[ -n "$APP_VERSION" && -n "$APP_BUILD" ]] || { echo "Missing version in Config/Version.xcconfig" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '\nBuilt: %s\n' "$APP"
printf 'Move the app to Applications, launch it, and grant Full Disk Access to that copy.\n'
