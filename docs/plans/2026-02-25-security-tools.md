# Security Tools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add six production-ready security features — Secure Vault, File Locker, Clipboard Guard, Screen Privacy, Network Monitor, and Secure Notes — to the existing AppLocker macOS app.

**Architecture:** Feature modules under `Sources/AppLocker/<Feature>/`. A shared `CryptoHelper.swift` provides AES-256-GCM encryption and HKDF key derivation (CryptoKit only). Each feature is `#if os(macOS)` guarded. `MacContentView.swift` gains 6 new sidebar tabs (indices 7–12).

**Tech Stack:** Swift 5.9, SwiftUI, CryptoKit (AES.GCM + HKDF), AppKit (NSOpenPanel, NSPasteboard, NSWorkspace, NSWindow), Foundation (Process for lsof/whois), Security (Keychain for salts)

---

## Task 1: Shared Crypto Foundation + New Model Types

**Files:**
- Create: `Sources/AppLocker/Shared/CryptoHelper.swift`
- Modify: `Sources/AppLocker/Shared/Models.swift`

**Step 1: Create `CryptoHelper.swift`**

```swift
// Sources/AppLocker/Shared/CryptoHelper.swift
import Foundation
import CryptoKit
import Security

enum CryptoError: LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keyDerivationFailed
    case saltGenerationFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let r): return "Encryption failed: \(r)"
        case .decryptionFailed(let r): return "Decryption failed: \(r)"
        case .keyDerivationFailed: return "Key derivation failed"
        case .saltGenerationFailed: return "Could not generate random salt"
        }
    }
}

enum CryptoHelper {

    // MARK: - Key Derivation

    /// Derives a 256-bit symmetric key from a passcode + salt using HKDF-SHA256.
    /// context differentiates vault keys from notes keys etc.
    static func deriveKey(passcode: String, salt: Data, context: String) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(passcode.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data(context.utf8),
            outputByteCount: 32
        )
    }

    // MARK: - Encryption / Decryption

    /// Encrypts plaintext with AES-256-GCM.
    /// Returns nonce(12) + ciphertext + tag(16) as a single Data blob.
    static func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealedBox.combined else {
                throw CryptoError.encryptionFailed("combined is nil")
            }
            return combined
        } catch {
            throw CryptoError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypts AES-256-GCM combined blob produced by encrypt().
    static func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw CryptoError.decryptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Salt

    /// Generates 32 cryptographically random bytes.
    static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard status == errSecSuccess else { throw CryptoError.saltGenerationFailed }
        return Data(bytes)
    }

    // MARK: - Keychain Helpers

    private static let service = "com.applocker.crypto"

    static func saveSaltToKeychain(key: String, salt: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: salt,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadSaltFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    static func getOrCreateSalt(keychainKey: String) throws -> Data {
        if let existing = loadSaltFromKeychain(key: keychainKey) {
            return existing
        }
        let salt = try randomSalt()
        saveSaltToKeychain(key: keychainKey, salt: salt)
        return salt
    }

    // MARK: - Secure File Overwrite

    /// Overwrites a file with zeros before deleting it (best-effort).
    static func secureDelete(url: URL) {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let fh = try? FileHandle(forWritingTo: url) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let zeros = Data(repeating: 0, count: min(size ?? 0, 1024 * 1024))
        var written = 0
        let total = size ?? 0
        while written < total {
            fh.write(zeros)
            written += zeros.count
        }
        try? fh.close()
        try? FileManager.default.removeItem(at: url)
    }
}
```

**Step 2: Add new model types to `Models.swift`**

Append after the last struct in `Sources/AppLocker/Shared/Models.swift`:

```swift
// MARK: - Vault

struct VaultFile: Codable, Identifiable {
    let id: UUID
    let originalName: String
    let encryptedFilename: String   // UUID string, no extension, stored in vault dir
    let fileSize: Int               // original plaintext size in bytes
    let dateAdded: Date
    let fileExtension: String       // e.g. "pdf", "png"
}

// MARK: - File Locker

struct LockedFileRecord: Codable, Identifiable {
    let id: UUID
    let originalPath: String        // where the original was before encryption
    let lockedPath: String          // current .aplk path
    let dateEncrypted: Date
}

// MARK: - Clipboard Guard

struct ClipboardEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let estimatedCharCount: Int     // approximate, not the actual content
}

// MARK: - Network Monitor

struct NetworkConnection: Identifiable {
    let id = UUID()
    let processName: String
    let pid: Int32
    let remoteIP: String
    let remotePort: String
    var remoteOrg: String           // populated asynchronously via whois
    let localAddress: String
    let proto: String               // "TCP" / "UDP"
    let state: String               // "ESTABLISHED" / "LISTEN" / etc.
}

// MARK: - Secure Notes

struct EncryptedNote: Codable, Identifiable {
    let id: UUID
    var title: String
    var encryptedBody: Data         // AES-GCM combined (nonce + ciphertext + tag)
    let createdAt: Date
    var modifiedAt: Date
}
```

**Step 3: Build to verify no errors**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add Sources/AppLocker/Shared/CryptoHelper.swift Sources/AppLocker/Shared/Models.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: add CryptoHelper (AES-GCM/HKDF) and new security model types"
```

---

## Task 2: Secure Vault — Manager

**Files:**
- Create: `Sources/AppLocker/SecureVault/VaultManager.swift`

**Step 1: Write `VaultManager.swift`**

```swift
// Sources/AppLocker/SecureVault/VaultManager.swift
#if os(macOS)
import Foundation
import AppKit
import CryptoKit

@MainActor
class VaultManager: ObservableObject {
    static let shared = VaultManager()

    @Published var isUnlocked = false
    @Published var files: [VaultFile] = []
    @Published var lastError: String?

    private var sessionKey: SymmetricKey?
    private let keychainSaltKey = "com.applocker.vaultSalt"
    private let metaFilename = "vault_meta.json"

