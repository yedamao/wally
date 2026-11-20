#!/usr/bin/env bash
# Build Wally.app on macOS: compile the AppKit + WKWebView shell and embed
# a darwin wally binary. Run from anywhere; requires macOS 14+, Swift 5.9+
# (Xcode or Command Line Tools), and Go 1.26+ when embedding a fresh CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS="$ROOT/macos"
APP_SRC="$MACOS/Wally"
OUT_DIR="${OUT_DIR:-$MACOS/dist}"
APP="$OUT_DIR/Wally.app"
CONFIG="${CONFIGURATION:-release}"
BUILD_CLI=1
CLI_BIN=""
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ADHOC_SIGN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --out DIR           Output directory (default: macos/dist)
  --cli PATH          Use an existing wally binary instead of building one
  --no-cli            Do not embed a wally binary (app will search PATH)
  --debug             Build the Swift package in debug mode
  --sign IDENTITY     codesign with IDENTITY (e.g. "Developer ID Application: …")
  --adhoc-sign        codesign -s - (local run without a certificate)
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; APP="$OUT_DIR/Wally.app"; shift 2 ;;
    --cli) CLI_BIN="$2"; BUILD_CLI=0; shift 2 ;;
    --no-cli) BUILD_CLI=0; CLI_BIN=""; shift ;;
    --debug) CONFIG=debug; shift ;;
    --sign) SIGN_IDENTITY="$2"; shift 2 ;;
    --adhoc-sign) ADHOC_SIGN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-app.sh must run on macOS (AppKit / WebKit)." >&2
  exit 1
fi

# Prefer full Xcode when present (better SDKs); CLT alone is enough for AppKit.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! command -v swift >/dev/null; then
  echo "swift not found; install Xcode or the Command Line Tools." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$APP"

echo "==> Building Swift package ($CONFIG) with $(swift --version 2>&1 | head -1)"
echo "    DEVELOPER_DIR=${DEVELOPER_DIR:-"(default)"}"
(
  cd "$APP_SRC"
  # Clear a stale build dir that may have been produced under a different toolchain.
  rm -rf .build
  swift build -c "$CONFIG" --product Wally
)

BIN="$(cd "$APP_SRC" && swift build -c "$CONFIG" --show-bin-path)/Wally"
if [[ ! -x "$BIN" ]]; then
  echo "Swift build did not produce $BIN" >&2
  exit 1
fi

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wally"
chmod +x "$APP/Contents/MacOS/Wally"
cp "$APP_SRC/Sources/Wally/Info.plist" "$APP/Contents/Info.plist"

# Dock / Finder icon (CFBundleIconFile = AppIcon → AppIcon.icns).
ICON_DIR="$APP_SRC/Sources/Wally/Resources"
ICON_ICNS="$ICON_DIR/AppIcon.icns"
ICON_PNG="$ICON_DIR/AppIcon.png"
ICON_SVG="$ICON_DIR/AppIcon.svg"
if [[ -f "$ICON_ICNS" ]]; then
  cp "$ICON_ICNS" "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f "$ICON_SVG" ]] && command -v iconutil >/dev/null && command -v sips >/dev/null; then
  echo "==> Generating AppIcon.icns from SVG"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  MASTER="$(mktemp).png"
  # Prefer rsvg-convert; fall back to qlmanage is unreliable — require a PNG master.
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w 1024 -h 1024 "$ICON_SVG" -o "$MASTER"
  elif [[ -f "$ICON_PNG" ]]; then
    cp "$ICON_PNG" "$MASTER"
  else
    echo "Need AppIcon.icns or rsvg-convert / AppIcon.png to build the icon" >&2
    exit 1
  fi
  for pair in 16:icon_16x16 32:diana.k@example.org 32:icon_32x32 64:ivan.p@example.net \
              128:icon_128x128 256:wendy.h@example.net 256:icon_256x256 512:xavier.y@example.org \
              512:icon_512x512 1024:hannah.h@example.com; do
    size="${pair%%:*}"
    name="${pair##*:}"
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")" "$MASTER"
else
  echo "missing AppIcon.icns under $ICON_DIR (run macos/scripts/generate-app-icon.py)" >&2
  exit 1
fi
if [[ -f "$ICON_PNG" ]]; then
  cp "$ICON_PNG" "$APP/Contents/Resources/AppIcon.png"
fi
if [[ -f "$ICON_SVG" ]]; then
  cp "$ICON_SVG" "$APP/Contents/Resources/AppIcon.svg"
fi

if [[ "$BUILD_CLI" -eq 1 && -z "$CLI_BIN" ]]; then
  echo "==> Building darwin wally CLI"
  mkdir -p "$ROOT/bin"
  (
    cd "$ROOT"
    GOOS=darwin go build -o "$ROOT/bin/wally" ./cmd/wally
  )
  # When cross-building from Apple Silicon vs Intel hosts, go uses the host arch.
  CLI_BIN="$ROOT/bin/wally"
fi

if [[ -n "$CLI_BIN" ]]; then
  if [[ ! -x "$CLI_BIN" ]]; then
    echo "CLI binary not executable: $CLI_BIN" >&2
    exit 1
  fi
  echo "==> Embedding CLI: $CLI_BIN"
  cp "$CLI_BIN" "$APP/Contents/Resources/wally"
  chmod +x "$APP/Contents/Resources/wally"
fi

# PkgInfo
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Always sign: unsigned .app bundles often fail to show a UI under modern macOS.
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> codesign ($SIGN_IDENTITY)"
  codesign --force --deep --options runtime \
    --entitlements "$APP_SRC/Wally.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"
else
  echo "==> ad-hoc codesign"
  codesign --force --deep --sign - "$APP"
fi

# Drop quarantine so `open` does not silently refuse a freshly built app.
xattr -cr "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Open with: open \"$APP\""
echo "If the window still does not appear, check: ~/Library/Logs/Wally/launch.log"
