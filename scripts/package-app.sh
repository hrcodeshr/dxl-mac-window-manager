#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This app must be built on macOS." >&2
  exit 1
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DXLWindowManager"
APP="$ROOT/dist/DXL Window Manager.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DXLWindowManager"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/DXLWindowManager"

if command -v codesign >/dev/null; then
  codesign --force --sign - --entitlements "$ROOT/Resources/DXLWindowManager.entitlements" "$APP" || true
fi

echo "Built $APP"
echo "Open it, then grant Accessibility access in System Settings → Privacy & Security → Accessibility."
