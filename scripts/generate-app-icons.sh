#!/usr/bin/env bash
# Regenerates AppIcon PNGs from a single square master image (1024+ px recommended).
# Usage: ./scripts/generate-app-icons.sh /path/to/master.png
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="${1:-}"
OUT="$ROOT/Sources/AppLocker/Assets.xcassets/AppIcon.appiconset"
if [[ -z "$MASTER" || ! -f "$MASTER" ]]; then
  echo "Usage: $0 <master.png>" >&2
  exit 1
fi
mkdir -p "$OUT"
sips -z 40 40 "$MASTER" --out "$OUT/Icon-20@2x.png"
sips -z 60 60 "$MASTER" --out "$OUT/Icon-20@3x.png"
sips -z 58 58 "$MASTER" --out "$OUT/Icon-29@2x.png"
sips -z 87 87 "$MASTER" --out "$OUT/Icon-29@3x.png"
sips -z 80 80 "$MASTER" --out "$OUT/Icon-40@2x.png"
sips -z 120 120 "$MASTER" --out "$OUT/Icon-40@3x.png"
sips -z 120 120 "$MASTER" --out "$OUT/Icon-60@2x.png"
sips -z 180 180 "$MASTER" --out "$OUT/Icon-60@3x.png"
sips -z 152 152 "$MASTER" --out "$OUT/Icon-76@2x.png"
sips -z 167 167 "$MASTER" --out "$OUT/Icon-83.5@2x.png"
sips -z 20 20 "$MASTER" --out "$OUT/Icon-20.png"
sips -z 29 29 "$MASTER" --out "$OUT/Icon-29.png"
sips -z 40 40 "$MASTER" --out "$OUT/Icon-40.png"
sips -z 16 16 "$MASTER" --out "$OUT/Icon-mac-16.png"
sips -z 32 32 "$MASTER" --out "$OUT/Icon-mac-16@2x.png"
sips -z 32 32 "$MASTER" --out "$OUT/Icon-mac-32.png"
sips -z 64 64 "$MASTER" --out "$OUT/Icon-mac-32@2x.png"
sips -z 128 128 "$MASTER" --out "$OUT/Icon-mac-128.png"
sips -z 256 256 "$MASTER" --out "$OUT/Icon-mac-128@2x.png"
sips -z 256 256 "$MASTER" --out "$OUT/Icon-mac-256.png"
sips -z 512 512 "$MASTER" --out "$OUT/Icon-mac-256@2x.png"
sips -z 512 512 "$MASTER" --out "$OUT/Icon-mac-512.png"
sips -z 1024 1024 "$MASTER" --out "$OUT/Icon-mac-512@2x.png"
sips -z 1024 1024 "$MASTER" --out "$OUT/Icon-1024.png"
echo "Wrote icons to $OUT"
