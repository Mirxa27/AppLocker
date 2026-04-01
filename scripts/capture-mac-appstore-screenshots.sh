#!/usr/bin/env bash
# Builds (if needed) and captures 1440×900 PNGs for Mac App Store using the app's
# built-in hook (see MacAppLockerApp.maybeCaptureWindowForAppStore).
#
# Usage:
#   ./scripts/capture-mac-appstore-screenshots.sh [output-dir] [filename.png]
#
# Environment:
#   APP — path to AppLocker.app bundle (skips build if set and exists)
#   APPLOCKER_SCREENSHOT_SIZE — width x height (default 1440x900). Also 1280x800, 2560x1600, etc.
#   APPLOCKER_SCREENSHOT_WIDTH / HEIGHT — override numeric size if SIZE unset
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/screenshots-appstore}"
mkdir -p "$OUT"

find_built_app() {
  local dd="$1"
  local p
  # Preferred: standard layout inside -derivedDataPath
  p="$dd/Build/Products/Debug/AppLocker.app"
  if [[ -d "$p" ]]; then
    echo "$p"
    return 0
  fi
  # Any Products/**/AppLocker.app under this DerivedData
  p=$(find "$dd" -name AppLocker.app -type d 2>/dev/null | head -1 || true)
  if [[ -n "$p" ]]; then
    echo "$p"
    return 0
  fi
  # Xcode sometimes writes products to /tmp/Build even when -derivedDataPath is set
  p="/tmp/Build/Products/Debug/AppLocker.app"
  if [[ -d "$p" ]]; then
    echo "$p"
    return 0
  fi
  return 1
}

if [[ -n "${APP:-}" ]] && [[ -d "$APP" ]]; then
  APP_BUNDLE="$APP"
else
  echo "Building Debug AppLocker (unsigned)…"
  DD="$ROOT/build/DerivedData-screenshots"
  rm -rf "$DD"
  (cd "$ROOT" && xcodegen generate --spec project.yml >/dev/null)
  LOG=$(mktemp)
  # Force products/intermediates under -derivedDataPath. Without SYMROOT/OBJROOT, some Xcode
  # configurations (custom build locations) place Debug output in /tmp/Build instead.
  if ! xcodebuild \
    -project "$ROOT/AppLocker.xcodeproj" \
    -scheme AppLocker \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$DD" \
    SYMROOT="$DD/Build/Products" \
    OBJROOT="$DD/Build/Intermediates.noindex" \
    -quiet \
    build >"$LOG" 2>&1; then
    echo "xcodebuild failed:" >&2
    cat "$LOG" >&2
    rm -f "$LOG"
    exit 1
  fi
  rm -f "$LOG"
  APP_BUNDLE="$(find_built_app "$DD")" || true
fi

if [[ -z "${APP_BUNDLE:-}" ]] || [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Could not find AppLocker.app after build (checked DerivedData and /tmp/Build)." >&2
  exit 1
fi

echo "Using app bundle: $APP_BUNDLE"

BIN="$APP_BUNDLE/Contents/MacOS/AppLocker"
if [[ ! -x "$BIN" ]]; then
  echo "Could not find executable at: $BIN" >&2
  exit 1
fi

NAME="${2:-01-main-1440x900.png}"
export APPLOCKER_CAPTURE_SCREENSHOT=1
export APPLOCKER_SCREENSHOT_PATH="$OUT/$NAME"
export APPLOCKER_SCREENSHOT_DELAY="${APPLOCKER_SCREENSHOT_DELAY:-4}"
export APPLOCKER_SCREENSHOT_SIZE="${APPLOCKER_SCREENSHOT_SIZE:-1440x900}"

echo "Writing $APPLOCKER_SCREENSHOT_PATH (delay ${APPLOCKER_SCREENSHOT_DELAY}s)…"
"$BIN"
echo "Done."
