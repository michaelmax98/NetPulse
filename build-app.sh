#!/bin/bash
# Builds a standalone NetPulse.app into ./build
# Version can be overridden: VERSION=1.2.0 ./build-app.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"

swift build -c release

APP="build/NetPulse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/NetPulse" "$APP/Contents/MacOS/NetPulse"
cp "Support/Info.plist" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

if [ -f "Support/AppIcon.icns" ]; then
  cp "Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so macOS runs the locally built bundle without complaint.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP (version $VERSION)"
