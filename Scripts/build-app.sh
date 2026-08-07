#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/.build/Products/Curty.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

# Проверка границ должна выполняться сама, иначе README обещает гарантию,
# которой нет: вручную её никто не запускает.
"$ROOT/Scripts/security-check.sh"

export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"

swift build --disable-sandbox -c "$CONFIGURATION" --package-path "$ROOT"
BIN_DIRECTORY="$(swift build --disable-sandbox -c "$CONFIGURATION" --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIRECTORY/Curty" "$APP/Contents/MacOS/Curty"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"

# The icon ships prebuilt. Building it here meant running iconutil on every
# machine, and on some systems it rejects the generated iconset outright
# ("Invalid Iconset") — a hard stop over something entirely static. Use
# Scripts/generate-icon.swift to regenerate Resources/AppIcon.icns when the
# artwork itself changes.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: Resources/AppIcon.icns не найден, собираю с системным значком" >&2
    # Without the file the key would point at nothing, which Launch Services
    # reports in ways that read like a broken bundle.
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

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
