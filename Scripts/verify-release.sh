#!/bin/bash
set -euo pipefail

APP="${1:?usage: verify-release.sh /path/to/Curty.app}"

xattr -cr "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" 2>&1 | grep -q 'com.apple.security.app-sandbox'

# Network access is expected (album covers), but nothing beyond it should ever
# appear: no server socket, no unsandboxed escape hatch.
for forbidden in 'com.apple.security.files.user-selected.read-write' 'com.apple.security.network.server' 'com.apple.security.cs.disable-library-validation' 'com.apple.security.cs.allow-unsigned-executable-memory'; do
    if codesign -d --entitlements :- "$APP" 2>&1 | grep -q "$forbidden"; then
        echo "Main app unexpectedly has $forbidden." >&2
        exit 1
    fi
done

if [ "${ALLOW_DEVELOPMENT_SIGNATURE:-0}" != "1" ]; then
    spctl --assess --type execute --verbose=4 "$APP"
fi
