#!/usr/bin/env bash
# Regenerates every AppIcon.appiconset PNG from the 1024×1024 master so slots stay
# sharp and dimension-correct (fixes drifted or placeholder icons).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
OUT="$ROOT/Sources/AppLocker/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$MASTER" ]]; then
  echo "Missing master icon: $MASTER" >&2
  exit 1
fi

resize() {
  local px="$1"
  local file="$2"
  sips -z "$px" "$px" "$MASTER" --out "$OUT/$file" >/dev/null
}

echo "Resizing from $MASTER …"
# iPhone
resize 40  "Icon-20@2x.png"
resize 60  "Icon-20@3x.png"
resize 58  "Icon-29@2x.png"
resize 87  "Icon-29@3x.png"
resize 80  "Icon-40@2x.png"
resize 120 "Icon-40@3x.png"
resize 120 "Icon-60@2x.png"
resize 180 "Icon-60@3x.png"
# iPad
resize 152 "Icon-76@2x.png"
resize 167 "Icon-83.5@2x.png"
resize 20  "Icon-20.png"
resize 29  "Icon-29.png"
resize 58  "Icon-29@2x.png"
resize 40  "Icon-40.png"
resize 80  "Icon-40@2x.png"
# macOS
resize 16  "Icon-mac-16.png"
resize 32  "Icon-mac-16@2x.png"
resize 32  "Icon-mac-32.png"
resize 64  "Icon-mac-32@2x.png"
resize 128  "Icon-mac-128.png"
resize 256  "Icon-mac-128@2x.png"
resize 256  "Icon-mac-256.png"
resize 512  "Icon-mac-256@2x.png"
resize 512  "Icon-mac-512.png"
resize 1024 "Icon-mac-512@2x.png"
# Icon-1024.png is the master; no copy needed.

echo "Done. Open Xcode → Assets → AppIcon to preview."
