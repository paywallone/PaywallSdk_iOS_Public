#!/usr/bin/env bash
# Kullanım: ./run.sh [simülatör adı]
# Test uygulamasını derler, simülatöre kurar ve açar. Varsayılan: açık simülatör, yoksa ilk iPhone simülatörü.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID="paywall.testtool.ios"
DERIVED="$DIR/DerivedData"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ -n "${1:-}" ]]; then
    DEVICE="$(xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
else
    DEVICE="$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
    [[ -n "$DEVICE" ]] || DEVICE="$(xcrun simctl list devices available | grep 'iPhone' | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
fi
[[ -n "$DEVICE" ]] || { echo "Uygun simülatör bulunamadı." >&2; exit 1; }

echo "Derleniyor..."
xcodebuild build -quiet -project "$DIR/PaywallTestTool.xcodeproj" -scheme PaywallTestTool \
    -destination "id=$DEVICE" -derivedDataPath "$DERIVED"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$DERIVED/Build/Products/Debug-iphonesimulator/PaywallTestTool.app"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
