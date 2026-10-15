#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Release packaging requires macOS." >&2
    exit 1
fi

for tool in swift codesign ditto iconutil lipo shasum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool not found: $tool" >&2
        exit 1
    fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$REPO_ROOT/.build/release-packaging"
APP_BUNDLE="$BUILD_ROOT/staging/Terso.app"
ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon
ICONSET_DIR="$REPO_ROOT/Sources/TersoApp/Assets.xcassets/$ASSETCATALOG_COMPILER_APPICON_NAME.appiconset"
ICONSET_STAGING_DIR="$BUILD_ROOT/$ASSETCATALOG_COMPILER_APPICON_NAME.iconset"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist}"
ZIP_PATH="$OUTPUT_DIR/Terso-v0.1-macOS.zip"

rm -rf "$BUILD_ROOT"
mkdir -p \
    "$BUILD_ROOT" \
    "$APP_BUNDLE/Contents/MacOS" \
    "$APP_BUNDLE/Contents/Resources" \
    "$ICONSET_STAGING_DIR" \
    "$OUTPUT_DIR"

cp "$ICONSET_DIR"/*.png "$ICONSET_STAGING_DIR/"
iconutil --convert icns \
    --output "$APP_BUNDLE/Contents/Resources/Terso.icns" \
    "$ICONSET_STAGING_DIR"

for architecture in arm64 x86_64; do
    triple="$architecture-apple-macosx13.0"
    build_path="$BUILD_ROOT/$architecture"

    echo "Building TersoApp for $triple..."
    swift build \
        --configuration release \
        --product TersoApp \
        --triple "$triple" \
        --build-path "$build_path"

    executable="$build_path/$architecture-apple-macosx/release/TersoApp"
    if [[ ! -x "$executable" ]]; then
        echo "Expected release executable was not produced: $executable" >&2
        exit 1
    fi

    if [[ "$architecture" == "arm64" ]]; then
        ARM64_EXECUTABLE="$executable"
        ARM64_RESOURCE_BUNDLE="$build_path/$architecture-apple-macosx/release/terso-app_TersoApp.bundle"
    else
        X86_64_EXECUTABLE="$executable"
    fi
done

if [[ ! -d "$ARM64_RESOURCE_BUNDLE" ]]; then
    echo "Expected TersoApp resource bundle was not produced: $ARM64_RESOURCE_BUNDLE" >&2
    exit 1
fi

ditto "$ARM64_RESOURCE_BUNDLE" \
    "$APP_BUNDLE/Contents/Resources/terso-app_TersoApp.bundle"

lipo -create "$ARM64_EXECUTABLE" "$X86_64_EXECUTABLE" \
    -output "$APP_BUNDLE/Contents/MacOS/TersoApp"
lipo "$APP_BUNDLE/Contents/MacOS/TersoApp" -verify_arch arm64 x86_64

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TersoApp</string>
    <key>CFBundleIconFile</key>
    <string>Terso</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>org.terso.app</string>
    <key>CFBundleName</key>
    <string>Terso</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")") > "$ZIP_PATH.sha256"

echo "Created $ZIP_PATH"
echo "Created $ZIP_PATH.sha256"
