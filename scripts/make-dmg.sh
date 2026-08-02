#!/bin/bash
# Packages build/NetPulse.app into dist/NetPulse-<version>.dmg
# with the classic drag-to-Applications window.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-dev}"
APP="build/NetPulse.app"
[ -d "$APP" ] || { echo "Run build-app.sh first"; exit 1; }

mkdir -p dist
OUT="dist/NetPulse-${VERSION}.dmg"
rm -f "$OUT"

STAGE="build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

made=false
if command -v create-dmg >/dev/null 2>&1; then
  if create-dmg \
      --volname "NetPulse" \
      --window-pos 200 150 \
      --window-size 540 360 \
      --icon-size 128 \
      --icon "NetPulse.app" 140 160 \
      --app-drop-link 400 160 \
      --hide-extension "NetPulse.app" \
      "$OUT" "$STAGE"; then
    made=true
  else
    echo "create-dmg failed; falling back to hdiutil"
    rm -f "$OUT"
  fi
fi

if [ "$made" = false ]; then
  ln -sfn /Applications "$STAGE/Applications"
  hdiutil create -volname "NetPulse" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
fi

echo "Wrote $OUT"
