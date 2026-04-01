#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$REPO/project.yml"
PROJECT_FILE="$REPO/AppLocker.xcodeproj"
PUBLISH_DIR="$REPO/dist/publish"
IOS_SCHEME="AppLockerCompanion"
MAC_SCHEME="AppLocker"
IOS_ARCHIVE_PATH="$PUBLISH_DIR/${IOS_SCHEME}.xcarchive"
MAC_ARCHIVE_PATH="$PUBLISH_DIR/${MAC_SCHEME}-mac-appstore.xcarchive"
IOS_EXPORT_PATH="$PUBLISH_DIR/ios-appstore"
MAC_EXPORT_PATH="$PUBLISH_DIR/mac-appstore"
IOS_EXPORT_OPTIONS="$PUBLISH_DIR/ExportOptions-iOS-AppStore.plist"
MAC_EXPORT_OPTIONS="$PUBLISH_DIR/ExportOptions-mac-AppStore.plist"
TMP_DIR="$PUBLISH_DIR/tmp"

PLATFORMS="${PLATFORMS:-all}"                # all | ios | macos
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
UPLOAD_TO_APP_STORE_CONNECT="${UPLOAD_TO_APP_STORE_CONNECT:-0}"
ASC_API_KEY_ID="${ASC_API_KEY_ID:-${ASC_API_KEY:-}}"
ASC_API_ISSUER_ID="${ASC_API_ISSUER_ID:-${ASC_API_ISSUER:-}}"
ASC_API_KEY_PATH="${ASC_API_KEY_PATH:-}"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}Missing required tool: $1${NC}"
        exit 1
    fi
}

read_build_setting() {
    local scheme="$1"
    local key="$2"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$scheme" \
        -configuration Release \
        -showBuildSettings 2>/dev/null |
        awk -F ' = ' -v key="$key" '$1 ~ (" " key "$") { print $2; exit }'
}

detect_team_id() {
    security find-identity -v -p codesigning 2>/dev/null |
        sed -n \
            -e 's/.*Apple Distribution:.*(\([A-Z0-9]\{10\}\)).*/\1/p' \
            -e 's/.*Developer ID Application:.*(\([A-Z0-9]\{10\}\)).*/\1/p' \
            -e 's/.*Apple Development:.*(\([A-Z0-9]\{10\}\)).*/\1/p' |
        head -1
}

export_signing_style() {
    printf '%s' "$CODE_SIGN_STYLE" | tr '[:upper:]' '[:lower:]'
}

has_mac_installer_certificate() {
    security find-identity -v -p basic 2>/dev/null |
        grep -Eq '"(Mac Installer Distribution|3rd Party Mac Developer Installer):'
}

extract_codesign_entitlements() {
    local app_path="$1"
    local output_path="$2"
    codesign -d --entitlements - "$app_path" >"$output_path" 2>/dev/null
}

extract_mobileprovision_entitlements() {
    local profile_path="$1"
    local output_path="$2"
    local decoded_path="$TMP_DIR/profile-decoded.plist"
    security cms -D -i "$profile_path" >"$decoded_path"
    /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$decoded_path" >"$output_path"
}

# PlistBuddy interprets dots in entitlement keys as nested paths; use plistlib for flat com.apple.* keys.
plist_has_key() {
    local plist_path="$1"
    local key="$2"
    if [ ! -f "$plist_path" ] || [ ! -s "$plist_path" ]; then
        return 1
    fi
    PLIST_PATH="$plist_path" ENTITLEMENT_KEY="$key" python3 - <<'PY'
import os, plistlib, sys
path = os.environ["PLIST_PATH"]
key = os.environ["ENTITLEMENT_KEY"]
try:
    with open(path, "rb") as f:
        data = plistlib.load(f)
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(data, dict) and key in data else 1)
PY
}

require_signed_entitlement() {
    local signed_plist="$1"
    local profile_plist="$2"
    local key="$3"
    local missing_message="$4"

    if plist_has_key "$signed_plist" "$key"; then
        return 0
    fi

    if [ -n "$profile_plist" ] && [ -f "$profile_plist" ] && plist_has_key "$profile_plist" "$key"; then
        echo -e "${RED}${missing_message}${NC}"
        echo "Provisioning allows $key, but the signed archive does not contain it. Check the checked-in entitlements file and target signing settings."
        exit 1
    fi

    echo -e "${RED}${missing_message}${NC}"
    if [ -n "$profile_plist" ] && [ -f "$profile_plist" ]; then
        echo "The provisioning profile also lacks $key. Enable the capability for the App ID, regenerate the provisioning profile, and rearchive."
    fi
    exit 1
}

# Entitlement must appear in the provisioning profile plist (used for App Store IPA where codesign --entitlements omits merged keys).
require_entitlement_in_plist() {
    local plist_path="$1"
    local key="$2"
    local missing_message="$3"
    if plist_has_key "$plist_path" "$key"; then
        return 0
    fi
    echo -e "${RED}${missing_message}${NC}"
    exit 1
}

