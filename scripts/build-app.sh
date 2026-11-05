#!/bin/bash
# Builds build/konjac.app from the SwiftPM release build (ad-hoc signed).
set -euo pipefail

version="${KONJAC_VERSION:-0.0.0-dev}"

cd "$(dirname "$0")/.."

swift build -c release
bin_dir=$(swift build -c release --show-bin-path)

app=build/konjac.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"

cp "$bin_dir/Konjac" "$app/Contents/MacOS/konjac"

framework=$(find .build/artifacts -type d -name llama.framework -path "*macos-arm64_x86_64*" | head -n 1)
if [ -z "$framework" ]; then
    echo "error: llama.framework not found under .build/artifacts" >&2
    exit 1
fi
cp -R "$framework" "$app/Contents/Frameworks/"

# SwiftPM leaves absolute toolchain rpaths (Xcode paths) that mean nothing on other Macs.
binary="$app/Contents/MacOS/konjac"
otool -l "$binary" | awk '/cmd LC_RPATH/ {found=1} found && $1=="path" {print $2; found=0}' | while read -r rpath; do
    install_name_tool -delete_rpath "$rpath" "$binary"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$binary"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>org.konjac.app</string>
    <key>CFBundleName</key>
    <string>konjac</string>
    <key>CFBundleExecutable</key>
    <string>konjac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc only, no hardened runtime: library validation would reject the
# ad-hoc-signed bundled framework, and without notarization it adds nothing.
codesign --force --sign - "$app/Contents/Frameworks/llama.framework"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
echo "Built $app"