    var vaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("AppLocker/Vault", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Session Management

    func unlock(passcode: String) -> Bool {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"
            return false
        }
        do {
            let salt = try CryptoHelper.getOrCreateSalt(keychainKey: keychainSaltKey)
            sessionKey = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.vault.v1")
            isUnlocked = true
            lastError = nil
            loadMetadata()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func unlockWithBiometrics(completion: @escaping (Bool) -> Void) {
        AuthenticationManager.shared.authenticateWithBiometrics { [weak self] success, errorMsg in
            guard let self else { return }
            if success {
                // Biometrics succeeded but we need the raw passcode for HKDF.
                // We store a biometric-only derived key using a device-bound salt.
                // Since biometrics proves identity, we use a fixed context tied to device.
                do {
                    let salt = try CryptoHelper.getOrCreateSalt(keychainKey: self.keychainSaltKey)
                    // For biometric unlock, reuse same salt but different context marker.
                    // Key is identical because salt is the same; biometrics just bypasses passcode entry.
                    // SECURITY NOTE: This requires that the passcode was used at least once to generate the salt.
                    // If no passcode-based unlock has happened, biometric unlock falls back to passcode prompt.
                    if self.sessionKey == nil {
                        // We don't have a session key from passcode. Use a placeholder derived from device identity.
                        // This path should not occur in normal flow (biometrics only available after passcode login).
                        completion(false)
                        return
                    }
                    self.isUnlocked = true
                    self.lastError = nil
                    self.loadMetadata()
                    completion(true)
                } catch {
                    self.lastError = error.localizedDescription
                    completion(false)
                }
            } else {
                self.lastError = errorMsg
                completion(false)
            }
        }
    }

    func lock() {
        sessionKey = nil
        isUnlocked = false
        files = []
    }

    // MARK: - File Operations

    func addFile(from sourceURL: URL) {
        guard let key = sessionKey else { lastError = "Vault is locked"; return }
        do {
            let data = try Data(contentsOf: sourceURL)
            let encrypted = try CryptoHelper.encrypt(data, using: key)
            let encFilename = UUID().uuidString
            let destURL = vaultDirectory.appendingPathComponent(encFilename)
            try encrypted.write(to: destURL)

            let vaultFile = VaultFile(
                id: UUID(),
                originalName: sourceURL.lastPathComponent,
                encryptedFilename: encFilename,
                fileSize: data.count,
                dateAdded: Date(),
                fileExtension: sourceURL.pathExtension.lowercased()
            )
            files.append(vaultFile)
            saveMetadata()
            lastError = nil
        } catch {
            lastError = "Failed to add \(sourceURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func openFile(_ vaultFile: VaultFile) {
        guard let key = sessionKey else { lastError = "Vault is locked"; return }
        do {
            let encURL = vaultDirectory.appendingPathComponent(vaultFile.encryptedFilename)
            let encrypted = try Data(contentsOf: encURL)
            let decrypted = try CryptoHelper.decrypt(encrypted, using: key)
            // Write to a temp file preserving original name
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("AppLockerVault", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent(vaultFile.originalName)
            try decrypted.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
            lastError = nil
        } catch {
            lastError = "Failed to open \(vaultFile.originalName): \(error.localizedDescription)"
        }
    }

    func exportFile(_ vaultFile: VaultFile) {
        guard let key = sessionKey else { lastError = "Vault is locked"; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = vaultFile.originalName
        panel.begin { [weak self] response in
            guard response == .OK, let destURL = panel.url else { return }
            do {
                let encURL = self!.vaultDirectory.appendingPathComponent(vaultFile.encryptedFilename)
                let encrypted = try Data(contentsOf: encURL)
                let decrypted = try CryptoHelper.decrypt(encrypted, using: key)
                try decrypted.write(to: destURL)
                self?.lastError = nil
            } catch {
                self?.lastError = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func deleteFile(_ vaultFile: VaultFile) {
        let encURL = vaultDirectory.appendingPathComponent(vaultFile.encryptedFilename)
        CryptoHelper.secureDelete(url: encURL)
        files.removeAll { $0.id == vaultFile.id }
        saveMetadata()
    }

    // MARK: - Metadata Persistence

    private func loadMetadata() {
        let metaURL = vaultDirectory.appendingPathComponent(metaFilename)
        guard let data = try? Data(contentsOf: metaURL),
              let decoded = try? JSONDecoder().decode([VaultFile].self, from: data) else {
            files = []
            return
        }
        files = decoded
    }

    private func saveMetadata() {
        let metaURL = vaultDirectory.appendingPathComponent(metaFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(files) {
            try? data.write(to: metaURL)
        }
    }

    // MARK: - Helpers

    func formattedSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo.fill"
        case "mp4", "mov", "avi", "mkv": return "video.fill"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "zip", "tar", "gz", "7z", "rar": return "archivebox.fill"
        case "txt", "md": return "doc.text.fill"
        case "swift", "py", "js", "ts", "html", "css": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
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
git add Sources/AppLocker/SecureVault/VaultManager.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: add VaultManager with AES-GCM encrypt/decrypt and Keychain salt"
```

---

## Task 3: Secure Vault — View

**Files:**
- Create: `Sources/AppLocker/SecureVault/VaultView.swift`

**Step 1: Write `VaultView.swift`**

```swift
// Sources/AppLocker/SecureVault/VaultView.swift
#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct VaultView: View {
    @ObservedObject var vault = VaultManager.shared
    @State private var passcode = ""
    @State private var showUnlockSheet = false
    @State private var isDragTargeted = false
    @State private var selectedFileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Secure Vault")
                    .font(.headline)
                Spacer()
                if vault.isUnlocked {
                    Text("\(vault.files.count) files · \(totalSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Lock Vault") { vault.lock() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        panel.begin { response in
                            guard response == .OK else { return }
                            for url in panel.urls { vault.addFile(from: url) }
                        }
                    } label: {
                        Label("Add Files", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()

            Divider()

            if !vault.isUnlocked {
                lockedPlaceholder
            } else {
                unlockedContent
            }
        }
        .sheet(isPresented: $showUnlockSheet) { unlockSheet }
        .alert("Vault Error", isPresented: Binding(
            get: { vault.lastError != nil },
            set: { if !$0 { vault.lastError = nil } }
        )) {
            Button("OK") { vault.lastError = nil }
        } message: {
            Text(vault.lastError ?? "")
        }
    }

    // MARK: - Sub-views

    private var lockedPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            Text("Secure Vault")
                .font(.title2).fontWeight(.semibold)
            Text("Files are encrypted with AES-256-GCM.\nUnlock to access your vault.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Button("Unlock Vault") { showUnlockSheet = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var unlockedContent: some View {
        Group {
            if vault.files.isEmpty {
                dropZone
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160))], spacing: 12) {
                        ForEach(vault.files) { file in
                            VaultFileCard(file: file, isSelected: selectedFileID == file.id)
                                .onTapGesture { selectedFileID = file.id }
                                .contextMenu {
                                    Button("Open") { vault.openFile(file) }
                                    Button("Export...") { vault.exportFile(file) }
                                    Divider()
                                    Button("Delete", role: .destructive) { vault.deleteFile(file) }
                                }
                        }
                    }
                    .padding()
                }
                .background(
                    dropZoneOverlay
                )
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isDragTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 48))
                .foregroundColor(isDragTargeted ? .blue : .secondary)
            Text("Drop files here or click Add Files")
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(isDragTargeted ? Color.blue.opacity(0.05) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { vault.addFile(from: url) }
                }
            }
            return true
        }
    }

    private var dropZoneOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isDragTargeted ? Color.blue : Color.clear, lineWidth: 2)
            .background(isDragTargeted ? Color.blue.opacity(0.05) : Color.clear)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { vault.addFile(from: url) }
                    }
                }
                return true
            }
    }

    private var unlockSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text("Unlock Vault")
                .font(.title2).fontWeight(.semibold)
            SecureField("Master Passcode", text: $passcode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 240)
                .onSubmit { attemptUnlock() }
            if let error = vault.lastError {
                Text(error).foregroundColor(.red).font(.caption)
            }
            HStack {
                Button("Cancel") { showUnlockSheet = false; passcode = "" }
                    .keyboardShortcut(.cancelAction)
                Button("Unlock") { attemptUnlock() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(passcode.isEmpty)
            }
            if AuthenticationManager.shared.canUseBiometrics() {
                Button { vault.unlockWithBiometrics { success in if success { showUnlockSheet = false } } }
                label: { Label("Use Biometrics", systemImage: "touchid") }
                .buttonStyle(.borderless)
            }
        }
        .padding(32)
        .frame(width: 320)
    }

    // MARK: - Helpers

    private func attemptUnlock() {
        if vault.unlock(passcode: passcode) {
            passcode = ""
            showUnlockSheet = false
        }
    }

    private var totalSize: String {
        let total = vault.files.reduce(0) { $0 + $1.fileSize }
        return vault.formattedSize(total)
    }
}

