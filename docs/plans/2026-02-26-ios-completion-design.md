# iOS App Completion Design

**Date:** 2026-02-26
**Status:** Approved

## Goal
Complete the iOS companion app: fix broken CloudKit-dependent screens, add app icon, fix Secure Notes cross-device decryption.

## Architecture — iCloud KV Store bridge

Mac writes three new keys; iOS reads them via `KVStoreManager`.

| KV Key | Type | Written by Mac |
|--------|------|---------------|
| `com.applocker.lockedApps` | base64(JSON `[LockedAppInfo]`) | `AppMonitor.saveLockedApps()` |
| `com.applocker.encryptedNotes` | base64(JSON `[EncryptedNote]`) | `SecureNotesManager.saveNotes()` |
| `com.applocker.notesSalt` | base64(32-byte Data) | `SecureNotesManager` on first salt creation |

Existing keys (already written by Mac): `com.applocker.latestAlert`, `com.applocker.latestCommand`.

## Files Changed

### New
- `Sources/AppLocker/iOS/KVStoreManager.swift`
- `Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Contents.json` + icon PNGs

### Modified — Mac side
- `Sources/AppLocker/AppMonitor.swift` — add KV write in `saveLockedApps()`
- `Sources/AppLocker/SecureNotes/SecureNotesManager.swift` — add KV write in `saveNotes()` and `getOrCreateSalt()`

### Modified — iOS side
- `Sources/AppLocker/iOS/AppLockerApp_iOS.swift` — remove `CloudKitManager.setupPushSubscriptions()`
- `Sources/AppLocker/iOS/Dashboard/DashboardView.swift` — use KVStoreManager
- `Sources/AppLocker/iOS/Alerts/AlertsView.swift` — use local AlertRecord history
- `Sources/AppLocker/iOS/RemoteControl/RemoteControlView.swift` — read locked apps from KV
- `Sources/AppLocker/iOS/IntruderPhotos/iOSIntruderPhotosView.swift` — graceful empty state
- `Sources/AppLocker/iOS/SecureNotes/iOSSecureNotesView.swift` — fix context + salt

## Screen Designs

### KVStoreManager
```swift
@MainActor class KVStoreManager: ObservableObject {
    static let shared = KVStoreManager()
    @Published var lockedApps: [LockedAppInfo] = []
    @Published var alertHistory: [AlertRecord] = []     // persisted to UserDefaults
    @Published var encryptedNotes: [EncryptedNote] = []
    @Published var notesSalt: Data? = nil
    @Published var lastMacDevice: String? = nil
    @Published var lastSyncTime: Date? = nil
}

struct AlertRecord: Codable, Identifiable {
    var id = UUID()
    let appName: String
    let bundleID: String
    let deviceName: String
    let timestamp: Date
    let type: String   // "blocked" | "failed_attempt"
}
```

### Dashboard
- Section "Mac Device": device name + last sync time from `lastMacDevice` / `lastSyncTime`
- Section "Recent Blocks": last 5 entries from `alertHistory` filtered to `.blocked`
- Section "iOS Security": jailbreak status, PIN status, screen recording status

### Alerts
- Segmented picker: All / Blocked / Failed
- List from `alertHistory` sorted by timestamp desc
- Pull-to-refresh appends new KV alerts; "Clear History" button

### Remote Control
- Loads `KVStoreManager.shared.lockedApps` directly (no async fetch)
- Commands sent via `NotificationManager.shared.sendRemoteCommand()` unchanged

### Intruder Photos
- Empty state: "Intruder photos are captured and stored on your Mac.\nOpen AppLocker on your Mac to view them."
- Icon: `desktopcomputer.and.iphone`

### Secure Notes
- Salt: `KVStoreManager.shared.notesSalt`
- Notes: `KVStoreManager.shared.encryptedNotes`
- Decryption context: `"applocker.notes.v1"` (matching Mac)

## App Icon
Generate from `icon.png` (1024×1024) → all required iOS sizes via `sips`:
- 20pt @1x/2x/3x, 29pt @1x/2x/3x, 40pt @2x/3x, 60pt @2x/3x, 76pt @1x/2x, 83.5pt @2x, 1024pt @1x
- Store in `Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/`
- Register in Xcode project `project.pbxproj`

## Non-Goals
- CloudKit provisioning (requires App Store or separate provisioning profile)
- iCloud Drive sync for intruder photos
- Creating new notes on iOS (read-only view of Mac notes)
