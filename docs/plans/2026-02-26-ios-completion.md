# iOS App Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the iOS companion app — fix all broken CloudKit-dependent screens using iCloud KV Store, add the app icon, and fix Secure Notes cross-device decryption.

**Architecture:** A new `KVStoreManager` singleton subscribes to `NSUbiquitousKeyValueStore` on iOS and publishes decoded data. The Mac side writes three new keys (`lockedApps`, `encryptedNotes`, `notesSalt`) so iOS can read live data without CloudKit. All broken views are rewritten to consume `KVStoreManager`.

**Tech Stack:** Swift 5.9, SwiftUI, NSUbiquitousKeyValueStore, CryptoKit (via existing CryptoHelper), sips (macOS CLI for icon resizing), Xcode project.pbxproj (for asset catalog registration)

---

## Task 1: Generate App Icon Asset Catalog

**Files:**
- Create: `Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: 14 icon PNG files in that folder (generated from `icon.png`)
- Modify: `AppLocker.xcodeproj/project.pbxproj` (add asset catalog reference)

**Step 1: Generate all iOS icon sizes from icon.png using sips**

Run from repo root:

```bash
mkdir -p Sources/AppLocker/Assets.xcassets/AppIcon.appiconset

# Generate each required size
sips -z 20  20  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-20.png
sips -z 40  40  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-20@2x.png
sips -z 60  60  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-20@3x.png
sips -z 29  29  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-29.png
sips -z 58  58  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-29@2x.png
sips -z 87  87  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-29@3x.png
sips -z 40  40  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-40.png
sips -z 80  80  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-40@2x.png
sips -z 120 120 icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-40@3x.png
sips -z 120 120 icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-60@2x.png
sips -z 180 180 icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-60@3x.png
sips -z 76  76  icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-76.png
sips -z 152 152 icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-76@2x.png
sips -z 167 167 icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-83.5@2x.png
sips -z 1024 1024 icon.png --out Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-1024.png
```

**Step 2: Write Contents.json**

Create `Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [
    { "filename": "Icon-20.png",      "idiom": "iphone", "scale": "1x", "size": "20x20"    },
    { "filename": "Icon-20@2x.png",   "idiom": "iphone", "scale": "2x", "size": "20x20"    },
    { "filename": "Icon-20@3x.png",   "idiom": "iphone", "scale": "3x", "size": "20x20"    },
    { "filename": "Icon-29.png",      "idiom": "iphone", "scale": "1x", "size": "29x29"    },
    { "filename": "Icon-29@2x.png",   "idiom": "iphone", "scale": "2x", "size": "29x29"    },
    { "filename": "Icon-29@3x.png",   "idiom": "iphone", "scale": "3x", "size": "29x29"    },
    { "filename": "Icon-40.png",      "idiom": "iphone", "scale": "1x", "size": "40x40"    },
    { "filename": "Icon-40@2x.png",   "idiom": "iphone", "scale": "2x", "size": "40x40"    },
    { "filename": "Icon-40@3x.png",   "idiom": "iphone", "scale": "3x", "size": "40x40"    },
    { "filename": "Icon-60@2x.png",   "idiom": "iphone", "scale": "2x", "size": "60x60"    },
    { "filename": "Icon-60@3x.png",   "idiom": "iphone", "scale": "3x", "size": "60x60"    },
    { "filename": "Icon-76.png",      "idiom": "ipad",   "scale": "1x", "size": "76x76"    },
    { "filename": "Icon-76@2x.png",   "idiom": "ipad",   "scale": "2x", "size": "76x76"    },
    { "filename": "Icon-83.5@2x.png", "idiom": "ipad",   "scale": "2x", "size": "83.5x83.5"},
    { "filename": "Icon-20.png",      "idiom": "ipad",   "scale": "1x", "size": "20x20"    },
    { "filename": "Icon-20@2x.png",   "idiom": "ipad",   "scale": "2x", "size": "20x20"    },
    { "filename": "Icon-29.png",      "idiom": "ipad",   "scale": "1x", "size": "29x29"    },
    { "filename": "Icon-29@2x.png",   "idiom": "ipad",   "scale": "2x", "size": "29x29"    },
    { "filename": "Icon-40.png",      "idiom": "ipad",   "scale": "1x", "size": "40x40"    },
    { "filename": "Icon-40@2x.png",   "idiom": "ipad",   "scale": "2x", "size": "40x40"    },
    { "filename": "Icon-1024.png",    "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

**Step 3: Write Assets.xcassets root Contents.json**

Create `Sources/AppLocker/Assets.xcassets/Contents.json`:

```json
{
  "info": { "author": "xcode", "version": 1 }
}
```

**Step 4: Register asset catalog in Xcode project**

Read `AppLocker.xcodeproj/project.pbxproj`, find the iOS target's resources build phase, and add the asset catalog. The simplest reliable approach: open project.pbxproj and add the xcassets as a PBXFileReference + PBXBuildFile + add to Resources build phase of the iOS target (AppLockerCompanion).

Look for the existing `PBXResourcesBuildPhase` for the iOS target and add the asset catalog there. Alternatively, use xcodebuild to validate the project after manual edit.

The key sections to modify in project.pbxproj:
1. Add PBXFileReference for Assets.xcassets
2. Add PBXBuildFile referencing that file reference
3. Add the PBXBuildFile UUID to the iOS target's Resources build phase files array
4. Add the PBXFileReference to the main PBXGroup

**Step 5: Verify build compiles**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```
Expected: `Build complete!`

**Step 6: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/Assets.xcassets/ AppLocker.xcodeproj/project.pbxproj
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "feat: add iOS app icon asset catalog (all sizes from icon.png)"
```

---

## Task 2: KVStoreManager — iOS iCloud KV Bridge

**Files:**
- Create: `Sources/AppLocker/iOS/KVStoreManager.swift`

**Step 1: Write KVStoreManager.swift**

```swift
// Sources/AppLocker/iOS/KVStoreManager.swift
#if os(iOS)
import Foundation
import SwiftUI

// Lightweight alert record stored locally on iOS.
struct AlertRecord: Codable, Identifiable {
    var id = UUID()
    let appName: String
    let bundleID: String
    let deviceName: String
    let timestamp: Date
    let type: String   // "blocked" | "failed_attempt"
}

@MainActor
class KVStoreManager: ObservableObject {
    static let shared = KVStoreManager()

    @Published var lockedApps: [LockedAppInfo] = []
    @Published var alertHistory: [AlertRecord] = []
    @Published var encryptedNotes: [EncryptedNote] = []
    @Published var notesSalt: Data? = nil
    @Published var lastMacDevice: String? = nil
    @Published var lastSyncTime: Date? = nil

    private let store = NSUbiquitousKeyValueStore.default
    private let historyKey = "com.applocker.ios.alertHistory"

    private init() {
        loadAlertHistory()
        decodeAllKeys()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    // MARK: - KV Change Handler

    @objc private func kvStoreChanged(_ notification: Notification) {
        decodeAllKeys()

        // Append new alert to local history if it's fresh (< 5 min old)
        if let data = store.data(forKey: "com.applocker.latestAlert"),
           let alert = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let appName = alert["appName"] as? String,
           let bundleID = alert["bundleID"] as? String,
           let device = alert["deviceName"] as? String,
           let ts = alert["timestamp"] as? TimeInterval,
           let type = alert["type"] as? String,
           Date().timeIntervalSince1970 - ts < 300 {

            let record = AlertRecord(
                appName: appName,
                bundleID: bundleID,
                deviceName: device,
                timestamp: Date(timeIntervalSince1970: ts),
                type: type
            )
            // Avoid duplicates (same app within 5 seconds)
            let isDuplicate = alertHistory.contains {
                $0.appName == appName && abs($0.timestamp.timeIntervalSince1970 - ts) < 5
            }
            if !isDuplicate {
                alertHistory.insert(record, at: 0)
                if alertHistory.count > 200 { alertHistory = Array(alertHistory.prefix(200)) }
                saveAlertHistory()
            }
        }
    }

    // MARK: - Decode All KV Keys

    func decodeAllKeys() {
        // Locked apps
        if let b64 = store.string(forKey: "com.applocker.lockedApps"),
           let data = Data(base64Encoded: b64),
           let apps = try? JSONDecoder().decode([LockedAppInfo].self, from: data) {
            lockedApps = apps
        }

        // Encrypted notes
        if let b64 = store.string(forKey: "com.applocker.encryptedNotes"),
           let data = Data(base64Encoded: b64),
           let notes = try? {
               let d = JSONDecoder()
               d.dateDecodingStrategy = .iso8601
               return try d.decode([EncryptedNote].self, from: data)
           }() {
            encryptedNotes = notes
        }

        // Notes salt
        if let b64 = store.string(forKey: "com.applocker.notesSalt"),
           let saltData = Data(base64Encoded: b64) {
            notesSalt = saltData
        }

        // Last alert metadata
        if let data = store.data(forKey: "com.applocker.latestAlert"),
           let alert = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            lastMacDevice = alert["deviceName"] as? String
            if let ts = alert["timestamp"] as? TimeInterval {
                lastSyncTime = Date(timeIntervalSince1970: ts)
            }
        }
    }

    // MARK: - Alert History Persistence

    func clearHistory() {
        alertHistory.removeAll()
        saveAlertHistory()
    }

    private func saveAlertHistory() {
        if let data = try? JSONEncoder().encode(alertHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadAlertHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let records = try? JSONDecoder().decode([AlertRecord].self, from: data) else { return }
        alertHistory = records
    }
}
#endif
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```
Expected: `Build complete!`

**Step 3: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/iOS/KVStoreManager.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "feat: KVStoreManager — iCloud KV bridge for iOS, alert history, locked apps, notes"
```

---

## Task 3: Mac Side — Write to iCloud KV Store

**Files:**
- Modify: `Sources/AppLocker/AppMonitor.swift`
- Modify: `Sources/AppLocker/SecureNotes/SecureNotesManager.swift`

**Step 1: Add KV write to AppMonitor.saveLockedApps()**

In `Sources/AppLocker/AppMonitor.swift`, find `saveLockedApps()`:

```swift
    private func saveLockedApps() {
        if let data = try? JSONEncoder().encode(lockedApps) {
            UserDefaults.standard.set(data, forKey: lockedAppsKey)
        }
    }
```

Replace with:

```swift
    private func saveLockedApps() {
        if let data = try? JSONEncoder().encode(lockedApps) {
            UserDefaults.standard.set(data, forKey: lockedAppsKey)
            // Sync to iCloud KV so iOS companion can read the locked app list
            NSUbiquitousKeyValueStore.default.set(
                data.base64EncodedString(),
                forKey: "com.applocker.lockedApps"
            )
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }
```

**Step 2: Add KV writes to SecureNotesManager**

In `Sources/AppLocker/SecureNotes/SecureNotesManager.swift`, find `saveNotes()`:

```swift
    private func saveNotes() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(notes) {
            try? data.write(to: notesFileURL)
        }
    }
```

Replace with:

```swift
    private func saveNotes() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(notes) {
            try? data.write(to: notesFileURL)
            // Sync encrypted notes to iCloud KV for iOS companion (read-only on iOS)
            NSUbiquitousKeyValueStore.default.set(
                data.base64EncodedString(),
                forKey: "com.applocker.encryptedNotes"
            )
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }
```

Also find `unlock(passcode:)` — after deriving the session key and calling `loadNotes()`, add a salt sync. Find the line `isUnlocked = true` and add after `loadNotes()`:

```swift
            // Sync salt to iCloud KV so iOS can derive the same key
            let saltB64 = salt.base64EncodedString()
            NSUbiquitousKeyValueStore.default.set(saltB64, forKey: "com.applocker.notesSalt")
            NSUbiquitousKeyValueStore.default.synchronize()
```

Full updated `unlock` function:

```swift
    func unlock(passcode: String) -> Bool {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"
            return false
        }
        do {
            let salt = try CryptoHelper.getOrCreateSalt(keychainKey: keychainSaltKey)
            sessionKey = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.notes.v1")
            isUnlocked = true
            lastError = nil
            loadNotes()
            // Sync salt to iCloud KV so iOS companion can derive the same notes key
            NSUbiquitousKeyValueStore.default.set(salt.base64EncodedString(),
                                                   forKey: "com.applocker.notesSalt")
            NSUbiquitousKeyValueStore.default.synchronize()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
```

**Step 3: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 4: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/AppMonitor.swift Sources/AppLocker/SecureNotes/SecureNotesManager.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "feat: Mac syncs lockedApps + encryptedNotes + notesSalt to iCloud KV Store"
```

---

## Task 4: Fix AppLockerApp_iOS — Remove CloudKit Setup

**Files:**
- Modify: `Sources/AppLocker/iOS/AppLockerApp_iOS.swift`

**Step 1: Remove the CloudKitManager call**

Find `CloudKitManager.shared.setupPushSubscriptions()` and delete that line.

Updated `application(_:didFinishLaunchingWithOptions:)`:

```swift
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestNotificationPermissions()
        // Sync KV store on launch so latest Mac data is immediately available
        NSUbiquitousKeyValueStore.default.synchronize()
        Task { @MainActor in KVStoreManager.shared.decodeAllKeys() }
        return true
    }
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 3: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/iOS/AppLockerApp_iOS.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "fix: remove CloudKit push subscription, sync KVStoreManager on iOS launch"
```

---

## Task 5: Rewrite Dashboard View

**Files:**
- Modify: `Sources/AppLocker/iOS/Dashboard/DashboardView.swift`

**Step 1: Rewrite DashboardView.swift**

Replace the entire file content:

```swift
// Sources/AppLocker/iOS/Dashboard/DashboardView.swift
#if os(iOS)
import SwiftUI

struct DashboardView: View {
    @ObservedObject private var kv         = KVStoreManager.shared
    @ObservedObject private var protection = AppProtectionManager.shared

    var body: some View {
        NavigationStack {
            List {
                // Mac connection card
                Section("Mac Device") {
                    if let device = kv.lastMacDevice {
                        HStack {
                            Image(systemName: "desktopcomputer")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device).font(.headline)
                                if let sync = kv.lastSyncTime {
                                    Text("Last seen \(sync.formatted(.relative(presentation: .named)))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        HStack {
                            Image(systemName: "lock.app.dashed").foregroundColor(.orange)
                            Text("\(kv.lockedApps.count) app\(kv.lockedApps.count == 1 ? "" : "s") locked")
                                .font(.subheadline)
                        }
                    } else {
                        Label("No Mac connected — open AppLocker on your Mac",
                              systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                // Recent blocks
                Section("Recent Blocks") {
                    let recent = kv.alertHistory.filter { $0.type.contains("block") }.prefix(5)
                    if recent.isEmpty {
                        Text("No recent blocks").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(Array(recent)) { alert in
                            HStack {
                                Image(systemName: "hand.raised.fill").foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.appName).font(.subheadline)
                                    Text(alert.timestamp.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // iOS security status
                Section("iOS Security") {
                    Label(
                        protection.isJailbroken ? "Jailbreak detected!" : "Device integrity OK",
                        systemImage: protection.isJailbroken
                            ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                    )
                    .foregroundColor(protection.isJailbroken ? .red : .green)

                    Label(
                        protection.isPINSet() ? "PIN protection enabled" : "No PIN set",
                        systemImage: protection.isPINSet() ? "lock.fill" : "lock.slash"
                    )
                    .foregroundColor(protection.isPINSet() ? .green : .orange)

                    Label(
                        protection.isScreenRecording ? "Screen recording active!" : "Screen not recorded",
                        systemImage: protection.isScreenRecording ? "eye.trianglebadge.exclamationmark" : "eye.slash"
                    )
                    .foregroundColor(protection.isScreenRecording ? .red : .secondary)
                }
            }
            .navigationTitle("Dashboard")
            .refreshable { kv.decodeAllKeys() }
        }
    }
}
#endif
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 3: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/iOS/Dashboard/DashboardView.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "feat: Dashboard reads from KVStoreManager (Mac device, recent blocks, iOS security)"
```

---

## Task 6: Rewrite Alerts View

**Files:**
- Modify: `Sources/AppLocker/iOS/Alerts/AlertsView.swift`

**Step 1: Rewrite AlertsView.swift**

Replace entire file:

```swift
// Sources/AppLocker/iOS/Alerts/AlertsView.swift
#if os(iOS)
import SwiftUI

enum AlertFilter: String, CaseIterable, Identifiable {
    var id: Self { self }
    case all     = "All"
    case blocked = "Blocked"
    case failed  = "Failed Auth"
}

struct AlertsView: View {
    @ObservedObject private var kv = KVStoreManager.shared
    @State private var filter: AlertFilter = .all

    var filtered: [AlertRecord] {
        switch filter {
        case .all:     return kv.alertHistory
        case .blocked: return kv.alertHistory.filter { $0.type.contains("block") }
        case .failed:  return kv.alertHistory.filter { $0.type.contains("fail") }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(AlertFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Alerts",
                        systemImage: "bell.slash",
                        description: Text("Alerts appear here when your Mac blocks an app.")
                    )
                } else {
                    List(filtered) { alert in
                        AlertRecordRow(alert: alert)
                    }
                }
            }
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { kv.decodeAllKeys() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                if !kv.alertHistory.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) { kv.clearHistory() }
                    }
                }
            }
            .refreshable { kv.decodeAllKeys() }
        }
    }
}

struct AlertRecordRow: View {
    let alert: AlertRecord
    var isFailed: Bool { alert.type.contains("fail") }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                .foregroundColor(isFailed ? .red : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.appName).font(.headline)
                Text(alert.deviceName).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(alert.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
#endif
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 3: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/iOS/Alerts/AlertsView.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "feat: Alerts reads from KVStoreManager local history, filterable, clearable"
```

---

## Task 7: Rewrite Remote Control View

**Files:**
- Modify: `Sources/AppLocker/iOS/RemoteControl/RemoteControlView.swift`

**Step 1: Rewrite RemoteControlView.swift**

Replace entire file:

```swift
// Sources/AppLocker/iOS/RemoteControl/RemoteControlView.swift
#if os(iOS)
import SwiftUI
import LocalAuthentication

@MainActor
class RemoteControlViewModel: ObservableObject {
    @Published var statusMessage: String?

    func sendCommand(_ action: RemoteCommand.Action, bundleID: String? = nil) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            statusMessage = "Biometrics required to send commands"; return false
        }
        do {
            _ = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Confirm remote command"
            )
        } catch {
            statusMessage = error.localizedDescription; return false
        }
        NotificationManager.shared.sendRemoteCommand(action, bundleID: bundleID)
        statusMessage = "Command sent"
        // Auto-clear status after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = nil
        }
        return true
    }
}

struct RemoteControlView: View {
    @ObservedObject private var kv = KVStoreManager.shared
    @StateObject private var vm = RemoteControlViewModel()
    @State private var searchText = ""

    var filteredApps: [LockedAppInfo] {
        searchText.isEmpty ? kv.lockedApps
            : kv.lockedApps.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Global Commands") {
                    Button(role: .destructive) {
                        Task { _ = await vm.sendCommand(.lockAll) }
                    } label: {
                        Label("Lock All Apps", systemImage: "lock.fill")
                    }
                    Button {
                        Task { _ = await vm.sendCommand(.unlockAll) }
                    } label: {
                        Label("Unlock All Apps", systemImage: "lock.open.fill")
                    }
                    .foregroundColor(.green)
                }

                Section("Locked Apps (\(kv.lockedApps.count))") {
                    if kv.lockedApps.isEmpty {
                        if kv.lastMacDevice == nil {
                            Label("Open AppLocker on your Mac first",
                                  systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("No apps are currently locked")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(filteredApps) { app in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName).font(.subheadline)
                                    Text(app.bundleID).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Unlock") {
                                    Task { _ = await vm.sendCommand(.unlockApp, bundleID: app.bundleID) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                if let msg = vm.statusMessage {
                    Section {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search locked apps")
            .navigationTitle("Remote Control")
            .refreshable { kv.decodeAllKeys() }
        }
    }
}
#endif
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 3: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/iOS/RemoteControl/RemoteControlView.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "feat: Remote Control reads locked apps from KV Store, removes CloudKit dependency"
```

---

## Task 8: Fix Intruder Photos — Graceful Empty State

**Files:**
- Modify: `Sources/AppLocker/iOS/IntruderPhotos/iOSIntruderPhotosView.swift`

**Step 1: Rewrite iOSIntruderPhotosView.swift**

Replace entire file:

```swift
// Sources/AppLocker/iOS/IntruderPhotos/iOSIntruderPhotosView.swift
#if os(iOS)
import SwiftUI

struct iOSIntruderPhotosView: View {
    @ObservedObject private var kv = KVStoreManager.shared

    // Failed-auth alert records as a proxy for intruder events
    var intruderAlerts: [AlertRecord] {
        kv.alertHistory.filter { $0.type.contains("fail") }
    }

    var body: some View {
        NavigationStack {
            Group {
                if intruderAlerts.isEmpty {
                    ContentUnavailableView {
                        Label("No Intruder Events", systemImage: "eye.trianglebadge.exclamationmark")
                    } description: {
                        Text("Intruder photos are captured on your Mac after 2+ failed unlock attempts.\n\nOpen AppLocker on your Mac to view the photos.")
                    }
                } else {
                    List(intruderAlerts) { alert in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Failed unlock attempt on \(alert.appName)")
                                    .font(.subheadline)
                                Text(alert.deviceName)
                                    .font(.caption).foregroundColor(.secondary)
                                Text(alert.timestamp.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Intruder Events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { kv.decodeAllKeys() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable { kv.decodeAllKeys() }
        }
    }
}
#endif
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 3: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/iOS/IntruderPhotos/iOSIntruderPhotosView.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "feat: Intruder Photos shows failed-auth events from KV history, no CloudKit dependency"
```

---

## Task 9: Fix Secure Notes — Context + Salt Source

**Files:**
- Modify: `Sources/AppLocker/iOS/SecureNotes/iOSSecureNotesView.swift`

**Step 1: Rewrite the ViewModel to use KVStoreManager**

Replace entire file:

```swift
// Sources/AppLocker/iOS/SecureNotes/iOSSecureNotesView.swift
#if os(iOS)
import SwiftUI

@MainActor
class iOSNotesViewModel: ObservableObject {
    @Published var notes: [EncryptedNote] = []
    @Published var sessionKey: CryptoKit.SymmetricKey? = nil
    @Published var requiresPasscode = true
    @Published var error: String?

    // MARK: - Unlock

    func unlock(passcode: String) {
        let kv = KVStoreManager.shared

        // Salt must come from KV store (written by Mac when notes are unlocked)
        guard let salt = kv.notesSalt else {
            error = "Notes not yet synced from Mac — unlock notes on your Mac first"
            return
        }
        // Notes must be present in KV store
        guard !kv.encryptedNotes.isEmpty else {
            // No notes yet — unlock with the provided passcode anyway
            let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt,
                                              context: "applocker.notes.v1")
            sessionKey = key
            requiresPasscode = false
            notes = []
            error = nil
            return
        }
        // Verify passcode by attempting to decrypt the first note body
        let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt,
                                          context: "applocker.notes.v1")
        guard let _ = try? CryptoHelper.decrypt(kv.encryptedNotes[0].encryptedBody, using: key) else {
            error = "Incorrect passcode"
            return
        }
        sessionKey = key
        notes = kv.encryptedNotes.sorted { $0.modifiedAt > $1.modifiedAt }
        requiresPasscode = false
        error = nil
    }

    func lock() {
        sessionKey = nil
        requiresPasscode = true
        notes = []
    }

    // MARK: - Decrypt

    func decryptBody(of note: EncryptedNote) -> String {
        guard let key = sessionKey,
              let data = try? CryptoHelper.decrypt(note.encryptedBody, using: key) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Views

struct iOSSecureNotesView: View {
    @StateObject private var vm = iOSNotesViewModel()
    @State private var passcodeEntry = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.requiresPasscode {
                    unlockPlaceholder
                } else if vm.notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Create notes in AppLocker on your Mac.\nThey'll appear here once synced.")
                    )
                } else {
                    List(vm.notes) { note in
                        NavigationLink(destination: iOSNoteDetailView(note: note, vm: vm)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title).font(.headline)
                                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Secure Notes")
            .toolbar {
                if !vm.requiresPasscode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Lock") { vm.lock() }
                    }
                }
            }
        }
    }

    private var unlockPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 60)).foregroundColor(.blue)
            Text("Secure Notes")
                .font(.title2.bold())
            Text("Enter your AppLocker master passcode\nto read notes synced from your Mac.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            SecureField("Master passcode", text: $passcodeEntry)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            if let err = vm.error {
                Text(err).foregroundColor(.red).font(.caption)
            }
            Button("Unlock Notes") {
                vm.unlock(passcode: passcodeEntry)
                passcodeEntry = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(passcodeEntry.isEmpty)
        }
        .padding()
    }
}

struct iOSNoteDetailView: View {
    let note: EncryptedNote
    @ObservedObject var vm: iOSNotesViewModel
    @State private var bodyText = ""

    var body: some View {
        ScrollView {
            Text(bodyText.isEmpty ? "(empty)" : bodyText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(note.title)
        .onAppear { bodyText = vm.decryptBody(of: note) }
    }
}
#endif
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 3: Commit**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  add Sources/AppLocker/iOS/SecureNotes/iOSSecureNotesView.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  commit -m "fix: Secure Notes uses correct context (applocker.notes.v1) and salt from KV Store"
```

---

## Task 10: Final Build Verification + GitHub Push

**Step 1: Full clean build**

```bash
swift package clean && swift build -c release 2>&1 | grep -E '(error:|Build complete|warning:)' | grep -v AuthenticationManager
```
Expected: `Build complete!` with zero errors.

**Step 2: Push main**

```bash
git push origin main 2>&1 | tail -3
```

**Step 3: Tag and release**

```bash
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" \
  tag -a v3.5 -m "AppLocker v3.5 — iOS app completion + app icon"
git push origin v3.5
```

The GitHub Actions release workflow will automatically:
- Build the macOS release binary
- Sign with Developer ID
- Notarize and staple
- Publish `AppLocker-3.5.dmg` to GitHub releases

---

## Build Order

```
Task 1 (icon) → Task 2 (KVStoreManager) → Task 3 (Mac KV writes)
  → Task 4 (AppDelegate fix) → Task 5 (Dashboard) → Task 6 (Alerts)
    → Task 7 (Remote Control) → Task 8 (Intruder Photos) → Task 9 (Secure Notes)
      → Task 10 (verify + publish)
```