struct VaultFileCard: View {
    let file: VaultFile
    let isSelected: Bool
    @ObservedObject var vault = VaultManager.shared

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: vault.iconForExtension(file.fileExtension))
                .font(.system(size: 36))
                .foregroundColor(.blue)
                .frame(height: 44)
            Text(file.originalName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(vault.formattedSize(file.fileSize))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(width: 120, height: 110)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }
}
#endif
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 3: Wire into `MacContentView.swift`**

In `MainInterface.body`, add after the existing `SidebarButton` for Categories (tab 6):

```swift
SidebarButton(title: "Secure Vault",    icon: "lock.doc.fill",            isSelected: selectedTab == 7)  { selectedTab = 7  }
```

In the `switch selectedTab` in `MainInterface`:
```swift
case 7: VaultView()
```

**Step 4: Build and verify sidebar shows "Secure Vault"**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 5: Commit**

```bash
git add Sources/AppLocker/SecureVault/
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: Secure Vault with AES-GCM file encryption, drag-drop, open/export/delete"
```

---

## Task 4: File Locker — Manager

**Files:**
- Create: `Sources/AppLocker/FileLocker/FileLockerManager.swift`

**APLK file format:**
```
Offset  Length  Field
0       4       Magic bytes: 0x41 0x50 0x4C 0x4B ("APLK")
4       1       Version: 0x01
5       32      Salt (random per file)
37      N       AES-GCM combined output (12-byte nonce + ciphertext + 16-byte tag)
```

**Step 1: Write `FileLockerManager.swift`**

```swift
// Sources/AppLocker/FileLocker/FileLockerManager.swift
#if os(macOS)
import Foundation

enum FileLockerError: LocalizedError {
    case invalidFormat(String)
    case wrongPasscode
    case fileNotFound(String)
    case alreadyLocked(String)
    case notLocked(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let f): return "Invalid .aplk file: \(f)"
        case .wrongPasscode: return "Incorrect passcode — cannot decrypt"
        case .fileNotFound(let p): return "File not found: \(p)"
        case .alreadyLocked(let f): return "\(f) is already locked"
        case .notLocked(let f): return "\(f) is not a .aplk file"
        }
    }
}

@MainActor
class FileLockerManager: ObservableObject {
    static let shared = FileLockerManager()

    @Published var lockedFiles: [LockedFileRecord] = []
    @Published var lastError: String?
    @Published var isProcessing = false

    private let recordsKey = "com.applocker.lockedFiles"
    private let aplkMagic = Data([0x41, 0x50, 0x4C, 0x4B]) // "APLK"
    private let aplkVersion: UInt8 = 0x01
    private let headerSize = 37 // 4 magic + 1 version + 32 salt

    private init() { loadRecords() }

    // MARK: - Encrypt

    func lockFiles(passcode: String) {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Select Files to Lock"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in
                self?.isProcessing = true
                for url in panel.urls {
                    await self?.encryptItem(at: url, passcode: passcode)
                }
                self?.isProcessing = false
                self?.saveRecords()
            }
        }
    }

    private func encryptItem(at url: URL, passcode: String) async {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            lastError = FileLockerError.fileNotFound(url.lastPathComponent).localizedDescription
            return
        }
        if isDir.boolValue {
            // Recurse into directory
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil
            ) else { return }
            for item in contents { await encryptItem(at: item, passcode: passcode) }
        } else {
            await encryptFile(at: url, passcode: passcode)
        }
    }

    private func encryptFile(at url: URL, passcode: String) async {
        guard url.pathExtension != "aplk" else {
            lastError = FileLockerError.alreadyLocked(url.lastPathComponent).localizedDescription
            return
        }
        do {
            let plaintext = try Data(contentsOf: url)
            let salt = try CryptoHelper.randomSalt()
            let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.filelockr.v1")
            let ciphertext = try CryptoHelper.encrypt(plaintext, using: key)

            // Build container
            var container = aplkMagic
            container.append(aplkVersion)
            container.append(salt)
            container.append(ciphertext)

            let lockedURL = url.appendingPathExtension("aplk")
            try container.write(to: lockedURL)
            CryptoHelper.secureDelete(url: url)

            let record = LockedFileRecord(
                id: UUID(),
                originalPath: url.path,
                lockedPath: lockedURL.path,
                dateEncrypted: Date()
            )
            lockedFiles.append(record)
        } catch {
            lastError = "Failed to lock \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Decrypt

    func unlockFiles(passcode: String) {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Select .aplk Files to Unlock"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        // Filter in panel callback since UTType for custom extension isn't registered
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in
                self?.isProcessing = true
                for url in panel.urls where url.pathExtension == "aplk" {
                    self?.decryptFile(at: url, passcode: passcode)
                }
                self?.isProcessing = false
                self?.saveRecords()
            }
        }
    }

    private func decryptFile(at lockedURL: URL, passcode: String) {
        do {
            let container = try Data(contentsOf: lockedURL)
            guard container.count > headerSize else {
                throw FileLockerError.invalidFormat("too small")
            }
            // Verify magic
            let magic = container.prefix(4)
            guard magic == aplkMagic else {
                throw FileLockerError.invalidFormat("bad magic bytes")
            }
            // Extract salt
            let salt = container[5..<37]
            let ciphertext = container[37...]

            let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.filelockr.v1")
            let plaintext: Data
            do {
                plaintext = try CryptoHelper.decrypt(Data(ciphertext), using: key)
            } catch {
                throw FileLockerError.wrongPasscode
            }

            // Restore original path by stripping .aplk
            let originalURL = lockedURL.deletingPathExtension()
            try plaintext.write(to: originalURL)
            CryptoHelper.secureDelete(url: lockedURL)

            // Remove from records
            lockedFiles.removeAll { $0.lockedPath == lockedURL.path }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([LockedFileRecord].self, from: data) else { return }
        // Filter out records whose locked file no longer exists
        lockedFiles = records.filter { FileManager.default.fileExists(atPath: $0.lockedPath) }
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(lockedFiles) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    func clearMissingRecords() {
        lockedFiles = lockedFiles.filter { FileManager.default.fileExists(atPath: $0.lockedPath) }
        saveRecords()
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
git add Sources/AppLocker/FileLocker/FileLockerManager.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: FileLockerManager with APLK container format, in-place AES-GCM encrypt/decrypt"
```

---

## Task 5: File Locker — View

**Files:**
- Create: `Sources/AppLocker/FileLocker/FileLockerView.swift`

**Step 1: Write `FileLockerView.swift`**

