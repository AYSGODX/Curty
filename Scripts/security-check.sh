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

for pattern in 'PrivateFrameworks' 'MediaRemote' 'DynaLoader' 'dlopen' '/usr/bin/perl' 'CGEvent.*post' 'URLSession' 'NWConnection' 'com.apple.security.network.client'; do
    if scan "$pattern" "$ROOT/Sources" "$ROOT/Config"; then
        echo "Forbidden capability found: $pattern" >&2
        FAILURES=1
    fi
done

if ! scan '<key>com.apple.security.app-sandbox</key>' "$ROOT/Config/Curty.entitlements"; then
    echo "Sandbox entitlement is missing." >&2
    FAILURES=1
fi

if scan 'Key\.clipboardImages:[[:space:]]*true' "$ROOT/Sources"; then
    echo "Automatic clipboard image capture must remain opt-in." >&2
    FAILURES=1
fi

exit "$FAILURES"
