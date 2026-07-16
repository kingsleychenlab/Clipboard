#!/bin/zsh
# Builds Clipboard Overlay from source and installs it to /Applications.
#
#   ./install.sh
#
# Building locally (rather than downloading a binary) is deliberate: the app is
# ad-hoc signed, so a downloaded copy would be quarantined by Gatekeeper and
# need extra steps to open. Built on your own machine, it just runs.
set -e

cd "$(dirname "$0")"
APP_NAME="ClipboardOverlay.app"
DEST="/Applications/$APP_NAME"

echo "Clipboard Overlay — install"
echo

# --- checks -----------------------------------------------------------------

MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if (( MACOS_MAJOR < 13 )); then
  echo "✗ macOS 13 or later required (found $(sw_vers -productVersion))"
  exit 1
fi

if ! command -v swift > /dev/null; then
  echo "✗ The Swift toolchain isn't installed."
  echo "  Run:  xcode-select --install"
  exit 1
fi

echo "✓ macOS $(sw_vers -productVersion), $(swift --version 2>/dev/null | head -1)"
echo

# --- build ------------------------------------------------------------------

./build.sh release

# --- install ----------------------------------------------------------------

if pgrep -q ClipboardOverlay; then
  echo "==> stopping the running copy"
  pkill ClipboardOverlay || true
  sleep 1
fi

echo "==> installing to $DEST"
rm -rf "$DEST"
cp -R "build/$APP_NAME" "$DEST"

echo "==> launching"
open "$DEST"

cat <<'EOF'

Installed. Nothing will appear — that's correct, it has no dock or menu bar icon.

  Press Cmd+Shift+V from any app to summon it.

One more step for auto-paste:
  The first time you press Enter on a clip, macOS will ask for Accessibility
  permission — it's required to send the Cmd+V keystroke for you. Approve it at
  System Settings → Privacy & Security → Accessibility.
  Without it everything still works; you just press Cmd+V yourself.

To start it automatically at login:
  System Settings → General → Login Items → + → ClipboardOverlay

To uninstall:
  pkill ClipboardOverlay
  rm -rf /Applications/ClipboardOverlay.app
  rm -rf ~/Library/Application\ Support/ClipboardOverlay
EOF
