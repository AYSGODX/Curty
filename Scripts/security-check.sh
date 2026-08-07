#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# Returns 0 when the pattern is present. A scan that cannot run at all is a
# hard failure: silently reporting "not found" would turn every check below
# into a false pass.
scan() {
    local pattern="$1"
    shift
    local status=0
    grep -rEn "$pattern" "$@" >/dev/null || status=$?
    if [ "$status" -gt 1 ]; then
        echo "Scan could not run for pattern: $pattern" >&2
        exit 2
    fi
    return "$status"
}

for pattern in 'PrivateFrameworks' 'MediaRemote' 'DynaLoader' 'dlopen' '/usr/bin/perl' 'CGEvent.*post' 'NWConnection'; do
    if scan "$pattern" "$ROOT/Sources" "$ROOT/Config"; then
        echo "Forbidden capability found: $pattern" >&2
        FAILURES=1
    fi
done

# Network access exists for one reason only: album covers, which Spotify hands
# out as a link rather than as image data. The entitlement is therefore expected,
# but the code using it must stay in one file so it cannot quietly spread.
ARTWORK_FILE="$ROOT/Sources/Curty/Features/Media/ArtworkLoader.swift"

# Однозначно сетевые API: им место только в загрузчике обложек.
NETWORK_USERS="$(grep -rlE 'URLSession|NSURLConnection|CFReadStream' "$ROOT/Sources" 2>/dev/null || true)"
if [ "$NETWORK_USERS" != "$ARTWORK_FILE" ]; then
    echo "Сетевой код должен жить только в ArtworkLoader.swift, найден в: ${NETWORK_USERS:-нигде}" >&2
    FAILURES=1
fi

# contentsOf: одинаково читает и файл, и http-адрес — грепом их не различить.
# Поэтому список файлов, которым это позволено, задан явно: новое обращение
# придётся внести сюда руками, то есть осознанно.
CONTENTS_OF_ALLOWED="$ARTWORK_FILE
$ROOT/Sources/Curty/Core/AtomicJSONStore.swift"
CONTENTS_OF_USERS="$(grep -rlE '(Data|String)\(contentsOf' "$ROOT/Sources" 2>/dev/null || true)"
UNEXPECTED="$(comm -23 <(echo "$CONTENTS_OF_USERS" | sort) <(echo "$CONTENTS_OF_ALLOWED" | sort) | grep -v '^$' || true)"
if [ -n "$UNEXPECTED" ]; then
    echo "contentsOf: вне списка разрешённых файлов: $UNEXPECTED" >&2
    echo "Если это чтение локального файла — добавьте файл в CONTENTS_OF_ALLOWED." >&2
    FAILURES=1
fi

if ! scan 'approvedHosts' "$ARTWORK_FILE"; then
    echo "The artwork loader must keep its host allowlist." >&2
    FAILURES=1
fi

if ! scan '<key>com.apple.security.app-sandbox</key>' "$ROOT/Config/Curty.entitlements"; then
    echo "Sandbox entitlement is missing." >&2
    FAILURES=1
fi

if scan 'Key\.clipboardImages:[[:space:]]*true' "$ROOT/Sources"; then
    echo "Automatic clipboard image capture must remain opt-in." >&2
    FAILURES=1
fi

exit "$FAILURES"
