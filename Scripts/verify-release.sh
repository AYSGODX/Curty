#!/bin/bash
set -euo pipefail

APP="${1:?usage: verify-release.sh /path/to/Curty.app}"

xattr -cr "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" 2>&1 | grep -q 'com.apple.security.app-sandbox'

if codesign -d --entitlements :- "$APP" 2>&1 | grep -q 'com.apple.security.network.client'; then
    echo "Main app unexpectedly has network access." >&2
    exit 1
fi

if [ "${ALLOW_DEVELOPMENT_SIGNATURE:-0}" != "1" ]; then
    spctl --assess --type execute --verbose=4 "$APP"
fi
