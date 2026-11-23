#!/usr/bin/env bash
# Builds Touché.app into ./build and (optionally) launches it.
#   ./build.sh          build only
#   ./build.sh run      build, kill any running copy, launch
#   ./build.sh install  build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Touché.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Touche "$APP/Contents/MacOS/Touche"
# SwiftPM records macOS 14 as the SDK the binary was built with, and AppKit then draws pre-Liquid Glass controls
# for compatibility. Record the SDK it was actually compiled against.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Touche" "$APP/Contents/MacOS/Touche"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier dev.isaiah.touche "$APP" >/dev/null
echo "Built $APP"

case "${1:-}" in
  run)
    pkill -x Touche && sleep 1 || true
    open "$APP"
    ;;
  install)
    pkill -x Touche && sleep 1 || true
    rm -rf "/Applications/Touché.app"
    cp -R "$APP" /Applications/
    open "/Applications/Touché.app"
    echo "Installed to /Applications"
    ;;
esac
