# Wally for macOS

A native Mac app that runs the local Wally gateway and shows the embedded
WebUI in a `WKWebView` window — same workbench as `wally webui`, without
opening a browser.

The UI shell is **AppKit** (not SwiftUI), so it builds with either full
Xcode or the Command Line Tools. SwiftUI’s `@State` macros need the
`SwiftUIMacros` plugin, which Command Line Tools do not ship.

## Requirements

- macOS 14 or later
- Swift 5.9+ (Xcode or Command Line Tools)
- Go 1.26+ when the build script embeds a fresh `wally` binary

## Build

From the repository root on a Mac:

```sh
./macos/scripts/build-app.sh
open macos/dist/Wally.app
```

Useful flags:

```sh
./macos/scripts/build-app.sh --adhoc-sign          # local codesign
./macos/scripts/build-app.sh --cli /path/to/wally  # embed an existing binary
./macos/scripts/build-app.sh --no-cli              # rely on PATH / ~/go/bin
./macos/scripts/build-app.sh --sign "Developer ID Application: …"
```

The app looks for a `wally` (or `nanobot`) binary in this order:

1. `WALLY_BINARY` environment variable
2. `Contents/Resources/wally` inside the app bundle
3. `~/go/bin`, Homebrew, and `PATH`

## How it works

1. On launch, the app starts `wally webui --yes --no-open`.
2. That command enables the websocket channel if needed, attaches to a
   running gateway or starts an on-demand one (shared lease), and keeps
   the lease until the app quits.
3. The window loads `http://127.0.0.1:<gateway.port>/ui/` (default port
   **18790**, or whatever is in `~/.nanobot-go/config.json`).
4. Quitting the app terminates `wally webui`, which releases the lease
   (an on-demand gateway stops when no clients remain; a
   `gateway service install` / `gateway --background` gateway stays up).

Menus: **Reload WebUI** (⌘R), **Open in Browser** (⇧⌘O), **Show Logs**
(⌘L), **Restart Gateway** (⇧⌘R).

## Develop the Swift sources

```sh
cd macos/Wally
swift build
swift test
swift run   # runs the executable outside a .app bundle
```

Prefer `build-app.sh` for day-to-day use so `Info.plist`, ATS exceptions
for loopback HTTP, and the embedded CLI are in place.

## Structure check (any OS)

```sh
./macos/scripts/check-structure.sh
```

## Notes

- The app is **not** App Sandbox’d: it must spawn `wally` and talk to the
  local gateway (same trust model as running the CLI).
- First run still needs a config / API key (`wally onboard`, or open the
  WebUI Providers page once the window is up).
- This tree is source-only in CI on Linux; assemble `.app` on a Mac.
