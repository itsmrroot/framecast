#!/bin/bash
# Packages build/Framecast.app into a drag-to-Applications disk image.
# Usage: scripts/make-dmg.sh <output.dmg>   (needs: pip install dmgbuild)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: scripts/make-dmg.sh <output.dmg>}"
APP="build/Framecast.app"
[ -d "$APP" ] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/make-dmg-background.swift "$WORK" >/dev/null
# One TIFF holding both resolutions, so the background is sharp on Retina displays.
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" 2>/dev/null

rm -f "$OUT"
python3 -m dmgbuild -s scripts/dmg-settings.py \
  -D app="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")" \
  -D background="$WORK/background.tiff" \
  -D icon="$PWD/Resources/AppIcon.icns" \
  "Framecast" "$OUT"

# Sign the disk image with the same identity as the app, when one is set.
if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "$CODESIGN_IDENTITY" != "-" ]; then
  codesign --force --sign "$CODESIGN_IDENTITY" "$OUT"
fi
echo "Built $OUT"
