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
        let panel = NSSavePanel()
        panel.nameFieldStringValue = vaultFile.originalName
        panel.begin { [weak self] response in
            guard response == .OK, let destURL = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let key = self.sessionKey else {
                    self.lastError = "Vault was locked before export could complete"
                    return
                }
                do {
                    let encURL = self.vaultDirectory.appendingPathComponent(vaultFile.encryptedFilename)
                    let encrypted = try Data(contentsOf: encURL)
                    let decrypted = try CryptoHelper.decrypt(encrypted, using: key)
                    try decrypted.write(to: destURL)
                    self.lastError = nil
                } catch {
                    self.lastError = "Export failed: \(error.localizedDescription)"
                }
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: metaURL),
              let decoded = try? decoder.decode([VaultFile].self, from: data) else {
            files = []
            return
        }
        files = decoded
    }

    func saveMetadata() {
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
