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
RELEASE_DIR="$REPO/release"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
ENTITLEMENTS="$REPO/SupportingFiles/macOS/AppLocker.entitlements"

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
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ] || [ -z "$BUNDLE_ID" ]; then
    echo -e "${RED}Unable to resolve build settings for ${SCHEME}.${NC}"
    exit 1
fi

echo -e "${GREEN}Preparing ${APP_NAME} ${VERSION} (${BUILD_NUMBER})${NC}"
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

echo -e "${YELLOW}Applying ad-hoc signature for local distribution...${NC}"
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_PATH"
else
    codesign --force --deep --sign - "$APP_PATH"
fi

codesign --verify --deep --strict "$APP_PATH"

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

echo -e "${GREEN}Release artifacts ready.${NC}"
echo "App: $RELEASE_DIR/$APP_NAME.app"
echo "DMG: $DMG_PATH"
