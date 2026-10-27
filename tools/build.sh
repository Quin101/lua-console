#!/usr/bin/env bash
# Builds Qrawller Terminal for Windows (.exe) and macOS (.app).
#
#   ./tools/build.sh            -> dist/QrawllerTerminal-win64.zip and dist/QrawllerTerminal-macos.zip
#   ./tools/build.sh windows    -> only Windows
#   ./tools/build.sh mac        -> only macOS
#
# Needs: bash, curl, zip, unzip, python3 (for the mac Info.plist).
set -euo pipefail

LOVE_VERSION="11.5"
NAME="QrawllerTerminal"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
CACHE="$BUILD/cache"
TARGET="${1:-all}"

mkdir -p "$BUILD" "$DIST" "$CACHE"

# 1. pack the game into a .love file (just a zip of the source)
LOVEFILE="$BUILD/qrawller.love"
rm -f "$LOVEFILE"
(cd "$ROOT" && zip -9 -q -r "$LOVEFILE" main.lua conf.lua config.lua src commands widgets assets -x "*.DS_Store")
echo "packed  $LOVEFILE"

fetch() { # url dest
    if [ ! -f "$2" ]; then
        echo "download $1"
        curl -fsSL -o "$2" "$1"
    fi
}

build_windows() {
    local zipname="love-$LOVE_VERSION-win64"
    fetch "https://github.com/love2d/love/releases/download/$LOVE_VERSION/$zipname.zip" "$CACHE/$zipname.zip"
    rm -rf "$CACHE/$zipname" && unzip -q -o "$CACHE/$zipname.zip" -d "$CACHE"
    local out="$BUILD/$NAME-win64"
    rm -rf "$out" && mkdir -p "$out"
    # a "fused" exe is love.exe with the game appended to it
    cat "$CACHE/$zipname/love.exe" "$LOVEFILE" > "$out/$NAME.exe"
    cp "$CACHE/$zipname/"*.dll "$out/"
    cp "$CACHE/$zipname/license.txt" "$out/love-license.txt"
    cp "$ROOT/assets/fonts/LICENSE.txt" "$out/font-license.txt"
    rm -f "$DIST/$NAME-win64.zip"
    (cd "$BUILD" && zip -9 -q -r "$DIST/$NAME-win64.zip" "$NAME-win64")
    echo "built   $DIST/$NAME-win64.zip"
}

build_mac() {
    local zipname="love-$LOVE_VERSION-macos"
    fetch "https://github.com/love2d/love/releases/download/$LOVE_VERSION/$zipname.zip" "$CACHE/$zipname.zip"
    rm -rf "$CACHE/love.app" && unzip -q -o "$CACHE/$zipname.zip" -d "$CACHE"
    local app="$BUILD/$NAME.app"
    rm -rf "$app" && cp -R "$CACHE/love.app" "$app"
    cp "$LOVEFILE" "$app/Contents/Resources/qrawller.love"
    python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
with open(p, "rb") as f:
    d = plistlib.load(f)
d["CFBundleName"] = "Qrawller Terminal"
d["CFBundleIdentifier"] = "dev.qrawller.terminal"
d.pop("UTExportedTypeDeclarations", None)
d.pop("CFBundleDocumentTypes", None)
with open(p, "wb") as f:
    plistlib.dump(d, f)
PY
    rm -f "$DIST/$NAME-macos.zip"
    (cd "$BUILD" && zip -9 -q -r -y "$DIST/$NAME-macos.zip" "$NAME.app")
    echo "built   $DIST/$NAME-macos.zip"
}

case "$TARGET" in
    windows|win) build_windows ;;
    mac|macos) build_mac ;;
    all) build_windows; build_mac ;;
    *) echo "usage: $0 [all|windows|mac]"; exit 1 ;;
esac
