# Changelog

All notable changes to AppLocker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Fix app blocking functionality
- Improve monitoring reliability
- Add more comprehensive debug logging

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

### Notes

- Known issue: App blocking may not work reliably in all scenarios
- Requires manual testing of blocking functionality

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

[Unreleased]: https://github.com/Mirxa27/AppLocker/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/Mirxa27/AppLocker/releases/tag/v3.0.0
[2.0.0]: https://github.com/Mirxa27/AppLocker/releases/tag/v2.0.0
[1.0.0]: https://github.com/Mirxa27/AppLocker/releases/tag/v1.0.0
