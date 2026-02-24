# Security Tools Design — AppLocker

**Date:** 2026-02-25
**Status:** Approved
**Scope:** 6 new security features added as macOS feature modules

---

## Context

AppLocker already provides: app blocking/monitoring, passcode + biometric auth, per-app passcodes, scheduling, categories, intruder photo capture, cross-device notifications, activity log, usage stats, config export/import, and menu-bar integration.

This design adds a second tier of security tools operating on files, clipboard, screen, network, and notes.

---

## Architecture Decision

**Approach: Feature modules** — each feature in its own pair of files under `Sources/AppLocker/<Feature>/`. `MacContentView.swift` gets 6 new sidebar tabs (indices 7–12). No external dependencies; CryptoKit and standard macOS frameworks only.

```
Sources/AppLocker/
  SecureVault/
    VaultManager.swift
    VaultView.swift
  FileLocker/
    FileLockerManager.swift
    FileLockerView.swift
  ClipboardGuard/
    ClipboardGuard.swift
    ClipboardGuardView.swift
  ScreenPrivacy/
    ScreenPrivacyManager.swift
    ScreenPrivacyView.swift
  NetworkMonitor/
    NetworkMonitor.swift
    NetworkMonitorView.swift
  SecureNotes/
    SecureNotesManager.swift
    SecureNotesView.swift
  Shared/
    CryptoHelper.swift        ← new shared encryption utility
    Models.swift              ← extended with 5 new model types
```

---

## Shared Encryption Primitive — `CryptoHelper.swift`

All encryption uses `CryptoKit`. A single helper used by Vault, FileLocker, and SecureNotes.

```
deriveKey(passcode, salt, context) → SymmetricKey
  HKDF<SHA256>(inputKeyMaterial: passcode bytes, salt: salt, info: context, outputByteCount: 32)

encrypt(data, key) → Data
  AES.GCM.seal(data, using: key).combined   // nonce(12) + ciphertext + tag(16)

decrypt(data, key) → Data
  AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)

randomSalt() → Data
  32 bytes from SecRandomCopyBytes
```

Key material never persisted — only the 32-byte salt is persisted (Keychain for vault, file header for file locker, UserDefaults for notes).

---

## Feature 1 — Secure Vault

### Purpose
Password-protected encrypted folder. Files are copied in and encrypted at rest. Originals are untouched.

### Storage
- Directory: `~/Library/Application Support/AppLocker/Vault/`
- Per-file: `<uuid>.enc` containing AES-GCM combined output
- Metadata: `vault_meta.json` in the same directory holding `[VaultFile]`

### Key lifecycle
1. On first vault creation, generate a 32-byte vault salt → store in Keychain under `"com.applocker.vaultSalt"`
2. `VaultManager.unlock(passcode:)` → calls `AuthenticationManager.verifyPasscode()` → derives `SymmetricKey` via `HKDF` → held in `private var sessionKey: SymmetricKey?`
3. `VaultManager.lock()` → zeroes and nils `sessionKey`, sets `isUnlocked = false`

### Operations
| Action | Implementation |
|--------|---------------|
| Add file | Read → `encrypt()` → write `<uuid>.enc` → append `VaultFile` to metadata |
| Open file | `decrypt()` → write to `FileManager.default.temporaryDirectory/<name>` → `NSWorkspace.open` |
| Export | `decrypt()` → `NSSavePanel` to user-chosen path |
| Delete | Remove `<uuid>.enc` + remove `VaultFile` from metadata |

### UI
- `LazyVGrid` of file cards with `NSWorkspace.icon(forFile:)` thumbnails
- `onDrop(of: [.fileURL])` drag-and-drop target
- Unlock sheet with `SecureField` + biometrics button
- Toolbar: Add, Export, Delete

---

## Feature 2 — File Locker (In-Place Encryption)

### Purpose
Encrypt any file on disk in-place. The file is replaced by a `.aplk` container. Decrypt restores the original.

### File format — `.aplk` container
```
[0..3]   Magic:   0x41 0x50 0x4C 0x4B  ("APLK")
[4]      Version: 0x01
[5..36]  Salt:    32 bytes (random per file)
[37..]   Payload: AES.GCM.SealedBox.combined (nonce 12B + ciphertext + tag 16B)
```

### Key derivation
`deriveKey(passcode, salt_from_header, context: "filelockr")` — passcode prompted once per session, then held in `FileLockerManager.sessionKey`.

### Encrypt flow
1. `NSOpenPanel` (allows files + directories)
2. For each file: read → derive fresh salt → encrypt → write `<path>.aplk` → securely delete original (overwrite with zeros, then `FileManager.removeItem`)
3. Append `LockedFileRecord` to persisted list

### Decrypt flow
1. `NSOpenPanel` filtered to `.aplk` files
2. Read 37-byte header → extract salt → derive key → decrypt → write to original path (strip `.aplk`) → delete `.aplk`

### Folder support
Recurse into selected directories; only non-`.aplk` files are encrypted, only `.aplk` files are decrypted.

### UI
- Two-pane: left = persisted list of locked files with status badges; right = drop zone
- "Lock Selected" / "Unlock Selected" buttons
- Progress indicator for large files

---

## Feature 3 — Clipboard Guard

### Mechanism
- `Timer.publish(every: 1, on: .main, in: .common)` checks `NSPasteboard.general.changeCount`
- On change: record `ClipboardEvent(timestamp: now, charCount: estimated)`, start countdown
- After `clearDelay` seconds: `NSPasteboard.general.clearContents()`

