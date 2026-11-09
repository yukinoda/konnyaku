#!/bin/bash
# Builds build/Konnyaku.app from the SwiftPM release build (ad-hoc signed).
set -euo pipefail

version="${KONNYAKU_VERSION:-0.0.0}"
if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: KONNYAKU_VERSION must look like 1, 1.2 or 1.2.3 (got '$version')" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

swift build -c release
bin_dir=$(swift build -c release --show-bin-path)

app=build/Konnyaku.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"

cp "$bin_dir/Konnyaku" "$app/Contents/MacOS/Konnyaku"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

framework=$(find .build/artifacts -type d -name llama.framework -path "*macos-arm64*" | head -n 1)
if [ -z "$framework" ]; then
    echo "error: llama.framework not found under .build/artifacts" >&2
    exit 1
fi
cp -R "$framework" "$app/Contents/Frameworks/"

# Konnyaku runs only on Apple silicon, but the xcframework's macOS slice is
# universal, so drop the dead x86_64 code. lipo -thin rejects a binary that
# is already single-arch, so only thin a universal one.
llama_binary="$app/Contents/Frameworks/llama.framework/Versions/A/llama"
if [ "$(lipo -archs "$llama_binary")" != "arm64" ]; then
    lipo "$llama_binary" -thin arm64 -output "$llama_binary"
fi

# SwiftPM leaves absolute toolchain rpaths (Xcode, swiftly, Command Line Tools)
# that leak the builder's paths and are searched before the bundled frameworks.
# Keep only /usr/lib/swift and @-relative rpaths (@loader_path,
# @executable_path/...). Delete the rest: absolute paths, and bare relative
# paths such as "lib", which dyld resolves against the working directory.
binary="$app/Contents/MacOS/Konnyaku"
rpaths=$(otool -l "$binary" | awk '/cmd LC_RPATH/ {found=1} found && $1=="path" {print; found=0}')
while IFS= read -r line; do
    # Line looks like "path /some dir/lib (offset 12)"; keep the full path.
    rpath="${line#*path }"
    rpath="${rpath% (offset *}"
    # Skip the empty line produced when the binary has no rpaths at all.
    if [ -z "$rpath" ]; then
        continue
    fi
    if [ "$rpath" = "/usr/lib/swift" ]; then
        continue
    fi
    if [[ "$rpath" == @* ]]; then
        continue
    fi
    install_name_tool -delete_rpath "$rpath" "$binary"
done <<< "$rpaths"

frameworks_rpath="@executable_path/../Frameworks"
# Reuse the list captured above (relative rpaths were kept): `otool | grep -q`
# under pipefail can fail with SIGPIPE even when the rpath is present.
if ! grep -qF "path $frameworks_rpath " <<< "$rpaths"; then
    install_name_tool -add_rpath "$frameworks_rpath" "$binary"
fi
scripts/check-rpaths.sh "$binary"

# Apple silicon only (the DMG is named -arm64); fail if any binary disagrees.
for macho in "$binary" "$llama_binary"; do
    archs=$(lipo -archs "$macho")
    if [ "$archs" != "arm64" ]; then
        echo "error: $macho should be arm64 only, got '$archs'" >&2
        exit 1
    fi
done

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.yukinoda.konnyaku</string>
    <key>CFBundleName</key>
    <string>Konnyaku</string>
    <key>CFBundleExecutable</key>
    <string>Konnyaku</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Translate with Konnyaku</string>
            </dict>
            <key>NSMessage</key>
            <string>translateSelection</string>
            <key>NSPortName</key>
            <string>Konnyaku</string>
            <key>NSRequiredContext</key>
            <dict/>
            <key>NSSendTypes</key>
            <array>
                <string>public.utf8-plain-text</string>
                <string>NSStringPboardType</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# License notices ship inside the app (llama.cpp's MIT terms require it).
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"

# Ad-hoc signed with the hardened runtime: once Konnyaku holds the
# Accessibility permission, the runtime stops other processes from injecting
# code (DYLD_INSERT_LIBRARIES) to use that permission. The entitlement only
# relaxes library validation so the ad-hoc-signed framework can load.
codesign --force --sign - "$app/Contents/Frameworks/llama.framework"
codesign --force --sign - --options runtime --entitlements scripts/app.entitlements "$app"
codesign --verify --strict --verbose=2 "$app"
echo "Built $app"
