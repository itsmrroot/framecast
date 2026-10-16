#!/bin/bash
# Builds Framecast.app into ./build. Usage: scripts/build-app.sh [debug|release]
# Set ARCH=arm64 or ARCH=x86_64 to build for a specific architecture (default: the host's).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
# iCloud Drive (Desktop & Documents) skips anything named *.nosync. Synced app bundles get
# conflict copies ("Framecast 2.app") and Finder metadata that breaks code signing.
mkdir -p build.nosync
[ -L build ] || { [ -e build ] && echo "Move or delete ./build so it can link to build.nosync" >&2 && exit 1; ln -s build.nosync build; }
APP="build.nosync/Framecast.app"
# SwiftUI in the macOS 27 SDK needs Xcode's macro plugins; the 26 SDK builds with just the Command Line Tools.
SDK_ARGS=()
if [ -n "${ARCH:-}" ]; then SDK_ARGS+=(--arch "$ARCH"); fi
if ! xcodebuild -version >/dev/null 2>&1; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk; do
    if [ -d "$sdk" ]; then SDK_ARGS+=(--sdk "$sdk"); break; fi
  done
fi

SDK_ARGS+=(--scratch-path .build.nosync)
swift build -c "$CONFIG" "${SDK_ARGS[@]}"
BIN="$(swift build -c "$CONFIG" "${SDK_ARGS[@]}" --show-bin-path)/Framecast"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Framecast"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
  TMP="$(mktemp -d)"
  swift scripts/make-icon.swift "$TMP/icon.png"
  ICONSET="$TMP/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable identity when available so macOS remembers privacy permissions between builds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
xattr -cr "$APP"
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Built build/Framecast.app (signed with: ${IDENTITY:-ad-hoc})"
