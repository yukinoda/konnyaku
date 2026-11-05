#!/bin/bash
# Regenerates assets/AppIcon.icns and assets/logo.png from assets/logo.svg.
# Run after editing the SVG and commit the outputs; build-app.sh only copies them.
set -euo pipefail

cd "$(dirname "$0")/.."

svg=assets/logo.svg
work=$(mktemp -d)
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"

# sips cannot decode SVG on every macOS release, and qlmanage flattens the
# transparent corners onto white, so render once with AppKit, then downscale.
master="$work/master.png"
swift scripts/render-svg.swift "$svg" "$master"

for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns "$iconset" --output assets/AppIcon.icns
sips -z 256 256 "$master" --out assets/logo.png >/dev/null
rm -rf "$work"
echo "Wrote assets/AppIcon.icns and assets/logo.png"
