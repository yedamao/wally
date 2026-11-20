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
need "$MACOS/Wally/Sources/Wally/main.swift"
need "$MACOS/Wally/Sources/Wally/AppDelegate.swift"
need "$MACOS/Wally/Sources/Wally/GatewayController.swift"
need "$MACOS/Wally/Sources/Wally/MainWindowController.swift"
need "$MACOS/Wally/Sources/Wally/ThemeBridge.swift"
need "$MACOS/Wally/Sources/Wally/StatusOverlayView.swift"
need "$MACOS/Wally/Sources/Wally/Info.plist"
need "$MACOS/Wally/Sources/Wally/Resources/AppIcon.svg"
need "$MACOS/Wally/Sources/Wally/Resources/AppIcon.icns"
need "$MACOS/Wally/Sources/Wally/Resources/AppIcon.png"
need "$MACOS/scripts/generate-app-icon.py"
need "$MACOS/Wally/Tests/WallyTests/GatewayConfigTests.swift"

# Must be AppKit (Command Line Tools lack SwiftUIMacros).
if grep -R -n --include='*.swift' -E 'import SwiftUI|@State |@StateObject|@EnvironmentObject' "$MACOS/Wally/Sources" >/dev/null; then
  echo "SwiftUI macros found under Sources; the app must stay AppKit-only for CLT builds" >&2
  fail=1
fi

for key in CFBundleIdentifier CFBundleExecutable CFBundleIconFile LSMinimumSystemVersion NSAppTransportSecurity; do
  if ! grep -q "$key" "$MACOS/Wally/Sources/Wally/Info.plist"; then
    echo "Info.plist missing key: $key" >&2
    fail=1
  fi
done

if ! grep -q '<string>AppIcon</string>' "$MACOS/Wally/Sources/Wally/Info.plist"; then
  echo "Info.plist CFBundleIconFile should be AppIcon" >&2
  fail=1
fi

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
