#!/usr/bin/env bash
# Renders Support/icon/AppIcon.svg into Support/icon/AppIcon-1024.png and Support/AppIcon.icns.
# Run it after editing the SVG; build.sh only copies the .icns.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
sips -s format png Support/icon/AppIcon.svg --out Support/icon/AppIcon-1024.png >/dev/null
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z $SIZE $SIZE Support/icon/AppIcon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  sips -z $((SIZE * 2)) $((SIZE * 2)) Support/icon/AppIcon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Support/AppIcon.icns
echo "Wrote Support/AppIcon.icns"
