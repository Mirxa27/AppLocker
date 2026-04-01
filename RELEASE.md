# Release Process

## Local Unsigned Release

Use this for local verification builds and ad-hoc distribution:

```bash
make test
./scripts/build-release.sh
```

Artifacts are written to `release/`:

1. `AppLocker.app`
2. `AppLocker.xcarchive`
3. `AppLocker-<marketing-version>.dmg`

The script regenerates `AppLocker.xcodeproj` from `project.yml`, archives the real Xcode app, applies an ad-hoc signature, and packages a DMG.

## Signed Release

Use this for Developer ID distribution outside the Mac App Store:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/release-signed.sh
```

If `SIGNING_IDENTITY` is omitted, the script will try to auto-detect the first `Developer ID Application` identity in the login keychain.

Optional notarization environment variables:

```bash
export APPLE_ID="name@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_ASC_PASSWORD="app-specific-password"
./scripts/release-signed.sh
```

Signed artifacts are written to `release/signed/`.

## App Store Release

Use this to archive and export the App Store deliverables for both platforms:

```bash
make test
make publish-appstore
```

The script writes its artifacts to `dist/publish/`:

1. `AppLockerCompanion.xcarchive`
2. `ios-appstore/AppLockerCompanion.ipa`
3. `AppLocker-mac-appstore.xcarchive`
4. `mac-appstore/AppLocker.pkg`
5. `ExportOptions-iOS-AppStore.plist`
6. `ExportOptions-mac-AppStore.plist`

The App Store script:

1. Regenerates `AppLocker.xcodeproj` from `project.yml`
2. Detects the local signing team from installed identities unless `APPLE_TEAM_ID` or `DEVELOPMENT_TEAM` is set
3. Archives the iOS and macOS targets with automatic signing and provisioning updates enabled
4. Exports a signed `.ipa` for iOS and `.pkg` for macOS using `app-store-connect` export options

To export only one platform:

```bash
PLATFORMS=ios ./scripts/publish-appstore.sh
PLATFORMS=macos ./scripts/publish-appstore.sh
```

To upload the exported artifacts directly to App Store Connect after export:

**Option A — App Store Connect API key (recommended for CI):**

```bash
export UPLOAD_TO_APP_STORE_CONNECT=1
export ASC_API_KEY_ID="YOUR_API_KEY_ID"
export ASC_API_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_API_KEY_PATH="/absolute/path/AuthKey_YOUR_API_KEY_ID.p8"
./scripts/publish-appstore.sh
```

**Option B — Apple ID and app-specific password** (when API key variables are not set):

```bash
export UPLOAD_TO_APP_STORE_CONNECT=1
export APPLE_ID="you@example.com"
export APPLE_ASC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./scripts/publish-appstore.sh
```

Use an [app-specific password](https://support.apple.com/en-us/102654) from appleid.apple.com, not your normal Apple ID password.

The upload step validates each package with `xcrun altool` and then uploads when either the API key trio **or** `APPLE_ID` + `APPLE_ASC_PASSWORD` is set.

## Version Source

Release scripts read the version from the Xcode build settings generated from `project.yml`:

1. `MARKETING_VERSION`
2. `CURRENT_PROJECT_VERSION`
3. `PRODUCT_BUNDLE_IDENTIFIER`

Update versioning in `project.yml` before packaging a release.

## App Store Connect — macOS resubmission (common rejections)

If review cites **2.1.0 (App Completeness)**, **2.3.3 (Accurate Metadata)**, or **2.4.5 (Hardware Compatibility)**:

1. **Entitlements must not be empty.** A corrupted `SupportingFiles/macOS/AppLocker.entitlements` (only `<dict/>`) breaks sandboxing, iCloud, and camera usage—often leading to crashes or “incomplete” behavior in review. Run `make verify-entitlements` before every archive; restore with `git checkout HEAD -- SupportingFiles/macOS/AppLocker.entitlements` if needed.
2. **Metadata (2.3.3):** Upload enough Mac screenshots (up to 10) that match the **current** UI. Use `./scripts/capture-mac-appstore-screenshots.sh` per shot; set `APPLOCKER_SCREENSHOT_SIZE` (e.g. `1280x800`, `1440x900`, or `2560x1600`) so sizes match [App Store Connect requirements](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications). Show real flows (dashboard, locked apps, settings)—not placeholders.
3. **Review notes:** If the app needs Accessibility permission or a passcode before use, explain the steps in App Review Information so testers can enable features without guessing.
4. **Hardware (2.4.5):** Release builds are archived for standard macOS architectures via Xcode; test on both Apple Silicon and Intel if possible. If the app is Apple Silicon–only, say so in the description and review notes (otherwise ensure a universal or separate Intel build per your App Store plan).

`scripts/publish-appstore.sh` runs `verify-entitlements` automatically before building.

## Verification Checklist

- `make verify-entitlements` passes
- App icons: after editing `Icon-1024.png`, run `./scripts/sync-app-icons-from-1024.sh`
- `make test` passes
- `make build-macos` passes
- `make build-ios` passes on a machine with a compatible iOS simulator runtime
- `make publish-appstore` exports the `.ipa` and `.pkg` on a machine with valid App Store signing assets
- Accessibility permissions flow is verified on macOS
- Release scripts produce `.app`, `.xcarchive`, and `.dmg`
- Signed release passes `codesign --verify --deep --strict`
- Signed release passes `spctl --assess --type execute`
- Notarization completes if distribution outside your own machines is required

## Troubleshooting

### Build the generated project explicitly

```bash
xcodegen generate --spec project.yml
xcodebuild -project AppLocker.xcodeproj -scheme AppLocker -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO archive
```

### Reset a broken local release directory

```bash
rm -rf release
make clean
```

### Check signing identities

```bash
security find-identity -v -p codesigning
```

### Validate a notarized DMG

```bash
xcrun stapler validate release/signed/AppLocker-<marketing-version>.dmg
```
