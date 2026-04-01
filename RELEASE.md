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

```bash
export UPLOAD_TO_APP_STORE_CONNECT=1
export ASC_API_KEY_ID="YOUR_API_KEY_ID"
export ASC_API_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_API_KEY_PATH="/absolute/path/AuthKey_YOUR_API_KEY_ID.p8"
./scripts/publish-appstore.sh
```

The upload step validates each package with `xcrun altool` and then uploads it only when all required API key variables are set.

## Version Source

Release scripts read the version from the Xcode build settings generated from `project.yml`:

1. `MARKETING_VERSION`
2. `CURRENT_PROJECT_VERSION`
3. `PRODUCT_BUNDLE_IDENTIFIER`

Update versioning in `project.yml` before packaging a release.

## Verification Checklist

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