```swift
// Sources/AppLocker/FileLocker/FileLockerView.swift
#if os(macOS)
import SwiftUI

struct FileLockerView: View {
    @ObservedObject var locker = FileLockerManager.shared
    @State private var passcode = ""
    @State private var showPasscodeSheet = false
    @State private var pendingAction: LockerAction = .lock
    @State private var isDragTargeted = false

    enum LockerAction { case lock, unlock }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showPasscodeSheet) { passcodeSheet }
        .alert("File Locker Error", isPresented: Binding(
            get: { locker.lastError != nil },
            set: { if !$0 { locker.lastError = nil } }
        )) {
            Button("OK") { locker.lastError = nil }
        } message: {
            Text(locker.lastError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("File Locker")
                .font(.headline)
            Spacer()
            if locker.isProcessing {
                ProgressView().controlSize(.small)
                Text("Processing…").font(.caption).foregroundColor(.secondary)
            }
            Button {
                pendingAction = .lock
                showPasscodeSheet = true
            } label: { Label("Lock Files", systemImage: "lock.fill") }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(locker.isProcessing)

            Button {
                pendingAction = .unlock
                showPasscodeSheet = true
            } label: { Label("Unlock .aplk", systemImage: "lock.open.fill") }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(locker.isProcessing)
        }
        .padding()
    }

    private var content: some View {
        HSplitView {
            // Left: locked file records
            VStack(alignment: .leading) {
                HStack {
                    Text("Locked Files (\(locker.lockedFiles.count))")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button("Refresh") { locker.clearMissingRecords() }
                        .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                }
                .padding([.horizontal, .top])

                if locker.lockedFiles.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.badge.lock")
                            .font(.system(size: 36)).foregroundColor(.secondary)
                        Text("No locked files tracked").foregroundColor(.secondary).font(.caption)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                } else {
                    List(locker.lockedFiles) { record in
                        LockedFileRow(record: record)
                    }
                }
            }
            .frame(minWidth: 260)

            // Right: drop zone
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: isDragTargeted ? "arrow.down.doc.fill" : "doc.badge.lock")
                    .font(.system(size: 52))
                    .foregroundColor(isDragTargeted ? .blue : .secondary)
                Text("Drop files here to lock them")
                    .foregroundColor(.secondary)
                Text("Files are encrypted with AES-256-GCM.\nThe original is securely deleted.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(isDragTargeted ? Color.blue.opacity(0.05) : Color.clear)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                showPasscodeSheet = true
                pendingAction = .lock
                // Store dropped URLs for after passcode entry
                return true
            }
        }
    }

    private var passcodeSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: pendingAction == .lock ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 44)).foregroundColor(.blue)
            Text(pendingAction == .lock ? "Lock Files" : "Unlock .aplk Files")
                .font(.title2).fontWeight(.semibold)
            Text(pendingAction == .lock
                 ? "Files will be encrypted in-place.\nOriginals are securely deleted."
                 : "Select .aplk files to decrypt and restore.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).font(.subheadline)
            SecureField("Master Passcode", text: $passcode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 240)
                .onSubmit { performAction() }
            HStack {
                Button("Cancel") { showPasscodeSheet = false; passcode = "" }
                    .keyboardShortcut(.cancelAction)
                Button(pendingAction == .lock ? "Lock" : "Unlock") { performAction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(passcode.isEmpty)
            }
        }
        .padding(32).frame(width: 340)
    }

    private func performAction() {
        let pc = passcode
        passcode = ""
        showPasscodeSheet = false
        if pendingAction == .lock {
            locker.lockFiles(passcode: pc)
        } else {
            locker.unlockFiles(passcode: pc)
        }
    }
}

struct LockedFileRow: View {
    let record: LockedFileRecord

    var body: some View {
        HStack {
            Image(systemName: "doc.badge.lock").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: record.lockedPath).lastPathComponent)
                    .font(.subheadline).lineLimit(1)
                Text("Locked \(record.dateEncrypted, style: .relative) ago")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if FileManager.default.fileExists(atPath: record.lockedPath) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
```

**Step 2: Wire into `MacContentView.swift`**

Add sidebar entry after Secure Vault (tab 7):
```swift
SidebarButton(title: "File Locker", icon: "doc.badge.lock", isSelected: selectedTab == 8) { selectedTab = 8 }
```

Add to switch:
```swift
case 8: FileLockerView()
```

**Step 3: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 4: Commit**

```bash
git add Sources/AppLocker/FileLocker/
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: FileLockerView with lock/unlock flow, drop zone, record tracking"
```

---

## Task 6: Clipboard Guard

**Files:**
- Create: `Sources/AppLocker/ClipboardGuard/ClipboardGuard.swift`
- Create: `Sources/AppLocker/ClipboardGuard/ClipboardGuardView.swift`

**Step 1: Write `ClipboardGuard.swift`**

```swift
// Sources/AppLocker/ClipboardGuard/ClipboardGuard.swift
#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
class ClipboardGuard: ObservableObject {
    static let shared = ClipboardGuard()

    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    @Published var clearDelaySeconds: Int = 30 {
        didSet { UserDefaults.standard.set(clearDelaySeconds, forKey: delayKey) }
    }
    @Published var recentEvents: [ClipboardEvent] = []
    @Published var secondsUntilClear: Int = 0

    private var monitorTimer: AnyCancellable?
    private var clearWorkItem: DispatchWorkItem?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let enabledKey = "com.applocker.clipboardGuard.enabled"
    private let delayKey = "com.applocker.clipboardGuard.delay"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        let savedDelay = UserDefaults.standard.integer(forKey: delayKey)
        clearDelaySeconds = savedDelay > 0 ? savedDelay : 30
        if isEnabled { startMonitoring() }
    }

    private func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        monitorTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func stopMonitoring() {
        monitorTimer?.cancel()
        monitorTimer = nil
        clearWorkItem?.cancel()
        clearWorkItem = nil
        secondsUntilClear = 0
    }

    private func tick() {
        let current = NSPasteboard.general.changeCount
        if current != lastChangeCount {
            lastChangeCount = current
            // Estimate content size from string items
            let charCount = NSPasteboard.general.string(forType: .string)?.count ?? 0
            let event = ClipboardEvent(timestamp: Date(), estimatedCharCount: charCount)
            recentEvents.insert(event, at: 0)
            if recentEvents.count > 20 { recentEvents = Array(recentEvents.prefix(20)) }
            scheduleClear()
        }
        // Tick down countdown
        if secondsUntilClear > 0 { secondsUntilClear -= 1 }
    }

    private func scheduleClear() {
        clearWorkItem?.cancel()
        secondsUntilClear = clearDelaySeconds
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSPasteboard.general.clearContents()
            self.secondsUntilClear = 0
            let clearEvent = ClipboardEvent(timestamp: Date(), estimatedCharCount: 0)
            self.recentEvents.insert(clearEvent, at: 0)
            if self.recentEvents.count > 20 { self.recentEvents = Array(self.recentEvents.prefix(20)) }
        }
        clearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(clearDelaySeconds), execute: item)
    }

    func clearNow() {
        clearWorkItem?.cancel()
        NSPasteboard.general.clearContents()
        secondsUntilClear = 0
    }
}
#endif
```

**Step 2: Write `ClipboardGuardView.swift`**

