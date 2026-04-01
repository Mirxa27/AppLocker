# Changelog

All notable changes to AppLocker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- SwiftPM unit test coverage for schedule evaluation, legacy schedule decoding, CryptoKit encryption, tamper rejection, and PBKDF2 derivation
- Explicit shared Xcode schemes generated from `project.yml` for both the macOS app and the iOS companion
- Reproducible App Store archive/export automation for the iOS IPA and macOS PKG via `scripts/publish-appstore.sh`

### Changed

- Schedule windows now support two real policies: block during the selected window or allow only during the selected window
- macOS schedule editing UI now exposes the active schedule policy instead of silently treating every schedule as a block window
- Release automation now archives the real Xcode app bundle instead of rebuilding a hand-rolled app from `swift build`
- Quick-start and release documentation now match the generated Xcode workflow and current release scripts
- iOS file vault keys are now rewrapped during PIN changes so encrypted files survive credential rotation

### Fixed

- Filled the missing app icon variants referenced by `AppIcon.appiconset`
- Removed the unfinished allow-list shortcut in schedule template application
- Exported backup metadata now uses the current app version instead of a hardcoded `3.0`
- iOS file locker resets now delete encrypted payloads before clearing the in-memory metadata

## [3.7.0] - 2026-04-01

### Added

- `docs/ARCHITECTURE.md` describing targets, data flow, storage, and release process
- `scripts/generate-app-icons.sh` to regenerate App Icon PNGs from a master image
- `CloudKitManager.handleRemoteNotification` and unit tests; APNs registration when notifications are authorized
- `Tests/AppLockerTests/CloudKitManagerTests.swift`

### Changed

- README security section aligned with PBKDF2 passcode storage (v1 migration path documented)
- Remote “Lock All” from iOS companion: clears temporary unlocks, re-checks running apps, locks screen (⌃⌘Q with screen-saver fallback) instead of putting the Mac to sleep
- macOS and iOS register for remote notifications and handle CloudKit-related pushes; macOS runs `setupPushSubscriptions` on launch

### Fixed

- Restored complete App Icon PNG set for iOS and macOS asset catalog entries

## [3.6.0] - 2026-03-02

### Changed

- **Restored Original App Icons** - Reverted to the classic icon set with standard naming convention
- Cleaned up iPad-specific icon duplicates for consistent asset management

### Fixed

- Icon asset catalog structure simplified for better maintainability

## [3.1.0] - 2026-03-02

### Added

- **Focus Mode** - Pomodoro-style distraction-free work sessions with profiles (Deep Work, Study, Meeting)
- **App Usage Quotas** - Daily time limits for locked apps with warnings and optional termination
- **Smart Schedule Templates** - 8 pre-built schedule templates (Work Hours, Evening Wind Down, Study Time, etc.)
- Enhanced sidebar with new Productivity section

### Fixed

- Fixed syntax errors in AuthenticationManager.swift (SecRandomCopyBytes buffer parameter)
- Fixed syntax errors in MacContentView.swift (running apps filter predicate)
- Fixed syntax errors in IntruderManager.swift (file filtering and sorting)
- Fixed GitHub Actions workflow to properly create app bundle structure and DMG
- Fixed build-release.sh to create app bundle structure from scratch if needed
- Added missing entitlements.plist for code signing
- Updated actions/cache to v4 and softprops/action-gh-release to v2
- Fixed release job to run on ubuntu-latest (no macOS needed for artifact upload)
- Fixed Makefile version target to not depend on pre-existing app bundle
- Fixed Package.swift to exclude Assets.xcassets warning

### Improved

- Release workflow now creates versioned DMG files (e.g. AppLocker-3.1.dmg)
- DMG includes Applications symlink for drag-and-drop installation
- Build workflow generates Info.plist with version from git tag
- Added proper permissions for GitHub Release creation
- Enhanced app structure with organized feature folders

## [3.0.0] - 2025-02-11

### Added

- Initial release of AppLocker v3.0
- Passcode protection with SHA-256 hashing and random salt
- Biometric authentication (Touch ID/Face ID) support
- App blocking engine with workspace monitoring
- Schedule-based locking (time windows, days of week)
- Usage statistics tracking (blocks, unlocks, failed attempts)
- App categories for batch management
- Configurable unlock duration (30s to 1 hour)
- Auto-lock on screen sleep/lid close
- Escalating lockout protection after failed attempts
- Passcode change functionality
- Export/import configuration (JSON format)
- Persistent activity log (survives restarts)
- Local notifications with action buttons
- Cross-device alerts via iCloud
- Menu bar integration with status
- Full data reset option

### Security

- Passcodes stored in macOS Keychain
- SHA-256 hashing with 32-byte random salt
- kSecAttrAccessibleWhenUnlockedThisDeviceOnly keychain protection
- Progressive time-based lockout (30s → 1hr)
- No network connectivity required (except iCloud sync)

### Technical

- Swift 5.9+ and SwiftUI
- Pure Swift Package Manager project
- LocalAuthentication framework for biometrics
- NSWorkspace monitoring for app events
- Requires macOS 13.0 (Ventura) or later
- Needs Accessibility permissions

## [2.0.0] - 2025-02-10

### Added

- Enhanced UI with multiple tabs
- Settings panel
- Usage statistics view
- Notification history
- App categories system

## [1.0.0] - 2025-02-09

### Added

- Basic app locking functionality
- Passcode authentication
- Simple UI
- Activity logging

[Unreleased]: https://github.com/Mirxa27/AppLocker/compare/v3.6.0...HEAD
[3.6.0]: https://github.com/Mirxa27/AppLocker/releases/tag/v3.6.0
[3.0.0]: https://github.com/Mirxa27/AppLocker/releases/tag/v3.0.0
[2.0.0]: https://github.com/Mirxa27/AppLocker/releases/tag/v2.0.0
[1.0.0]: https://github.com/Mirxa27/AppLocker/releases/tag/v1.0.0
