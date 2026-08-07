#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/.build/Products/Curty.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
STABLE_IDENTITY_NAME="${STABLE_IDENTITY_NAME:-Curty Self-Signed}"

# Требование подписи ad-hoc сборки — cdhash, то есть хеш содержимого. Он меняется
# при каждой пересборке, поэтому macOS видит новое приложение и сбрасывает все
# выданные разрешения: календарь, управление плеером. Подпись собственным
# сертификатом даёт требование по идентификатору и сертификату, и разрешения
# переживают обновление. Сертификат создаётся один раз вручную, см. README.
if [ "$SIGNING_IDENTITY" = "-" ] \
   && security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$STABLE_IDENTITY_NAME\""; then
    SIGNING_IDENTITY="$STABLE_IDENTITY_NAME"
fi

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

# Кнопке обновления не с чем сравнивать удалённую ветку, пока сборка не знает
# собственный коммит.
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
COMMIT_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD 2>/dev/null || true)"
if [ -n "$COMMIT" ]; then
    /usr/libexec/PlistBuddy -c "Add :CurtyBuildCommit string $COMMIT" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CurtyBuildCommitDate string $COMMIT_DATE" "$APP/Contents/Info.plist"
else
    echo "warning: сборка вне git-репозитория, проверка обновлений будет недоступна" >&2
fi

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
    echo "Сборка подписана разово (ad-hoc): выданные разрешения сбросятся при"
    echo "следующей пересборке. Как это вылечить — раздел «Разрешения» в README."
elif [ "$SIGNING_IDENTITY" = "$STABLE_IDENTITY_NAME" ]; then
    # Метка времени требует обращения к серверу Apple и с собственным
    # сертификатом не проходит.
    codesign --force --options runtime --timestamp=none \
        --entitlements "$ROOT/Config/Curty.entitlements" \
        --sign "$SIGNING_IDENTITY" "$APP"
    echo "Подписано локальным сертификатом «$SIGNING_IDENTITY»: разрешения переживут обновление."
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
