#!/bin/zsh
# Builds Clipboard.app. No Xcode required — SwiftPM compiles the binary
# and we assemble the bundle around it, which is all an LSUIElement app needs.
#
#   ./build.sh            release (default)
#   ./build.sh debug      debug build, includes the self-test
set -e

cd "$(dirname "$0")"
CONFIG="${1:-release}"
APP="build/Clipboard.app"
ICNS="Resources/AppIcon.icns"

# The icon is generated from Tools/make-icon.swift. Re-render only when that
# source is newer than the .icns, so ordinary builds stay fast.
if [[ ! -f "$ICNS" || Tools/make-icon.swift -nt "$ICNS" ]]; then
  echo "==> rendering icon"
  swift Tools/make-icon.swift
  iconutil -c icns build/AppIcon.iconset -o "$ICNS"
fi

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" 2>&1 | grep -vE "XCTest|PlatformPath|^\s*$" || true

BIN=".build/$CONFIG/Clipboard"
[[ -f "$BIN" ]] || { echo "build failed: no binary at $BIN"; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signing, since notarizing needs a paid Apple Developer account. Note the
# consequence: the signature is a hash of the contents, so every rebuild is a new
# identity to macOS and the Accessibility grant silently stops applying. If a
# rebuilt copy won't auto-paste, that's why:
#   tccutil reset Accessibility com.kingsley.clipboard
codesign --force --sign - "$APP" 2>/dev/null

echo "==> built $APP"