```swift
// Sources/AppLocker/ClipboardGuard/ClipboardGuardView.swift
#if os(macOS)
import SwiftUI

struct ClipboardGuardView: View {
    @ObservedObject var guard_ = ClipboardGuard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clipboard Guard")
                .font(.headline)

            // Status card
            HStack {
                Image(systemName: guard_.isEnabled ? "clipboard.fill" : "clipboard")
                    .font(.title2)
                    .foregroundColor(guard_.isEnabled ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(guard_.isEnabled ? "Active" : "Inactive")
                        .fontWeight(.semibold)
                    if guard_.isEnabled && guard_.secondsUntilClear > 0 {
                        Text("Clears in \(guard_.secondsUntilClear)s")
                            .font(.caption).foregroundColor(.orange)
                    } else if guard_.isEnabled {
                        Text("Monitoring clipboard")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: $guard_.isEnabled).toggleStyle(.switch).labelsHidden()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            // Settings
            VStack(alignment: .leading, spacing: 10) {
                Text("Auto-Clear Delay").font(.subheadline).foregroundColor(.secondary)
                Picker("Delay", selection: $guard_.clearDelaySeconds) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                .pickerStyle(.segmented)

                Button("Clear Clipboard Now") { guard_.clearNow() }
                    .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            // Recent activity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent Activity").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear History") { guard_.recentEvents.removeAll() }
                        .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                }
                if guard_.recentEvents.isEmpty {
                    Text("No clipboard activity recorded")
                        .foregroundColor(.secondary).font(.caption)
                } else {
                    List(guard_.recentEvents) { event in
                        HStack {
                            Image(systemName: event.estimatedCharCount == 0 ? "trash" : "doc.on.clipboard")
                                .foregroundColor(event.estimatedCharCount == 0 ? .red : .blue)
                                .font(.caption)
                            Text(event.estimatedCharCount == 0 ? "Cleared" : "~\(event.estimatedCharCount) chars")
                                .font(.caption)
                            Spacer()
                            Text(event.timestamp, style: .time)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            Spacer()
        }
        .padding()
    }
}
#endif
```

**Step 3: Wire into `MacContentView.swift`**

Add sidebar entry (tab 9):
```swift
SidebarButton(title: "Clipboard Guard", icon: "clipboard.fill", isSelected: selectedTab == 9) { selectedTab = 9 }
```

Add to switch:
```swift
case 9: ClipboardGuardView()
```

**Step 4: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 5: Commit**

```bash
git add Sources/AppLocker/ClipboardGuard/
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: ClipboardGuard with auto-clear, configurable delay, activity history"
```

---

## Task 7: Screen Privacy

**Files:**
- Create: `Sources/AppLocker/ScreenPrivacy/ScreenPrivacyManager.swift`
- Create: `Sources/AppLocker/ScreenPrivacy/ScreenPrivacyView.swift`
- Modify: `Sources/AppLocker/MacAppLockerApp.swift` (set `sharingType = .none` on app launch)

**Step 1: Write `ScreenPrivacyManager.swift`**

```swift
// Sources/AppLocker/ScreenPrivacy/ScreenPrivacyManager.swift
#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
class ScreenPrivacyManager: ObservableObject {
    static let shared = ScreenPrivacyManager()

    @Published var detectedRecorders: [String] = []
    @Published var autoLockOnRecording: Bool = false {
        didSet { UserDefaults.standard.set(autoLockOnRecording, forKey: autoLockKey) }
    }
    @Published var isWindowProtected: Bool = false

    private var scanTimer: AnyCancellable?
    private let autoLockKey = "com.applocker.screenPrivacy.autoLock"

    // Known screen capture / sharing app bundle IDs
    private let knownRecorders: Set<String> = [
        "com.apple.screencapture",
        "com.apple.QuickTimePlayerX",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.elgato.StreamDeck",
        "com.obsproject.obs-studio",
        "net.telestream.screenflow9",
        "com.techsmith.camtasia",
        "com.loom.desktop",
        "com.cleanmymacsoftware.cleverclip",
        "com.apple.systempreferences"   // Screen Sharing in System Prefs
    ]

    private init() {
        autoLockOnRecording = UserDefaults.standard.bool(forKey: autoLockKey)
        startScanning()
    }

    // MARK: - Window Protection

    func applyWindowProtection() {
        for window in NSApp.windows {
            window.sharingType = .none
        }
        isWindowProtected = true
    }

    // MARK: - Recorder Scanning

    func startScanning() {
        scanTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.scanForRecorders() }
    }

    func scanForRecorders() {
        let running = NSWorkspace.shared.runningApplications
        let detected = running
            .filter { app in
                guard let bid = app.bundleIdentifier else { return false }
                return knownRecorders.contains(bid)
            }
            .map { $0.localizedName ?? $0.bundleIdentifier ?? "Unknown" }

        let changed = Set(detected) != Set(detectedRecorders)
        detectedRecorders = detected

        if !detected.isEmpty && changed && autoLockOnRecording {
            AuthenticationManager.shared.logout()
        }
    }

    func stopScanning() {
        scanTimer?.cancel()
        scanTimer = nil
    }
}
#endif
```

**Step 2: Write `ScreenPrivacyView.swift`**

```swift
// Sources/AppLocker/ScreenPrivacy/ScreenPrivacyView.swift
#if os(macOS)
import SwiftUI

struct ScreenPrivacyView: View {
    @ObservedObject var manager = ScreenPrivacyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Privacy")
                .font(.headline)

            // Window protection card
            HStack {
                Image(systemName: manager.isWindowProtected ? "eye.slash.fill" : "eye")
                    .font(.title2)
                    .foregroundColor(manager.isWindowProtected ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isWindowProtected ? "Window Protected" : "Window Unprotected")
                        .fontWeight(.semibold)
                    Text(manager.isWindowProtected
                         ? "AppLocker is invisible in screenshots and screen recordings."
                         : "Apply protection to hide this window from screen capture.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if !manager.isWindowProtected {
                    Button("Apply Protection") {
                        manager.applyWindowProtection()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            // Auto-lock option
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Lock on Recording Detected")
                        .fontWeight(.medium)
                    Text("Immediately locks AppLocker when a screen recorder is detected.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $manager.autoLockOnRecording).toggleStyle(.switch).labelsHidden()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            // Detected recorders
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Detected Screen Capture Processes")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button { manager.scanForRecorders() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
                if manager.detectedRecorders.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        Text("No screen capture apps detected").font(.caption)
                    }
                } else {
                    ForEach(manager.detectedRecorders, id: \.self) { name in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(name).font(.caption).foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            Spacer()
        }
        .padding()
    }
}
#endif
```

**Step 3: Add `applyWindowProtection()` call in `MacAppLockerApp.swift`**

In `applicationDidFinishLaunching`, after `setupMenuBar()`, add:

```swift
ScreenPrivacyManager.shared.applyWindowProtection()
```

Also wire into `MacContentView.swift` sidebar (tab 10):

```swift
SidebarButton(title: "Screen Privacy", icon: "eye.slash.fill", isSelected: selectedTab == 10) { selectedTab = 10 }
```

And switch:
```swift
case 10: ScreenPrivacyView()
```

**Step 4: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 5: Commit**

```bash
git add Sources/AppLocker/ScreenPrivacy/
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: ScreenPrivacy with NSWindow.sharingType protection and recorder detection"
```

---

## Task 8: Network Monitor

**Files:**
- Create: `Sources/AppLocker/NetworkMonitor/NetworkMonitor.swift`
- Create: `Sources/AppLocker/NetworkMonitor/NetworkMonitorView.swift`

**Step 1: Write `NetworkMonitor.swift`**

`lsof -i -n -P` output format (space-separated, variable width):
```
COMMAND   PID USER   FD  TYPE DEVICE SIZE/OFF NODE NAME
Safari   1234 user  27u  IPv4 0xabc     0t0  TCP  10.0.0.5:52000->93.184.1.1:443 (ESTABLISHED)
```
The key field is `NAME`: `localAddr->remoteAddr (STATE)` for TCP, `localAddr->remoteAddr` for UDP.

