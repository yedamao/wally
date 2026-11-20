#!/usr/bin/env bash
# Validate the macOS app tree on any host (including Linux CI). Does not
# compile Swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS="$ROOT/macos"
fail=0

need() {
  if [[ ! -e "$1" ]]; then
    echo "missing: $1" >&2
    fail=1
  fi
}

need "$MACOS/README.md"
need "$MACOS/scripts/build-app.sh"
need "$MACOS/Wally/Package.swift"
need "$MACOS/Wally/Wally.entitlements"
need "$MACOS/Wally/Sources/Wally/WallyApp.swift"
need "$MACOS/Wally/Sources/Wally/GatewayController.swift"
need "$MACOS/Wally/Sources/Wally/ContentView.swift"
need "$MACOS/Wally/Sources/Wally/WebView.swift"
need "$MACOS/Wally/Sources/Wally/SettingsView.swift"
need "$MACOS/Wally/Sources/Wally/Info.plist"
need "$MACOS/Wally/Sources/Wally/Resources/AppIcon.svg"
need "$MACOS/Wally/Tests/WallyTests/GatewayConfigTests.swift"

# Info.plist essentials
for key in CFBundleIdentifier CFBundleExecutable LSMinimumSystemVersion NSAppTransportSecurity; do
  if ! grep -q "$key" "$MACOS/Wally/Sources/Wally/Info.plist"; then
    echo "Info.plist missing key: $key" >&2
    fail=1
  fi
done

if ! grep -q 'ai.wally.app' "$MACOS/Wally/Sources/Wally/Info.plist"; then
  echo "Info.plist bundle id should be ai.wally.app" >&2
  fail=1
fi

if ! grep -q 'webui' "$MACOS/Wally/Sources/Wally/GatewayController.swift"; then
  echo "GatewayController should launch wally webui" >&2
  fail=1
fi

if [[ "$(uname -s)" == "Darwin" ]] && command -v swift >/dev/null; then
  echo "==> swift test (WallyTests)"
  (cd "$MACOS/Wally" && swift test --filter WallyTests)
fi

if [[ "$fail" -ne 0 ]]; then
  echo "macos structure check failed" >&2
  exit 1
fi
echo "macos structure check ok"
