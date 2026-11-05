#!/bin/bash
# Builds build/konjac-<version>.dmg (drag-to-install) and its SHA-256 file.
set -euo pipefail

cd "$(dirname "$0")/.."

export KONJAC_VERSION="${KONJAC_VERSION:-0.0.0-dev}"
dmg="build/konjac-$KONJAC_VERSION.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

scripts/build-app.sh

cp -R build/konjac.app "$staging/"
ln -s /Applications "$staging/Applications"

rm -f "$dmg"
hdiutil create -volname konjac -srcfolder "$staging" -format UDZO -ov "$dmg"

(cd build && shasum -a 256 "konjac-$KONJAC_VERSION.dmg" > "konjac-$KONJAC_VERSION.dmg.sha256")
cat "$dmg.sha256"
