#!/bin/bash
# Regenerates assets/AppIcon.icns and assets/logo.png from assets/logo.svg.
# Run after editing the SVG and commit the outputs; build-app.sh only copies them.
set -euo pipefail

cd "$(dirname "$0")/.."

svg=assets/logo.svg
iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -s format png -z "$size" "$size" "$svg" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -s format png -z "$double" "$double" "$svg" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns "$iconset" --output assets/AppIcon.icns
sips -s format png -z 256 256 "$svg" --out assets/logo.png >/dev/null
echo "Wrote assets/AppIcon.icns and assets/logo.png"
