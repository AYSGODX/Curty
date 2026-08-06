#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/.build/Products/Curty.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"

swift build --disable-sandbox -c "$CONFIGURATION" --package-path "$ROOT"
BIN_DIRECTORY="$(swift build --disable-sandbox -c "$CONFIGURATION" --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIRECTORY/Curty" "$APP/Contents/MacOS/Curty"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"

ASSET_CATALOG="$ROOT/.build/CurtyAssets.xcassets"
APP_ICON_SET="$ASSET_CATALOG/AppIcon.appiconset"
COMPILED_ASSETS="$ROOT/.build/CompiledAssets"
ASSET_INFO="$ROOT/.build/AssetInfo.plist"
swift "$ROOT/Scripts/generate-icon.swift" "$APP_ICON_SET"
rm -rf "$COMPILED_ASSETS"
mkdir -p "$COMPILED_ASSETS"
xcrun actool \
    --compile "$COMPILED_ASSETS" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_INFO" \
    "$ASSET_CATALOG"
cp -R "$COMPILED_ASSETS/." "$APP/Contents/Resources/"

# Finder metadata and quarantine attributes are not part of the application
# payload and make strict code-signature verification fail after packaging.
xattr -cr "$APP"

if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --options runtime --timestamp=none \
        --entitlements "$ROOT/Config/Curty.entitlements" \
        --sign - "$APP"
    echo "Development build created with an ad-hoc identity. Do not distribute it."
else
    codesign --force --options runtime --timestamp \
        --entitlements "$ROOT/Config/Curty.entitlements" \
        --sign "$SIGNING_IDENTITY" "$APP"
fi

# Launch Services may attach Finder metadata after discovering the new icon.
# It is not executable content and must be absent for strict verification.
xattr -cr "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "$APP"
