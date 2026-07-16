#!/bin/zsh
# Runs the self-test against a throwaway history file, so it never touches the
# real one and never inherits state from a previous run.
set -e
cd "$(dirname "$0")"

STORE="$(mktemp -t clipboardoverlay-test).json"
trap 'rm -f "$STORE"' EXIT

echo "==> building (debug — the self-test is compiled out of release builds)"
swift build 2>&1 | grep -vE "XCTest|PlatformPath|^\s*$" | grep -E "error|warning:|Compiling|Build complete" || true

echo "==> running self-test"
rm -f "$STORE"
CLIPBOARD_OVERLAY_STORE="$STORE" \
CLIPBOARD_OVERLAY_SELFTEST=1 \
  .build/debug/ClipboardOverlay 2>&1 | grep -E "PASS|FAIL|SELF TEST|accessibility"
