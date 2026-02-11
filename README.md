# AppLocker for macOS

A macOS application that lets you lock apps behind a passcode or Touch ID/Face ID authentication.

## Features

- **Passcode Protection** - Securely lock apps with a 4+ digit passcode (SHA-256 hashed with random salt, stored in Keychain)
- **Biometric Authentication** - Unlock with Touch ID or Face ID (if available)
- **App Blocking Engine** - Prevents locked apps from opening without authentication (200ms polling + workspace observers)
- **Schedule-Based Locking** - Set time-based rules for when apps should be locked (per-app, with day-of-week support)
- **Usage Statistics** - Track block counts, unlock counts, and failed attempts per app with time-period filtering
- **App Categories** - Organize locked apps into groups (Social Media, Games, etc.) for batch management
- **Configurable Unlock Duration** - Choose how long temporary unlocks last (30s to 1 hour)
- **Auto-Lock on Sleep** - Automatically re-locks all apps and AppLocker when screen sleeps or lid closes
- **Escalating Lockout** - Progressive time-based lockout after failed passcode attempts (30s to 1 hour)
- **Change Passcode** - Update your security passcode from Settings
- **Export/Import Config** - Backup and restore your locked apps, categories, and settings
- **Persistent Activity Log** - Logs survive app restarts (up to 500 entries)
- **Local Notifications** - Get notified when locked apps are accessed, with action buttons
- **Cross-Device Alerts** - Sync security alerts via iCloud to your other Apple devices
- **Menu Bar Integration** - Quick access from the macOS status bar
- **Full Reset** - Option to wipe all data and start fresh from Settings

## How to Use

### First Time Setup

1. Launch AppLocker
2. Set up your security passcode (minimum 4 characters)
3. Grant Accessibility permissions when prompted (required for app blocking)

### Locking Apps

1. Open AppLocker and authenticate
2. Go to the "Add Apps" tab
3. Browse installed apps or currently running apps
4. Click "Lock" on any app you want to protect
5. Enable monitoring using the toggle in the header

### Unlocking Apps

When you try to open a locked app:

1. AppLocker will intercept and terminate it
2. An unlock dialog appears
3. Enter your passcode OR use Touch ID/Face ID
4. The app will be temporarily unlocked for the configured duration (default: 5 minutes)

### Schedules

1. Go to the "Locked Apps" tab
2. Click the clock icon next to any locked app
3. Enable scheduling and set the active hours and days
4. The app will only be blocked during the scheduled time windows

### Usage Statistics

The "Stats" tab shows:

- Total blocks, unlocks, and failed attempts
- Per-app breakdown with last-blocked timestamps
- Filterable by time period (today, this week, this month, all time)

### Settings

- **Security**: Change passcode, auto-lock on sleep, lockout protection
- **Unlock Duration**: Configure how long temporary unlocks last
- **Notifications**: Toggle notifications and cross-device alerts
- **Backup & Restore**: Export/import your configuration
- **Danger Zone**: Reset all data

### Security Notes

- Passcodes are hashed with SHA-256 and a random 32-byte salt
- Credentials stored in macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- No network connectivity required (except for cross-device iCloud sync)
- Escalating lockout: 30s at 5 failures, 2min at 8, 5min at 10, 15min at 15, 1hr at 20
- All data stays on your device

## Technical Details

- Built with Swift 5.9+ and SwiftUI
- Uses LocalAuthentication framework for biometrics
- Uses CryptoKit (SHA-256) for passcode hashing
- Requires macOS 13.0 (Ventura) or later
- Needs Accessibility permissions for app monitoring
- Pure Swift Package Manager project (no Xcode project needed)

## Build from Source

```bash
cd ~/AppLocker
swift build -c release
```

To create the app bundle:

```bash
swift build -c release
cp -r AppLocker.app/Contents/Resources .build/arm64-apple-macosx/release/
```

## Important

**Grant Accessibility Permissions**: The app needs Accessibility access to monitor and block other applications. You'll be prompted on first launch. Go to System Settings > Privacy & Security > Accessibility to manage.

**Passcode Recovery**: You can now change your passcode from Settings (requires current passcode). If you forget your passcode completely, use the "Reset Everything" option in Settings > Danger Zone, which will wipe all data.
