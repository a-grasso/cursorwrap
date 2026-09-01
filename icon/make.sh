#!/bin/bash
# Renders icon.html and packs it into AppIcon.icns, the file build.sh ships.
# Run this after editing icon.html, and commit the .icns: a Homebrew build has
# a compiler but no browser, so it takes the packed icon as it finds it.
set -euo pipefail
cd "$(dirname "$0")"

CHROME=""
for candidate in \
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "$(command -v chromium || true)"
do
  [ -x "$candidate" ] && { CHROME="$candidate"; break; }
done
[ -n "$CHROME" ] || { echo "need a Chromium to render icon.html" >&2; exit 1; }

MASTER="icon@1024.png"
SET="AppIcon.iconset"

rm -rf "$SET" "$MASTER"
# Transparent background, or the corners the system rounds away come out black.
"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --default-background-color=00000000 --force-device-scale-factor=1 \
  --window-size=1024,1024 --screenshot="$MASTER" icon.html >/dev/null 2>&1
[ -f "$MASTER" ] || { echo "render produced nothing" >&2; exit 1; }

mkdir -p "$SET"
# iconutil wants every rung of the ladder, named its way.
emit() { sips -Z "$1" "$MASTER" --out "$SET/icon_$2.png" >/dev/null; }
emit 16   16x16
emit 32   16x16@2x
emit 32   32x32
emit 64   32x32@2x
emit 128  128x128
emit 256  128x128@2x
emit 256  256x256
emit 512  256x256@2x
emit 512  512x512
emit 1024 512x512@2x

iconutil --convert icns "$SET" --output AppIcon.icns
rm -rf "$SET" "$MASTER"
echo "built icon/AppIcon.icns"
