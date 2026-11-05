#!/bin/bash
# Builds build/konjac-<version>.dmg (drag-to-install) and its SHA-256 file.
set -euo pipefail

cd "$(dirname "$0")/.."

export KONJAC_VERSION="${KONJAC_VERSION:-0.0.0}"
dmg="build/konjac-$KONJAC_VERSION.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

scripts/build-app.sh

cp -R build/konjac.app "$staging/"
ln -s /Applications "$staging/Applications"

# hdiutil intermittently fails with "Resource busy" on CI runners.
rm -f "$dmg"
for attempt in 1 2 3; do
    if hdiutil create -volname konjac -srcfolder "$staging" -format UDZO "$dmg"; then
        break
    fi
    if [ "$attempt" -eq 3 ]; then
        echo "error: hdiutil create failed after 3 attempts" >&2
        exit 1
    fi
    echo "hdiutil create failed (attempt $attempt), retrying" >&2
    rm -f "$dmg"
    sleep 5
done

(cd build && shasum -a 256 "konjac-$KONJAC_VERSION.dmg" > "konjac-$KONJAC_VERSION.dmg.sha256")
cat "$dmg.sha256"
