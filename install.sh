#!/bin/bash
# Tessera Clock installer for macOS.
#   git clone https://github.com/dngu/tessera-clock && cd tessera-clock && ./install.sh
# or, without cloning:
#   curl -fsSL https://raw.githubusercontent.com/dngu/tessera-clock/main/install.sh | bash
set -euo pipefail

[ "$(uname)" = Darwin ] || { echo "Tessera Clock's screensaver needs macOS."; exit 1; }
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Needs Apple's command line tools. Starting their installer; run this script again when it finishes."
  xcode-select --install || true
  exit 1
fi

# Run from a checkout, or fetch the source when piped from curl.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ ! -f "$DIR/build-saver.sh" ]; then
  DIR="$(mktemp -d)"
  trap 'rm -rf "$DIR"' EXIT
  echo "Downloading Tessera Clock…"
  curl -fsSL https://github.com/dngu/tessera-clock/archive/refs/heads/main.tar.gz | tar -xz -C "$DIR" --strip-components 1
fi

echo "Building…"
"$DIR/build-saver.sh" >/dev/null

DEST="$HOME/Library/Screen Savers"
mkdir -p "$DEST"
rm -rf "$DEST/TesseraClock.saver"
cp -R "$DIR/TesseraClock.saver" "$DEST/"
killall legacyScreenSaver 2>/dev/null || true   # drop any copy of the old version still loaded

echo "Installed to $DEST/TesseraClock.saver"
echo "Opening Screen Saver settings: pick Tessera Clock."
open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension" 2>/dev/null || true
