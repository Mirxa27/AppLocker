# AppLocker — Security Hardening + iOS Companion Design
**Date:** 2026-02-25
**Status:** Approved

---

## 1. Goals

1. Harden macOS cryptographic and runtime security to professional standard.
2. Build a full iOS companion dashboard (replacing the 3-button stub).
3. Replace the slow iCloud KV notification path with real-time CloudKit push.

---

## 2. Notification Architecture

### Current state
Mac writes to `NSUbiquitousKeyValueStore`. iOS sees it only when KV syncs — latency 30 s to several minutes.

### New: CloudKit subscriptions
- Mac creates `CKRecord` types `BlockedAppEvent` and `FailedAuthEvent` in the default CloudKit container (`iCloud.com.mirxa.AppLocker`).
- iOS app creates a `CKQuerySubscription` on both record types. CloudKit sends a silent push within 1–3 seconds of record creation.
- iOS `UNUserNotificationCenter` surfaces the push as a banner.
- Both platforms still write to iCloud KV for backwards-compatible status sync (monitoring on/off, locked-apps list).

### CloudKit record schemas

**BlockedAppEvent**
```
id:          String (UUID, CKRecord.ID)
appName:     String
bundleID:    String
deviceName:  String
timestamp:   Date
```

**FailedAuthEvent**
```
id:          String
appName:     String
bundleID:    String
deviceName:  String
timestamp:   Date
photoAsset:  CKAsset? (encrypted intruder photo, optional)
```

**LockedAppList** (one record, updated on every lock/unlock)
```
deviceName:  String
apps:        Data (JSON-encoded [LockedAppInfo], AES-GCM encrypted)
updatedAt:   Date
```

---

## 3. macOS Security Hardening

### 3.1 PBKDF2 passcode hashing
- **Current:** `SHA256(passcode + salt)` — single-pass, GPU-brute-forcable.
- **New:** `SecKeyDerivePBKDF2` (CCKeyDerivationPBKDF) with SHA-256 PRF, 200,000 iterations, 32-byte output, 32-byte random salt.
- **Migration:** On next successful login with the old hash, re-derive with PBKDF2 and overwrite both the hash and a new `passcodeVersion` Keychain item (`"v2"`). Old SHA-256 path removed after migration.

### 3.2 Anti-debugger
- On `applicationDidFinishLaunching`, call `ptrace(PT_DENY_ATTACH, 0, 0, 0)` via a `@_silgen_name` bridge.
- If a debugger is already attached, the OS sends SIGSEGV and the app exits.
- No-op in `#if DEBUG` builds so Xcode debugging still works.

### 3.3 Inactivity auto-lock
- `InactivityMonitor` singleton: calls `NSEvent.addGlobalMonitorForEvents(matching: .any)` to reset an idle timer.
- Default timeout: 10 minutes (user-configurable 1–60 min in Settings).
- On fire: `AuthenticationManager.shared.logout()`, clears `temporarilyUnlockedApps`.
- Timer paused while the lock screen / setup wizard is visible.

### 3.4 Encrypted exports
- Export payload: JSON → AES-GCM encrypt with a key derived from the master passcode via `CryptoHelper.deriveKey(passcode:salt:context:"export")`.
- File format: `4-byte magic "APLK"` + `1-byte version` + `32-byte salt` + `12-byte nonce` + ciphertext + `16-byte GCM tag`.
- Extension: `.aplockerbackup` (replaces plain `.json`).
- Import: detect magic header; if present decrypt first, then JSON-decode.

### 3.5 Encrypted intruder photos
- `IntruderManager.saveIntruderPhoto(data:)` encrypts photo bytes with AES-GCM before writing.
- Filename: `intruder-<timestamp>.aplkimg` (opaque, no `.jpg`).
- Key derived from vault key (same per-device Keychain salt, context `"intruder"`).
- `IntruderPhotoView` decrypts on demand when displaying.

### 3.6 Authenticated remote commands
- A 32-byte shared secret `com.applocker.commandSecret` is generated on first Mac launch and stored in the Keychain with `kSecAttrSynchronizable = true` (syncs to iOS Keychain via iCloud Keychain).
- Commands include field `hmac: String` = HMAC-SHA256(commandSecret, commandID + action + timestamp).
- Receiver verifies HMAC before executing. Commands with invalid HMAC or timestamp > 60 s old are rejected.

### 3.7 Wake / sleep lock
- Subscribe to `NSWorkspace.didWakeNotification`.
- On wake: if `autoLockOnSleep` is true → `AuthenticationManager.shared.logout()`.
- Existing `willSleepNotification` already clears `temporarilyUnlockedApps`; wake handler adds the auth logout.

