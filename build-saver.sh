#!/bin/bash
# Install it afterwards with:  open TesseraClock.saver
set -euo pipefail
cd "$(dirname "$0")"

OUT="TesseraClock.saver"
SDK="$(xcrun --show-sdk-path)"
TARGET="$(uname -m)-apple-macos13.0"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

# A screensaver is a loadable bundle, so compile to an object and link with -bundle.
xcrun swiftc -O -parse-as-library -module-name TesseraClock -target "$TARGET" -sdk "$SDK" \
  -emit-object -o "$TMP/TesseraClock.o" TesseraClock/TesseraClockView.swift
xcrun clang -bundle -target "$TARGET" -isysroot "$SDK" \
  -L "$SDK/usr/lib/swift" -L /usr/lib/swift -Wl,-rpath,/usr/lib/swift \
  -o "$OUT/Contents/MacOS/TesseraClock" "$TMP/TesseraClock.o"

cp TesseraClock/Info.plist "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT"
echo "Built $OUT"
