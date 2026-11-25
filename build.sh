#!/usr/bin/env bash
# Builds Touché.app into ./build and (optionally) launches it.
#   ./build.sh          build only
#   ./build.sh run      build, kill any running copy, launch
#   ./build.sh install  build and copy to /Applications
#
# Optional environment (used by the release workflow):
#   SIGN_IDENTITY  a Developer ID Application identity (name or SHA-1); signs with the hardened runtime.
#                  Unset: ad-hoc signature, fine for running locally.
#   VERSION        overrides CFBundleShortVersionString (e.g. 1.2.0). Unset: from `git describe`, like 1.2.0-3-gabc1234.
#   BUILD_NUMBER   overrides CFBundleVersion
#   UNIVERSAL=1    builds for Apple silicon and Intel
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-}" == 1 ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
SWIFT_FLAGS=(-c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})
swift build "${SWIFT_FLAGS[@]}"
BIN_DIR=$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)

APP=build/Touché.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Touche" "$APP/Contents/MacOS/Touche"
# SwiftPM records macOS 14 as the SDK the binary was built with, and AppKit then draws pre-Liquid Glass controls
# for compatibility. Record the SDK it was actually compiled against.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Touche" "$APP/Contents/MacOS/Touche"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
PLIST="$APP/Contents/Info.plist"
VERSION=${VERSION:-$(git describe --tags --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)}
if [[ -n "${VERSION:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"; fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"; fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # Notarization requires the hardened runtime and a secure timestamp.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --identifier heliopolis.p3x972.touche "$APP"
else
  codesign --force --sign - --identifier heliopolis.p3x972.touche "$APP" >/dev/null
fi
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