```swift
// Sources/AppLocker/NetworkMonitor/NetworkMonitor.swift
#if os(macOS)
import Foundation
import SwiftUI

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var connections: [NetworkConnection] = []
    @Published var isPaused: Bool = false
    @Published var showLockedAppsOnly: Bool = true

    private var refreshTask: Task<Void, Never>?
    private var orgCache: [String: String] = [:]    // ip -> org name

    private init() { startRefreshing() }

    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                if !isPaused {
                    let raw = await fetchLsofOutput()
                    let parsed = parseConnections(raw)
                    let filtered = applyFilter(parsed)
                    connections = filtered
                    await annotateOrgs()
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - lsof Subprocess

    private func fetchLsofOutput() async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-i", "-n", "-P"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Parsing

    private func parseConnections(_ output: String) -> [NetworkConnection] {
        var result: [NetworkConnection] = []
        let lines = output.components(separatedBy: "\n").dropFirst() // skip header

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9 else { continue }

            let typeField = parts[4]
            guard typeField == "IPv4" || typeField == "IPv6" else { continue }

            let cmd = parts[0]
            let pid = Int32(parts[1]) ?? 0

            // Find the protocol field (TCP/UDP) and the name that follows it
            guard let protoIdx = parts.firstIndex(where: { $0 == "TCP" || $0 == "UDP" }),
                  protoIdx + 1 < parts.count else { continue }

            let proto = parts[protoIdx]
            let nameField = parts[protoIdx + 1]
            guard nameField.contains("->") else { continue }

            let arrowParts = nameField.components(separatedBy: "->")
            let local = arrowParts[0]
            let remoteRaw = arrowParts[1]

            // remoteRaw may be "93.184.1.1:443" or "93.184.1.1:443" with state following
            var remoteAddr = remoteRaw
            var state = ""
            if protoIdx + 2 < parts.count {
                let stateRaw = parts[protoIdx + 2]
                if stateRaw.hasPrefix("(") && stateRaw.hasSuffix(")") {
                    state = String(stateRaw.dropFirst().dropLast())
                }
            }

            // Split remoteAddr into IP and port (handle IPv6 [::1]:80)
            let remoteIP: String
            let remotePort: String
            if remoteAddr.hasPrefix("[") {
                // IPv6
                let closeBracket = remoteAddr.firstIndex(of: "]") ?? remoteAddr.endIndex
                remoteIP = String(remoteAddr[remoteAddr.index(after: remoteAddr.startIndex)..<closeBracket])
                let afterBracket = remoteAddr[remoteAddr.index(after: closeBracket)...]
                remotePort = afterBracket.hasPrefix(":") ? String(afterBracket.dropFirst()) : ""
            } else {
                let components = remoteAddr.components(separatedBy: ":")
                remoteIP = components.dropLast().joined(separator: ":")
                remotePort = components.last ?? ""
            }

            let conn = NetworkConnection(
                id: UUID(),
                processName: cmd,
                pid: pid,
                remoteIP: remoteIP,
                remotePort: remotePort,
                remoteOrg: orgCache[remoteIP] ?? (isPrivateIP(remoteIP) ? "Local" : ""),
                localAddress: local,
                proto: proto,
                state: state
            )
            result.append(conn)
        }
        return result
    }

    private func applyFilter(_ all: [NetworkConnection]) -> [NetworkConnection] {
        guard showLockedAppsOnly else { return all }
        let lockedNames = Set(AppMonitor.shared.lockedApps.map { $0.displayName.lowercased() })
        let lockedBundleIDs = Set(AppMonitor.shared.lockedApps.map { $0.bundleID.lowercased() })
        return all.filter { conn in
            lockedNames.contains(conn.processName.lowercased()) ||
            lockedBundleIDs.contains { $0.contains(conn.processName.lowercased()) }
        }
    }

    // MARK: - IP Annotation

    private func annotateOrgs() async {
        let unknownIPs = Set(connections.compactMap { conn -> String? in
            guard !conn.remoteIP.isEmpty,
                  orgCache[conn.remoteIP] == nil,
                  !isPrivateIP(conn.remoteIP) else { return nil }
            return conn.remoteIP
        })

        for ip in unknownIPs.prefix(5) {  // limit concurrent lookups
            let org = await whoisOrg(for: ip)
            orgCache[ip] = org ?? "Unknown"
            // Update connections with new org info
            for i in connections.indices where connections[i].remoteIP == ip {
                connections[i].remoteOrg = orgCache[ip] ?? ""
            }
        }
    }

    private func whoisOrg(for ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/whois")
            process.arguments = [ip]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let org = extractOrgFromWhois(output)
                continuation.resume(returning: org)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func extractOrgFromWhois(_ output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("orgname:") || lower.hasPrefix("org-name:") || lower.hasPrefix("netname:") {
                let value = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func isPrivateIP(_ ip: String) -> Bool {
        let privates = ["10.", "192.168.", "127.", "::1", "fe80:"]
        if ip.isEmpty || ip == "*" { return true }
        for prefix in privates where ip.hasPrefix(prefix) { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.components(separatedBy: ".")
            if let second = Int(parts[safe: 1] ?? ""), (16...31).contains(second) { return true }
        }
        return false
    }

    // MARK: - Grouping

    var groupedConnections: [(name: String, connections: [NetworkConnection])] {
        let grouped = Dictionary(grouping: connections, by: { $0.processName })
        return grouped.map { (name: $0.key, connections: $0.value) }
            .sorted { $0.connections.count > $1.connections.count }
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
```

**Step 2: Write `NetworkMonitorView.swift`**

```swift
// Sources/AppLocker/NetworkMonitor/NetworkMonitorView.swift
#if os(macOS)
import SwiftUI

struct NetworkMonitorView: View {
    @ObservedObject var monitor = NetworkMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if monitor.connections.isEmpty {
                emptyState
            } else {
                connectionList
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Network Monitor")
                .font(.headline)
            Text("(\(monitor.connections.count) connections)")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
            Toggle("Locked apps only", isOn: $monitor.showLockedAppsOnly)
                .toggleStyle(.checkbox).font(.caption)
            Toggle(monitor.isPaused ? "Paused" : "Live", isOn: $monitor.isPaused)
                .toggleStyle(.switch).font(.caption)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Image(systemName: "network").font(.system(size: 48)).foregroundColor(.secondary)
            Text(monitor.showLockedAppsOnly
                 ? "No network connections from locked apps"
                 : "No active connections found")
                .foregroundColor(.secondary)
            Text("Toggle 'Locked apps only' to see all connections")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var connectionList: some View {
        List {
            ForEach(monitor.groupedConnections, id: \.name) { group in
                Section {
                    ForEach(group.connections) { conn in
                        ConnectionRow(conn: conn)
                    }
                } header: {
                    HStack {
                        Text(group.name)
                            .font(.subheadline).fontWeight(.semibold)
                        Text("(\(group.connections.count))")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("Terminate") {
                            AppMonitor.shared.addLockedApp(bundleID: "")
                            // Find by process name in running apps
                            if let app = NSWorkspace.shared.runningApplications
                                .first(where: { ($0.localizedName ?? "") == group.name }) {
                                app.forceTerminate()
                                AppMonitor.shared.addLog("Network Monitor: terminated \(group.name)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

struct ConnectionRow: View {
    let conn: NetworkConnection

    var stateColor: Color {
        switch conn.state {
        case "ESTABLISHED": return .green
        case "LISTEN": return .blue
        case "CLOSE_WAIT", "TIME_WAIT", "FIN_WAIT1", "FIN_WAIT2": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("\(conn.remoteIP):\(conn.remotePort)")
                        .font(.system(.caption, design: .monospaced))
                    if !conn.remoteOrg.isEmpty {
                        Text("· \(conn.remoteOrg)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text("\(conn.proto) \(conn.state.isEmpty ? "UDP" : conn.state) · local: \(conn.localAddress)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
#endif
```

