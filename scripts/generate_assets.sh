#!/bin/bash
# Generate Din.icns from the 1024px icon PNG.
#
# Usage: ./scripts/generate_assets.sh
#
# Expects scripts/build/icon_1024.png to exist (written by scripts/render_readme.swift,
# which the Assets workflow runs on a macOS runner).
# Outputs Din/Assets/Din.icns

set -euo pipefail
cd "$(dirname "$0")/.."

ICON="scripts/build/icon_1024.png"
ICONSET="scripts/build/Din.iconset"
ICNS="Din/Assets/Din.icns"

if [ ! -f "$ICON" ]; then
    echo "Error: $ICON not found. It is produced by scripts/render_readme.swift." >&2
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$(dirname "$ICNS")"
iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Created $ICNS"