### Configuration
- Toggle: enabled/disabled
- Clear delay: 10 / 30 / 60 / 120 seconds (picker)

### History
Stores last 20 `ClipboardEvent` entries (timestamp + char count only — not the actual content).

### UI
- Status card: "Active — clears in Xs" or "Idle"
- Toggle + delay picker
- Recent activity list (time, rough size)

---

## Feature 4 — Screen Privacy

### NSWindow protection
At app launch, `mainWindow.sharingType = .none` prevents AppLocker's window from appearing in screenshots or screen recordings. Applied in `applicationDidFinishLaunching`.

### Recording detection
`ScreenPrivacyManager` scans `NSWorkspace.shared.runningApplications` every 5 seconds for known capture processes:

```swift
let knownRecorders: Set<String> = [
    "com.apple.screencapture", "com.apple.QuickTimePlayerX",
    "us.zoom.xos", "com.microsoft.teams", "com.elgato.StreamDeck",
    "com.obsproject.obs-studio", "net.telestream.screenflow",
    "com.techsmith.camtasia"
]
```

### Auto-lock on detection
Optional: if a recorder is detected and the option is enabled, call `AuthenticationManager.shared.logout()` to lock AppLocker immediately.

### UI
- Status card: "Window Protected" (always) + "Recording Detected / Clear"
- Toggle for auto-lock-on-detection
- List of currently detected capture processes

---

## Feature 5 — Network Monitor

### Data source
`Process` runs `/usr/sbin/lsof -i -n -P -F pcnPT` every 3 seconds on a background `Task`. Output parsed into `[NetworkConnection]`.

### Per-connection fields
`processName`, `pid`, `localAddress`, `remoteIP`, `remotePort`, `protocol` (TCP/UDP), `state` (ESTABLISHED / LISTEN / etc.)

### IP annotation
`whois` run once per unique remote IP (cached in `[String: String]` dict). Extracts `OrgName` or `netname` from whois output. Known private ranges (10.x, 172.16–31.x, 192.168.x, 127.x) labelled "Local".

### Filtering
Toggle: "Show locked apps only" (default) vs all user-space processes.

### Actions
- "Terminate App" button → calls existing `AppMonitor.shared.addLockedApp` + immediate block
- No actual packet filtering (requires root/`pfctl` — out of scope)

### UI
- `List` grouped by app (disclosure groups)
- Each row: remote IP, org name, port, protocol, state, timestamp
- Auto-refresh with "Pause" toggle
- Color-coded: ESTABLISHED = green, CLOSE_WAIT/TIME_WAIT = orange, LISTEN = blue

---

## Feature 6 — Secure Notes

### Storage
JSON file at `~/Library/Application Support/AppLocker/notes_meta.json`. Each entry stores:
- `id: UUID`, `title: String` (plaintext, for list display), `encryptedBody: Data`, `createdAt`, `modifiedAt`

### Key lifecycle
Same salt/key pattern as vault: `"com.applocker.notesSalt"` in Keychain. `SecureNotesManager.unlock(passcode:)` derives key, holds in memory. Both vault and notes can share the same session once unlocked (separate unlock calls, separate keys, but same passcode prompts the same underlying verify flow).

### Auto-save
1-second debounce: `DispatchWorkItem` cancelled and reset on each keystroke. On fire: encrypt body → update `encryptedBody` in metadata → write to disk.

### UI
- `NavigationSplitView`-style: left = note list (title + date), right = `TextEditor`
- Toolbar: New Note, Delete Note
- Locked state: shows "Unlock Notes" placeholder
- Note title editable inline in the list

---

## New Model Types (added to Models.swift)

```swift
struct VaultFile: Codable, Identifiable {
    let id: UUID; let originalName: String; let encryptedFilename: String
    let fileSize: Int; let dateAdded: Date; let fileExtension: String
}

struct LockedFileRecord: Codable, Identifiable {
    let id: UUID; let originalPath: String; let lockedPath: String; let dateEncrypted: Date
}

struct ClipboardEvent: Identifiable {
    let id = UUID(); let timestamp: Date; let estimatedCharCount: Int
}

struct NetworkConnection: Identifiable {
    let id = UUID(); let processName: String; let pid: Int32
    let remoteIP: String; let remotePort: String; let remoteOrg: String
    let localAddress: String; let proto: String; let state: String
}

struct EncryptedNote: Codable, Identifiable {
    let id: UUID; var title: String; var encryptedBody: Data
    let createdAt: Date; var modifiedAt: Date
}
```

---

## MacContentView.swift changes

Add 6 sidebar entries:
```swift
SidebarButton(title: "Secure Vault",     icon: "lock.doc.fill",            isSelected: selectedTab == 7)  { selectedTab = 7  }
SidebarButton(title: "File Locker",      icon: "doc.badge.lock",            isSelected: selectedTab == 8)  { selectedTab = 8  }
SidebarButton(title: "Clipboard Guard",  icon: "clipboard.fill",            isSelected: selectedTab == 9)  { selectedTab = 9  }
SidebarButton(title: "Screen Privacy",   icon: "eye.slash.fill",            isSelected: selectedTab == 10) { selectedTab = 10 }
SidebarButton(title: "Network Monitor",  icon: "network",                   isSelected: selectedTab == 11) { selectedTab = 11 }
SidebarButton(title: "Secure Notes",     icon: "lock.rectangle.stack.fill", isSelected: selectedTab == 12) { selectedTab = 12 }
```

---

## Non-Goals

- Actual packet filtering / firewall rules (requires root + `pfctl`)
- Cloud sync of vault contents
- Sharing notes between devices
- File format interoperability with other apps
