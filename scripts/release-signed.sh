#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$REPO/project.yml"
PROJECT_FILE="$REPO/AppLocker.xcodeproj"
SCHEME="AppLocker"
APP_NAME="AppLocker"
ENTITLEMENTS="$REPO/SupportingFiles/macOS/AppLocker.entitlements"
RELEASE_DIR="$REPO/release/signed"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"

APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_ASC_PASSWORD="${APPLE_ASC_PASSWORD:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}Missing required tool: $1${NC}"
        exit 1
    fi
}

read_build_setting() {
    local key="$1"
    printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' -v key="$key" '$1 ~ (" " key "$") { print $2; exit }'
}

require_tool xcodebuild
require_tool xcodegen
require_tool codesign
require_tool hdiutil
require_tool xcrun
require_tool security

echo -e "${YELLOW}Generating Xcode project from project.yml...${NC}"
xcodegen generate --spec "$PROJECT_SPEC" >/dev/null

BUILD_SETTINGS="$(xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -showBuildSettings)"

VERSION="${VERSION:-$(read_build_setting MARKETING_VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(read_build_setting CURRENT_PROJECT_VERSION)}"
BUNDLE_ID="$(read_build_setting PRODUCT_BUNDLE_IDENTIFIER)"
DMG_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}.dmg"

if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\\(Developer ID Application:.*\\)"/\\1/p' | head -1)"
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    echo -e "${RED}No Developer ID Application signing identity found.${NC}"
    exit 1
fi

echo -e "${GREEN}Signing ${APP_NAME} ${VERSION} (${BUILD_NUMBER}) with ${SIGNING_IDENTITY}${NC}"
echo "Bundle ID: $BUNDLE_ID"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo -e "${YELLOW}Archiving release build...${NC}"
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -archivePath "$ARCHIVE_PATH" \
    SKIP_INSTALL=NO \
    CODE_SIGNING_ALLOWED=NO \
    archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Archive succeeded but ${APP_PATH} is missing.${NC}"
    exit 1
fi

codesign --remove-signature "$APP_PATH" 2>/dev/null || true
codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute "$APP_PATH"

cp -R "$APP_PATH" "$RELEASE_DIR/"

echo -e "${YELLOW}Building DMG...${NC}"
TMP_DIR="$(mktemp -d)"
cp -R "$APP_PATH" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
rm -rf "$TMP_DIR"

if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_ASC_PASSWORD" ]; then
    echo -e "${YELLOW}Submitting DMG for notarization...${NC}"
    xcrun notarytool submit \
        "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_ASC_PASSWORD" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
else
    echo -e "${YELLOW}Notarization skipped. Set APPLE_ID, APPLE_TEAM_ID, and APPLE_ASC_PASSWORD to notarize.${NC}"
fi

echo -e "${GREEN}Signed release artifacts ready.${NC}"
echo "App: $RELEASE_DIR/$APP_NAME.app"
echo "DMG: $DMG_PATH"