**Step 3: Wire into `MacContentView.swift`** (tab 11)

```swift
SidebarButton(title: "Network Monitor", icon: "network", isSelected: selectedTab == 11) { selectedTab = 11 }
```
```swift
case 11: NetworkMonitorView()
```

**Step 4: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 5: Commit**

```bash
git add Sources/AppLocker/NetworkMonitor/
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: NetworkMonitor using lsof, per-app grouping, whois org lookup"
```

---

## Task 9: Secure Notes

**Files:**
- Create: `Sources/AppLocker/SecureNotes/SecureNotesManager.swift`
- Create: `Sources/AppLocker/SecureNotes/SecureNotesView.swift`

**Step 1: Write `SecureNotesManager.swift`**

```swift
// Sources/AppLocker/SecureNotes/SecureNotesManager.swift
#if os(macOS)
import Foundation
import CryptoKit

@MainActor
class SecureNotesManager: ObservableObject {
    static let shared = SecureNotesManager()

    @Published var isUnlocked = false
    @Published var notes: [EncryptedNote] = []
    @Published var lastError: String?

    private var sessionKey: SymmetricKey?
    private let keychainSaltKey = "com.applocker.notesSalt"

    private var notesFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("AppLocker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes_meta.json")
    }

    private init() {}

    // MARK: - Session

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
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func lock() {
        sessionKey = nil
        isUnlocked = false
        notes = []
    }

    // MARK: - Note Operations

    func createNote() -> EncryptedNote? {
        guard let key = sessionKey else { return nil }
        guard let emptyBody = try? CryptoHelper.encrypt(Data("".utf8), using: key) else { return nil }
        let note = EncryptedNote(
            id: UUID(), title: "New Note",
            encryptedBody: emptyBody,
            createdAt: Date(), modifiedAt: Date()
        )
        notes.insert(note, at: 0)
        saveNotes()
        return note
    }

    func deleteNote(_ note: EncryptedNote) {
        notes.removeAll { $0.id == note.id }
        saveNotes()
    }

    func decryptBody(of note: EncryptedNote) -> String {
        guard let key = sessionKey,
              let data = try? CryptoHelper.decrypt(note.encryptedBody, using: key) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func saveBody(_ body: String, for noteID: UUID) {
        guard let key = sessionKey,
              let idx = notes.firstIndex(where: { $0.id == noteID }),
              let encrypted = try? CryptoHelper.encrypt(Data(body.utf8), using: key) else { return }
        notes[idx].encryptedBody = encrypted
        notes[idx].modifiedAt = Date()
        saveNotes()
    }

    func renameNote(_ noteID: UUID, title: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].title = title
        notes[idx].modifiedAt = Date()
        saveNotes()
    }

    // MARK: - Persistence

    private func loadNotes() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: notesFileURL),
              let decoded = try? decoder.decode([EncryptedNote].self, from: data) else {
            notes = []
            return
        }
        notes = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func saveNotes() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(notes) {
            try? data.write(to: notesFileURL)
        }
    }
}
#endif
```

**Step 2: Write `SecureNotesView.swift`**

```swift
// Sources/AppLocker/SecureNotes/SecureNotesView.swift
#if os(macOS)
import SwiftUI

struct SecureNotesView: View {
    @ObservedObject var manager = SecureNotesManager.shared
    @State private var selectedNoteID: UUID?
    @State private var editingBody: String = ""
    @State private var passcode = ""
    @State private var showUnlockSheet = false
    @State private var saveWorkItem: DispatchWorkItem?
    @State private var editingTitle: String = ""
    @State private var isEditingTitle = false

    var selectedNote: EncryptedNote? {
        guard let id = selectedNoteID else { return nil }
        return manager.notes.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if !manager.isUnlocked {
                lockedPlaceholder
            } else {
                editorLayout
            }
        }
        .sheet(isPresented: $showUnlockSheet) { unlockSheet }
        .alert("Notes Error", isPresented: Binding(
            get: { manager.lastError != nil },
            set: { if !$0 { manager.lastError = nil } }
        )) {
            Button("OK") { manager.lastError = nil }
        } message: {
            Text(manager.lastError ?? "")
        }
    }

    // MARK: - Locked state

    private var lockedPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 64)).foregroundColor(.blue)
            Text("Secure Notes")
                .font(.title2).fontWeight(.semibold)
            Text("Notes are encrypted with AES-256-GCM.\nUnlock to read and edit.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("Unlock Notes") { showUnlockSheet = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Editor layout

    private var editorLayout: some View {
        HSplitView {
            // Note list
            VStack(spacing: 0) {
                HStack {
                    Text("Notes (\(manager.notes.count))")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        if let note = manager.createNote() {
                            selectedNoteID = note.id
                            editingBody = ""
                            editingTitle = note.title
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .help("New Note")
                    Button("Lock") { manager.lock(); selectedNoteID = nil }
                        .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal).padding(.top, 8)

                Divider().padding(.top, 6)

                List(manager.notes, selection: $selectedNoteID) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).fontWeight(.medium).lineLimit(1)
                        Text(note.modifiedAt, style: .relative)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete Note", role: .destructive) { manager.deleteNote(note) }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 180, maxWidth: 240)

            // Editor
            VStack(alignment: .leading, spacing: 0) {
                if let note = selectedNote {
                    // Title
                    HStack {
                        if isEditingTitle {
                            TextField("Note title", text: $editingTitle, onCommit: {
                                manager.renameNote(note.id, title: editingTitle)
                                isEditingTitle = false
                            })
                            .textFieldStyle(.plain)
                            .font(.title3.bold())
                            .onExitCommand {
                                manager.renameNote(note.id, title: editingTitle)
                                isEditingTitle = false
                            }
                        } else {
                            Text(note.title)
                                .font(.title3.bold())
                                .onTapGesture(count: 2) {
                                    editingTitle = note.title
                                    isEditingTitle = true
                                }
                        }
                        Spacer()
                        Text("Modified \(note.modifiedAt, style: .relative) ago")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding()

                    Divider()

                    TextEditor(text: $editingBody)
                        .font(.body)
                        .padding(8)
                        .onChange(of: editingBody) { _ in scheduleSave(noteID: note.id) }
                        .onAppear {
                            editingBody = manager.decryptBody(of: note)
                            editingTitle = note.title
                        }
                        .onChange(of: selectedNoteID) { newID in
                            if let id = newID,
                               let n = manager.notes.first(where: { $0.id == id }) {
                                editingBody = manager.decryptBody(of: n)
                                editingTitle = n.title
                                isEditingTitle = false
                            }
                        }
                } else {
                    VStack {
                        Spacer()
                        Text("Select a note or create a new one")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Unlock sheet

    private var unlockSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 48)).foregroundColor(.blue)
            Text("Unlock Notes").font(.title2).fontWeight(.semibold)
            SecureField("Master Passcode", text: $passcode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 240).onSubmit { attemptUnlock() }
            if let error = manager.lastError {
                Text(error).foregroundColor(.red).font(.caption)
            }
            HStack {
                Button("Cancel") { showUnlockSheet = false; passcode = "" }
                    .keyboardShortcut(.cancelAction)
                Button("Unlock") { attemptUnlock() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(passcode.isEmpty)
            }
            if AuthenticationManager.shared.canUseBiometrics() {
                Button {
                    AuthenticationManager.shared.authenticateWithBiometrics { success, _ in
                        if success { showUnlockSheet = false }
                    }
                } label: { Label("Use Biometrics", systemImage: "touchid") }
                .buttonStyle(.borderless)
            }
        }
        .padding(32).frame(width: 320)
    }

    // MARK: - Helpers

    private func attemptUnlock() {
        if manager.unlock(passcode: passcode) {
            passcode = ""
            showUnlockSheet = false
        }
    }

    private func scheduleSave(noteID: UUID) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [noteID] in
            manager.saveBody(editingBody, for: noteID)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
#endif
```

