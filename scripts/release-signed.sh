#!/bin/bash
# Full notarized release build for AppLocker
# Requires: Developer ID Application certificate in keychain
# Usage: VERSION=3.1 ./scripts/release-signed.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-3.1}"
BUNDLE_ID="com.applocker.AppLocker"
APP="$REPO/AppLocker.app"
ENTITLEMENTS="$REPO/dist/entitlements.plist"
DMG_OUT="$REPO/dist/AppLocker-$VERSION.dmg"

# Apple notarization credentials (set as env vars or edit here)
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_ASC_PASSWORD="${APPLE_ASC_PASSWORD:-}"  # App-specific password

# Find Developer ID Application cert automatically
DEV_ID_CERT=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 \
  | sed 's/.*"\(.*\)"/\1/')

if [ -z "$DEV_ID_CERT" ]; then
  echo -e "${RED}❌ No 'Developer ID Application' certificate found in keychain.${NC}"
  echo ""
  echo "To get one:"
  echo "  1. Go to: https://developer.apple.com/account/resources/certificates/add"
  echo "  2. Select: Developer ID Application"
  echo "  3. Create CSR via Keychain Access → Certificate Assistant → Request from CA"
  echo "  4. Upload CSR, download the .cer file"
  echo "  5. Double-click the .cer to install it in your keychain"
  echo "  6. Re-run this script"
  exit 1
fi

echo -e "${GREEN}✅ Using cert: $DEV_ID_CERT${NC}"

echo -e "${YELLOW}==> Killing any running AppLocker instance${NC}"
pkill -x AppLocker 2>/dev/null || true; sleep 0.5

echo -e "${YELLOW}==> Building release binary${NC}"
cd "$REPO"
swift build -c release
cp .build/release/AppLocker "$APP/Contents/MacOS/AppLocker"
chmod +x "$APP/Contents/MacOS/AppLocker"

echo -e "${YELLOW}==> Setting version $VERSION${NC}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

echo -e "${YELLOW}==> Signing with Developer ID (hardened runtime)${NC}"
codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --deep \
  --sign "$DEV_ID_CERT" \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  --timestamp \
  "$APP"

codesign --verify --deep --strict "$APP"
echo -e "${GREEN}   Signature verified${NC}"

echo -e "${YELLOW}==> Building DMG${NC}"
TMP=$(mktemp -d)
cp -R "$APP" "$TMP/"
ln -s /Applications "$TMP/Applications"
hdiutil create -volname "AppLocker $VERSION" \
  -srcfolder "$TMP" -ov -format UDZO -fs HFS+ "$DMG_OUT"
rm -rf "$TMP"

echo -e "${GREEN}   DMG: $DMG_OUT ($(du -sh "$DMG_OUT" | cut -f1))${NC}"

# Notarize if credentials provided
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_ASC_PASSWORD" ]; then
  echo -e "${YELLOW}==> Submitting to Apple notarization${NC}"
  SUBMISSION=$(xcrun notarytool submit "$DMG_OUT" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_ASC_PASSWORD" \
    --wait --output-format json 2>&1)

  STATUS=$(echo "$SUBMISSION" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")

  if [ "$STATUS" = "Accepted" ]; then
    echo -e "${GREEN}✅ Notarization accepted${NC}"
    echo -e "${YELLOW}==> Stapling ticket to DMG${NC}"
    xcrun stapler staple "$DMG_OUT"
    xcrun stapler validate "$DMG_OUT" && echo -e "${GREEN}✅ Stapled and validated${NC}"
  else
    echo -e "${RED}❌ Notarization status: $STATUS${NC}"
    SUBID=$(echo "$SUBMISSION" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")
    [ -n "$SUBID" ] && xcrun notarytool log "$SUBID" \
      --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_ASC_PASSWORD" 2>&1
    exit 1
  fi
else
  echo -e "${YELLOW}⚠️  Notarization skipped (set APPLE_ID, APPLE_TEAM_ID, APPLE_ASC_PASSWORD to notarize)${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Done! Release artifact: $DMG_OUT${NC}"
