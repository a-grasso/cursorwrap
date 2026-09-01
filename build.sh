#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="CursorWrap.app"

# main.swift owns the version; reading it back out here keeps Info.plist from
# drifting away from what `cursorwrap --version` reports.
VERSION="$(sed -n 's/^let VERSION = "\(.*\)"$/\1/p' main.swift)"
[ -n "$VERSION" ] || { echo "cannot read VERSION from main.swift" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/cursorwrap" main.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.agrasso.cursorwrap</string>
  <key>CFBundleName</key><string>CursorWrap</string>
  <key>CFBundleExecutable</key><string>cursorwrap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - --identifier dev.agrasso.cursorwrap "$APP"
echo "built $APP ($VERSION)"
