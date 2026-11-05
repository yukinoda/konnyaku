#!/bin/bash
# Fails if the binary has an absolute rpath other than /usr/lib/swift,
# or lacks @executable_path/../Frameworks.
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <path-to-binary>" >&2
    exit 2
fi

binary="$1"
required="@executable_path/../Frameworks"
found_required=0
rpaths=$(otool -l "$binary" | awk '/cmd LC_RPATH/ {found=1} found && $1=="path" {print; found=0}')

while IFS= read -r line; do
    rpath="${line#*path }"
    rpath="${rpath% (offset *}"
    if [ -z "$rpath" ]; then
        continue
    fi
    echo "rpath: $rpath"
    if [ "$rpath" = "$required" ]; then
        found_required=1
    fi
    # Relative rpaths stay inside the bundle; only absolute ones are checked.
    if [[ "$rpath" != /* ]]; then
        continue
    fi
    if [ "$rpath" = "/usr/lib/swift" ]; then
        continue
    fi
    echo "error: unexpected absolute rpath: $rpath" >&2
    exit 1
done <<< "$rpaths"

if [ "$found_required" -ne 1 ]; then
    echo "error: missing rpath $required" >&2
    exit 1
fi
