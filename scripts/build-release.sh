#!/bin/bash
# Build and package AppLocker for release

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="AppLocker"
BUNDLE_ID="com.applocker.AppLocker"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" AppLocker.app/Contents/Info.plist 2>/dev/null || echo "3.0")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" AppLocker.app/Contents/Info.plist 2>/dev/null || echo "3")

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_DIR="$PROJECT_DIR/release"
APP_BUNDLE="$PROJECT_DIR/AppLocker.app"

echo -e "${GREEN}🚀 Building $APP_NAME v$VERSION (Build $BUILD_NUMBER)${NC}"
echo ""

# Clean previous builds
echo -e "${YELLOW}📁 Cleaning previous builds...${NC}"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Build for release
echo -e "${YELLOW}🔨 Building release binary...${NC}"
cd "$PROJECT_DIR"
swift build -c release

if [ ! -f "$BUILD_DIR/release/AppLocker" ]; then
    echo -e "${RED}❌ Build failed - binary not found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build successful${NC}"
echo ""

# Update app bundle
echo -e "${YELLOW}📦 Packaging app bundle...${NC}"
cp "$BUILD_DIR/release/AppLocker" "$APP_BUNDLE/Contents/MacOS/AppLocker"

# Sign the app
echo -e "${YELLOW}🔏 Signing app bundle...${NC}"
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/dist/entitlements.plist" \
    --options runtime \
    "$APP_BUNDLE" 2>&1 | grep -v "replacing existing signature" || true

# Verify signature
echo -e "${YELLOW}✓ Verifying signature...${NC}"
if codesign --verify --deep --strict "$APP_BUNDLE" 2>&1; then
    echo -e "${GREEN}✅ Signature valid${NC}"
else
    echo -e "${YELLOW}⚠️  Signature verification had issues (may need Developer ID for distribution)${NC}"
fi

# Copy to release directory
echo -e "${YELLOW}📋 Copying to release directory...${NC}"
cp -R "$APP_BUNDLE" "$RELEASE_DIR/"

# Create DMG
echo -e "${YELLOW}💿 Creating DMG installer...${NC}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"

# Create temporary directory for DMG contents
TMP_DIR=$(mktemp -d)
cp -R "$APP_BUNDLE" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" > /dev/null 2>&1

# Clean up temp directory
rm -rf "$TMP_DIR"

if [ -f "$DMG_PATH" ]; then
    echo -e "${GREEN}✅ DMG created: $DMG_NAME${NC}"
else
    echo -e "${RED}❌ DMG creation failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 Release build complete!${NC}"
echo ""
echo "📦 Release artifacts:"
echo "   App Bundle: $RELEASE_DIR/AppLocker.app ($(du -sh "$RELEASE_DIR/AppLocker.app" | cut -f1))"
echo "   DMG:        $RELEASE_DIR/$DMG_NAME ($(du -sh "$DMG_PATH" | cut -f1))"
echo ""
echo "💡 To distribute:"
echo "   - Upload the DMG to GitHub Releases"
echo "   - Or run: gh release create v$VERSION $DMG_PATH --title 'AppLocker v$VERSION' --notes 'Release notes here'"
