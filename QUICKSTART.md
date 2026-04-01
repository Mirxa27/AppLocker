# Quick Start

## Daily Commands

```bash
# Regenerate the shared Xcode project
make generate-project

# Build the macOS app
make build-macos

# Run unit tests
make test

# Package an unsigned local release
make release

# Export App Store artifacts (.ipa + .pkg)
make publish-appstore
```

## iOS Companion Build

```bash
make build-ios
```

The iOS build uses the local iPhone Simulator SDK. If Xcode reports that no compatible simulator runtime is available for the active SDK, install the matching iOS runtime from Xcode Components and rerun the command.

## Release Artifacts

`make release` produces:

1. `release/AppLocker.app`
2. `release/AppLocker.xcarchive`
3. `release/AppLocker-<marketing-version>.dmg`

`make release-signed` produces the same artifacts in `release/signed/` and applies a Developer ID signature. If `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_ASC_PASSWORD` are set, the DMG is notarized and stapled.

`make publish-appstore` produces:

1. `dist/publish/AppLockerCompanion.xcarchive`
2. `dist/publish/ios-appstore/AppLockerCompanion.ipa`
3. `dist/publish/AppLocker-mac-appstore.xcarchive`
4. `dist/publish/mac-appstore/AppLocker.pkg`

## Troubleshooting

### Clean everything

```bash
make clean
```

### Verify the generated project

```bash
xcodegen generate --spec project.yml
xcodebuild -project AppLocker.xcodeproj -list
```

### Verify signatures on a packaged build

```bash
codesign --verify --deep --strict release/AppLocker.app
spctl --assess --type execute release/AppLocker.app
```
