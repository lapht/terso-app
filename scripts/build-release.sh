#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Release packaging requires macOS." >&2
    exit 1
fi

for tool in xcodebuild codesign ditto shasum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool not found: $tool" >&2
        exit 1
    fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$REPO_ROOT/.build/release-packaging"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/Terso.app"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist}"
ZIP_PATH="$OUTPUT_DIR/Terso-v0.1-macOS.zip"

rm -rf "$BUILD_ROOT"
mkdir -p "$OUTPUT_DIR"

echo "Building universal Terso.app with Xcode..."
xcodebuild \
    -project "$REPO_ROOT/Terso.xcodeproj" \
    -scheme TersoApp \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Expected release app bundle was not produced: $APP_BUNDLE" >&2
    exit 1
fi

codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")") > "$ZIP_PATH.sha256"

echo "Created $ZIP_PATH"
echo "Created $ZIP_PATH.sha256"