# Verify the **exported** IPA using embedded provisioning profile entitlements.
# `codesign -d --entitlements` often omits iCloud/Family keys for App Store builds even when the app is correctly provisioned.
verify_ios_exported_ipa_entitlements() {
    local ipa_path="$1"
    local unzip_dir="$TMP_DIR/ipa-entitlements-check"
    rm -rf "$unzip_dir"
    mkdir -p "$unzip_dir"
    unzip -q "$ipa_path" -d "$unzip_dir"

    local app_path
    app_path=$(find "$unzip_dir/Payload" -maxdepth 1 -name "*.app" -print -quit)
    if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        echo -e "${RED}Could not find .app inside IPA at ${ipa_path}.${NC}"
        exit 1
    fi

    local profile_plist="$TMP_DIR/ios-profile-entitlements.plist"
    extract_mobileprovision_entitlements "$app_path/embedded.mobileprovision" "$profile_plist"

    require_entitlement_in_plist "$profile_plist" "com.apple.developer.icloud-container-identifiers" \
        "The App Store provisioning profile is missing iCloud container entitlements."
    require_entitlement_in_plist "$profile_plist" "com.apple.developer.ubiquity-container-identifiers" \
        "The App Store provisioning profile is missing ubiquity container entitlements."
    require_entitlement_in_plist "$profile_plist" "com.apple.developer.icloud-services" \
        "The App Store provisioning profile is missing CloudKit service entitlements."
    require_entitlement_in_plist "$profile_plist" "com.apple.developer.ubiquity-kvstore-identifier" \
        "The App Store provisioning profile is missing the shared iCloud key-value store entitlement."

    if plist_has_key "$profile_plist" "com.apple.developer.family-controls"; then
        require_entitlement_in_plist "$profile_plist" "com.apple.developer.family-controls.app-and-website-usage" \
            "Family Controls is enabled but usage-data entitlement is missing from the provisioning profile."
    else
        echo -e "${YELLOW}Note: Family Controls entitlements are not present on this App Store provisioning profile. Screen Time features require them on the App ID + a new profile.${NC}"
    fi
}

verify_macos_archive_entitlements() {
    local app_path="$MAC_ARCHIVE_PATH/Products/Applications/${MAC_SCHEME}.app"
    local signed_plist="$TMP_DIR/macos-signed-entitlements.plist"

    extract_codesign_entitlements "$app_path" "$signed_plist"

    require_signed_entitlement "$signed_plist" "" "com.apple.security.app-sandbox" \
        "The macOS archive is not sandboxed."
    require_signed_entitlement "$signed_plist" "" "com.apple.security.network.client" \
        "The macOS archive is missing outbound-network entitlement."
    require_signed_entitlement "$signed_plist" "" "com.apple.security.device.camera" \
        "The macOS archive is missing camera entitlement."
    require_signed_entitlement "$signed_plist" "" "com.apple.security.files.user-selected.read-write" \
        "The macOS archive is missing user-selected file access entitlement."
    require_signed_entitlement "$signed_plist" "" "com.apple.developer.icloud-container-identifiers" \
        "The macOS archive is missing iCloud container entitlements."
    require_signed_entitlement "$signed_plist" "" "com.apple.developer.ubiquity-container-identifiers" \
        "The macOS archive is missing ubiquity container entitlements."
    require_signed_entitlement "$signed_plist" "" "com.apple.developer.icloud-services" \
        "The macOS archive is missing CloudKit service entitlements."
    require_signed_entitlement "$signed_plist" "" "com.apple.developer.ubiquity-kvstore-identifier" \
        "The macOS archive is missing the shared iCloud key-value store entitlement."
}

write_ios_export_options() {
    cat >"$IOS_EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>$(export_signing_style)</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF
}

write_mac_export_options() {
    cat >"$MAC_EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>$(export_signing_style)</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF
}

upload_package() {
    local package_path="$1"
    local label="$2"

    if [ "$UPLOAD_TO_APP_STORE_CONNECT" != "1" ]; then
        return 0
    fi

    # Prefer App Store Connect API key; fall back to Apple ID + app-specific password (not your Apple ID login password).
    local -a auth_args
    if [ -n "${ASC_API_KEY_ID:-}" ] && [ -n "${ASC_API_ISSUER_ID:-}" ] && [ -n "${ASC_API_KEY_PATH:-}" ]; then
        auth_args=(--api-key "$ASC_API_KEY_ID" --api-issuer "$ASC_API_ISSUER_ID" --p8-file-path "$ASC_API_KEY_PATH")
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_ASC_PASSWORD:-}" ]; then
        auth_args=(-u "$APPLE_ID" -p "@env:APPLE_ASC_PASSWORD")
        echo -e "${YELLOW}Using APPLE_ID + APPLE_ASC_PASSWORD (app-specific) for upload. Prefer ASC_API_* API keys for CI.${NC}"
    else
        echo -e "${RED}Upload requested. Set either (ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_KEY_PATH) or (APPLE_ID, APPLE_ASC_PASSWORD).${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Validating ${label} with App Store Connect...${NC}"
    xcrun altool \
        --validate-app "$package_path" \
        "${auth_args[@]}" \
        --output-format json

    echo -e "${YELLOW}Uploading ${label} to App Store Connect...${NC}"
    xcrun altool \
        --upload-package "$package_path" \
        "${auth_args[@]}" \
        --output-format json
}