---

## 4. iOS Companion — Full Dashboard

### Target: iOS 16+, SwiftUI, same SPM target with `#if os(iOS)` guards.

### 4.1 App protection
| Feature | Implementation |
|---|---|
| Biometric gate | `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` on cold launch and after 60 s in background |
| iOS PIN fallback | 4–6 digit PIN stored in iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Jailbreak detection | Check `/Applications/Cydia.app`, `fork()` success outside sandbox, writable `/private`, `MobileSubstrate` dylib |
| Screen recording | `UIScreen.main.isCaptured` observer → full-screen privacy overlay |
| Background snapshot | `applicationDidEnterBackground`: add blur `UIVisualEffectView` over key window; remove on foreground |

### 4.2 Tabs

| Tab | Content |
|---|---|
| **Dashboard** | Monitoring ON/OFF badge, locked-app count, last-event card, device selector for multi-Mac |
| **Alerts** | `List` of `BlockedAppEvent` / `FailedAuthEvent` CKRecords, real-time via CloudKit subscription push; swipe-to-delete from history |
| **Remote Control** | Searchable locked-apps list (from `LockedAppList` CKRecord); per-app Lock/Unlock buttons; Lock All / Unlock All with Face ID confirmation |
| **Secure Notes** | Full note list, tap to read/edit; AES-GCM decrypt on demand; requires master passcode entry once per session |
| **Intruder Photos** | Grid of captured photos fetched from CloudKit as `CKAsset`; decrypt and display; delete with confirmation |
| **Settings** | iOS PIN change, Face ID toggle, notification preferences, CloudKit sync status |

### 4.3 CloudKit sync
- `CloudKitManager` singleton handles record creation (Mac) and subscriptions (iOS).
- Mac creates records; iOS subscribes with `CKQuerySubscription` and `CKSubscription.NotificationInfo`.
- Background fetch / push entitlement required in entitlements file.
- Records pruned after 30 days (Mac runs cleanup task on launch).

---

## 5. Files to Create / Modify

### New files
| File | Purpose |
|---|---|
| `Sources/AppLocker/Shared/CloudKitManager.swift` | CK record CRUD + subscriptions |
| `Sources/AppLocker/Shared/InactivityMonitor.swift` | Global idle timer |
| `Sources/AppLocker/Shared/PBKDF2Helper.swift` | PBKDF2 derivation + migration logic |
| `Sources/AppLocker/iOS/iOSAppDelegate.swift` | Background push handling |
| `Sources/AppLocker/iOS/Dashboard/DashboardView.swift` | Dashboard tab |
| `Sources/AppLocker/iOS/Alerts/AlertsView.swift` | Alerts feed tab |
| `Sources/AppLocker/iOS/RemoteControl/RemoteControlView.swift` | Remote control tab |
| `Sources/AppLocker/iOS/SecureNotes/iOSSecureNotesView.swift` | Notes viewer/editor |
| `Sources/AppLocker/iOS/IntruderPhotos/iOSIntruderView.swift` | Photos gallery |
| `Sources/AppLocker/iOS/Settings/iOSSettingsView.swift` | iOS settings |
| `Sources/AppLocker/iOS/Protection/AppProtectionManager.swift` | Biometric + PIN + jailbreak |

### Modified files
| File | Change |
|---|---|
| `AuthenticationManager.swift` | PBKDF2 hash, migration path, wake-lock hook |
| `AppMonitor.swift` | Write CloudKit records on block/failed-auth; wake handler |
| `IntruderManager.swift` | Encrypt photos before save; decrypt on read |
| `NotificationManager.swift` | Remove CloudKit record creation delegation; keep iCloud KV for backwards compat |
| `MacAppLockerApp.swift` | Start InactivityMonitor; anti-debugger call |
| `MacContentView.swift` | Inactivity timeout setting in SettingsView; encrypted export/import |
| `iOSContentView.swift` | Replace with tab-based `iOSRootView` |
| `AppLockerApp_iOS.swift` | Add background push + CloudKit entitlements wiring |
| `Package.swift` | Add `CloudKit` framework linkage if needed (it's a system framework, just import) |

---

## 6. Out of Scope

- Server-side APNs backend (CloudKit covers push without a server)
- App Store submission / signing (existing Makefile handles this)
- Android version
- Screen Time API integration (Apple does not allow third-party apps to use `FamilyControls` outside of MDM/Family enrollment)
