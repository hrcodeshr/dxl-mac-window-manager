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
MACOS="$APP/Contents/MacOS"
FW="$APP/Contents/Frameworks"

rm -rf "$APP"
mkdir -p "$MACOS" "$APP/Contents/Resources" "$FW"
cp "$BIN" "$MACOS/DXLWindowManager"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
while read -r pixels filename; do
  sips -z "$pixels" "$pixels" "$ROOT/Resources/AppIcon.png" \
    --out "$ICONSET/$filename" >/dev/null
done <<'EOF'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
EOF
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

python3 - "$MACOS/DXLWindowManager" "$FW" <<'PY'
import os
import shutil
import subprocess
import sys

exe, dest = sys.argv[1], sys.argv[2]
os.makedirs(dest, exist_ok=True)


def rpaths(path):
    out = subprocess.check_output(["otool", "-l", path], text=True)
    paths = []
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if "LC_RPATH" not in line:
            continue
        for later in lines[i : i + 8]:
            if "path " in later:
                paths.append(later.split("path ", 1)[1].split(" (offset")[0].strip())
                break
    return paths


def linked(path):
    out = subprocess.check_output(["otool", "-L", path], text=True)
    libs = []
    for line in out.splitlines()[1:]:
        lib = line.strip().split()[0]
        if lib.startswith("/usr/lib/") or lib.startswith("/System/"):
            continue
        libs.append(lib)
    return libs


def resolve(lib, loader):
    if lib.startswith("@rpath/"):
        name = lib[len("@rpath/") :]
        for prefix in rpaths(loader):
            candidate = os.path.join(prefix, name)
            if os.path.isfile(candidate):
                return candidate
        return None
    if os.path.isfile(lib):
        return lib
    return None


copied = []
for lib in linked(exe):
    resolved = resolve(lib, exe)
    if not resolved:
        print(f"warning: could not resolve {lib}", file=sys.stderr)
        continue
    base = os.path.basename(resolved)
    shutil.copy2(resolved, os.path.join(dest, base))
    subprocess.check_call(["install_name_tool", "-change", lib, f"@rpath/{base}", exe])
    copied.append(base)

subprocess.call(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", exe])
print("embedded:", ", ".join(copied) if copied else "(nothing)")
PY

chmod +x "$MACOS/DXLWindowManager"

/usr/bin/xattr -cr "$APP" 2>/dev/null || true
if command -v codesign >/dev/null; then
  codesign --force --sign - --entitlements "$ROOT/Resources/DXLWindowManager.entitlements" "$APP" || true
fi

echo "Built $APP"
echo "A window and Dock icon should appear. If not, run:"
echo "  \"$MACOS/DXLWindowManager\""
echo "  cat ~/Library/Logs/dxl-window-manager.log"