archive_ios() {
    echo -e "${YELLOW}Archiving iOS App Store build...${NC}"
    rm -rf "$IOS_ARCHIVE_PATH" "$IOS_EXPORT_PATH"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$IOS_SCHEME" \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$IOS_ARCHIVE_PATH" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE="$CODE_SIGN_STYLE" \
        -allowProvisioningUpdates \
        archive

    write_ios_export_options

    echo -e "${YELLOW}Exporting iOS IPA...${NC}"
    xcodebuild \
        -exportArchive \
        -archivePath "$IOS_ARCHIVE_PATH" \
        -exportPath "$IOS_EXPORT_PATH" \
        -exportOptionsPlist "$IOS_EXPORT_OPTIONS" \
        -allowProvisioningUpdates

    local ipa_path="$IOS_EXPORT_PATH/${IOS_SCHEME}.ipa"
    if [ ! -f "$ipa_path" ]; then
        echo -e "${RED}Expected IPA not found at ${ipa_path}.${NC}"
        exit 1
    fi

    verify_ios_exported_ipa_entitlements "$ipa_path"

    upload_package "$ipa_path" "iOS IPA"
}

archive_macos() {
    if ! has_mac_installer_certificate; then
        echo -e "${RED}Missing Mac App Store installer signing certificate.${NC}"
        echo "Install a \"Mac Installer Distribution\" certificate (or legacy \"3rd Party Mac Developer Installer\") in the active keychain before exporting AppLocker.pkg."
        exit 1
    fi

    echo -e "${YELLOW}Archiving macOS App Store build...${NC}"
    rm -rf "$MAC_ARCHIVE_PATH" "$MAC_EXPORT_PATH"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$MAC_SCHEME" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$MAC_ARCHIVE_PATH" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE="$CODE_SIGN_STYLE" \
        -allowProvisioningUpdates \
        archive

    verify_macos_archive_entitlements

    write_mac_export_options

    echo -e "${YELLOW}Exporting macOS App Store package...${NC}"
    xcodebuild \
        -exportArchive \
        -archivePath "$MAC_ARCHIVE_PATH" \
        -exportPath "$MAC_EXPORT_PATH" \
        -exportOptionsPlist "$MAC_EXPORT_OPTIONS" \
        -allowProvisioningUpdates

    local pkg_path="$MAC_EXPORT_PATH/${MAC_SCHEME}.pkg"
    if [ ! -f "$pkg_path" ]; then
        echo -e "${RED}Expected PKG not found at ${pkg_path}.${NC}"
        exit 1
    fi

    upload_package "$pkg_path" "macOS PKG"
}

require_tool xcodegen
require_tool xcodebuild
require_tool xcrun
require_tool security
require_tool unzip
if [ "$UPLOAD_TO_APP_STORE_CONNECT" = "1" ]; then
    xcrun --find altool >/dev/null 2>&1 || {
        echo -e "${RED}Missing required tool: altool${NC}"
        exit 1
    }
fi

TEAM_ID="${APPLE_TEAM_ID:-${DEVELOPMENT_TEAM:-$(detect_team_id)}}"
if [ -z "$TEAM_ID" ]; then
    echo -e "${RED}No signing team detected. Set APPLE_TEAM_ID or DEVELOPMENT_TEAM.${NC}"
    exit 1
fi

mkdir -p "$PUBLISH_DIR"
mkdir -p "$TMP_DIR"

echo -e "${YELLOW}Generating Xcode project from project.yml...${NC}"
xcodegen generate --spec "$PROJECT_SPEC" >/dev/null

IOS_VERSION="$(read_build_setting "$IOS_SCHEME" MARKETING_VERSION)"
IOS_BUILD="$(read_build_setting "$IOS_SCHEME" CURRENT_PROJECT_VERSION)"
MAC_VERSION="$(read_build_setting "$MAC_SCHEME" MARKETING_VERSION)"
MAC_BUILD="$(read_build_setting "$MAC_SCHEME" CURRENT_PROJECT_VERSION)"

echo -e "${GREEN}Publishing App Store artifacts with team ${TEAM_ID}.${NC}"
echo "Platforms: ${PLATFORMS}"
echo "iOS: ${IOS_VERSION} (${IOS_BUILD})"
echo "macOS: ${MAC_VERSION} (${MAC_BUILD})"

case "$PLATFORMS" in
    all)
        archive_ios
        archive_macos
        ;;
    ios)
        archive_ios
        ;;
    macos)
        archive_macos
        ;;
    *)
        echo -e "${RED}Unsupported PLATFORMS value: ${PLATFORMS}. Use all, ios, or macos.${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}App Store artifacts ready.${NC}"
echo "iOS archive: $IOS_ARCHIVE_PATH"
echo "iOS export:  $IOS_EXPORT_PATH"
echo "macOS archive: $MAC_ARCHIVE_PATH"
echo "macOS export:  $MAC_EXPORT_PATH"