**Step 3: Wire into `MacContentView.swift`** (tab 12)

```swift
SidebarButton(title: "Secure Notes", icon: "lock.rectangle.stack.fill", isSelected: selectedTab == 12) { selectedTab = 12 }
```
```swift
case 12: SecureNotesView()
```

**Step 4: Build**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```

**Step 5: Commit**

```bash
git add Sources/AppLocker/SecureNotes/
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: SecureNotes with AES-GCM per-note encryption, auto-save, sidebar list"
```

---

## Task 10: Wire All Sidebar Tabs + Final `MacContentView.swift` Edit

**Files:**
- Modify: `Sources/AppLocker/MacContentView.swift`

This task consolidates the sidebar wiring from Tasks 3, 5, 6, 7, 8, 9 into a single clean edit to avoid partial-edit conflicts.

**Step 1: Replace the sidebar VStack in `MainInterface` with the full 13-entry version**

Find the `VStack(alignment: .leading, spacing: 4)` block in `MainInterface` (the sidebar) and replace it with:

```swift
VStack(alignment: .leading, spacing: 4) {
    SidebarButton(title: "Locked Apps",      icon: "lock.app.dashed",                  isSelected: selectedTab == 0)  { selectedTab = 0  }
    SidebarButton(title: "Add Apps",         icon: "plus.app",                         isSelected: selectedTab == 1)  { selectedTab = 1  }
    SidebarButton(title: "Stats",            icon: "chart.bar",                        isSelected: selectedTab == 2)  { selectedTab = 2  }
    SidebarButton(title: "Settings",         icon: "gear",                             isSelected: selectedTab == 3)  { selectedTab = 3  }
    SidebarButton(title: "Activity Log",     icon: "list.bullet.rectangle",            isSelected: selectedTab == 4)  { selectedTab = 4  }
    SidebarButton(title: "Intruder Photos",  icon: "person.crop.circle.badge.exclamationmark", isSelected: selectedTab == 5) { selectedTab = 5 }
    SidebarButton(title: "Categories",       icon: "folder.fill",                      isSelected: selectedTab == 6)  { selectedTab = 6  }

    Divider().padding(.vertical, 4)

    Text("Security Tools")
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)

    SidebarButton(title: "Secure Vault",     icon: "lock.doc.fill",                   isSelected: selectedTab == 7)  { selectedTab = 7  }
    SidebarButton(title: "File Locker",      icon: "doc.badge.lock",                  isSelected: selectedTab == 8)  { selectedTab = 8  }
    SidebarButton(title: "Clipboard Guard",  icon: "clipboard.fill",                  isSelected: selectedTab == 9)  { selectedTab = 9  }
    SidebarButton(title: "Screen Privacy",   icon: "eye.slash.fill",                  isSelected: selectedTab == 10) { selectedTab = 10 }
    SidebarButton(title: "Network Monitor",  icon: "network",                         isSelected: selectedTab == 11) { selectedTab = 11 }
    SidebarButton(title: "Secure Notes",     icon: "lock.rectangle.stack.fill",       isSelected: selectedTab == 12) { selectedTab = 12 }

    Spacer()
}
```

**Step 2: Replace the `switch selectedTab` block in `MainInterface` with:**

```swift
switch selectedTab {
case 0:  LockedAppsView(selectedTab: $selectedTab)
case 1:  AddAppsView()
case 2:  StatsView()
case 3:  SettingsView()
case 4:  ActivityLogView()
case 5:  IntruderPhotoView()
case 6:  CategoryManagementView()
case 7:  VaultView()
case 8:  FileLockerView()
case 9:  ClipboardGuardView()
case 10: ScreenPrivacyView()
case 11: NetworkMonitorView()
case 12: SecureNotesView()
default: Text("Select an option")
}
```

**Step 3: Build — must be clean**

```bash
swift build 2>&1 | grep -E '(error:|Build complete)'
```
Expected: `Build complete!`

**Step 4: Final commit**

```bash
git add Sources/AppLocker/MacContentView.swift Sources/AppLocker/MacAppLockerApp.swift
git -c user.email="dev@applocker.local" -c user.name="AppLocker Dev" commit -m "feat: wire all 6 security tool tabs into main navigation with section divider"
```

---

## Task 11: Integration Verification

**Manual verification checklist:**

1. **Secure Vault**: Launch app → tap "Secure Vault" → "Unlock Vault" → enter passcode → vault opens → drag a file in → file appears in grid → right-click → Open → file opens in default app → Export → saves decrypted → Delete → file removed.

2. **File Locker**: Tap "File Locker" → "Lock Files" → enter passcode → select a test file → file disappears, `.aplk` appears → "Unlock .aplk" → enter passcode → select `.aplk` → original restored.

3. **Clipboard Guard**: Tap "Clipboard Guard" → toggle ON → copy text anywhere → countdown appears → wait for delay → paste somewhere → clipboard is empty.

4. **Screen Privacy**: Tap "Screen Privacy" → "Apply Protection" → take a screenshot (Cmd+Shift+4) → AppLocker window appears black in screenshot → if a known recorder is running, it appears in the detected list.

5. **Network Monitor**: Tap "Network Monitor" → connections appear (open a website in Safari) → uncheck "Locked apps only" → more connections visible → org names populate after ~5 seconds.

6. **Secure Notes**: Tap "Secure Notes" → "Unlock Notes" → create note → type body → navigate away → come back → note body is preserved encrypted.

**Build verification:**

```bash
swift build 2>&1 | grep -E '(error:|warning:|Build complete)'
```

---

## Build Order

```
Task 1 (CryptoHelper + Models)
  → Task 2 (VaultManager)
    → Task 3 (VaultView)
      → Task 4 (FileLockerManager)
        → Task 5 (FileLockerView)
          → Task 6 (ClipboardGuard)
            → Task 7 (ScreenPrivacy)
              → Task 8 (NetworkMonitor)
                → Task 9 (SecureNotes)
                  → Task 10 (Sidebar wiring)
                    → Task 11 (Verification)
```

Each task is sequential (later tasks may reference types from earlier ones). Build after each task before proceeding.
