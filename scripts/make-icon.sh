#!/bin/bash
# Renders docs/app-icon.svg into Support/AppIcon.icns (requires librsvg + macOS iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found (brew install librsvg) — skipping icon generation"
  exit 0
fi

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" docs/app-icon.svg -o "$ICONSET/icon_${size}x${size}.png"
  rsvg-convert -w "$((size * 2))" -h "$((size * 2))" docs/app-icon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o Support/AppIcon.icns
echo "Wrote Support/AppIcon.icns"
