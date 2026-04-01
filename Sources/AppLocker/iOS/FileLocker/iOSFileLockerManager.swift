// Sources/AppLocker/iOS/FileLocker/iOSFileLockerManager.swift
#if os(iOS)
import Foundation
import CryptoKit
import SwiftUI
import LocalAuthentication
import Security

private enum FileLockerVaultError: LocalizedError {
    case invalidPIN
    case biometricsUnavailable
    case biometricVaultUnavailable
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "Incorrect app PIN"
        case .biometricsUnavailable:
            return "Biometrics not available on this device"
        case .biometricVaultUnavailable:
            return "Unlock File Locker with your PIN once before using biometrics"
        case .keychainFailure(let status):
            return "Secure storage error (\(status))"
        }
    }
}

@MainActor
class iOSFileLockerManager: ObservableObject {
    static let shared = iOSFileLockerManager()

    @Published var isUnlocked = false
    @Published var lockedFiles: [LockedFileEntry] = []
    @Published var lastError: String?
    @Published var isLoading = false

    private var sessionKey: SymmetricKey?
    private let saltKeychainKey = "com.applocker.ios.fileLockerSalt"
    private let metadataKey = "com.applocker.ios.fileLocker.meta"
    private let keychainService = "com.applocker.ios.fileLocker"
    private let masterKeyEnvelopeAccount = "masterKeyEnvelope"
    private let biometricMasterKeyAccount = "biometricMasterKey"
    private let legacyKeyContext = "applocker.ios.filelocker.v1"
    private let userDefaults = UserDefaults.standard
    private var tempDecryptedURLs: [URL] = []

    var vaultDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("AppLockerVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        loadMetadata()
    }

    // MARK: - Session Management

    func unlock(passcode: String) -> Bool {
        isLoading = true
        defer { isLoading = false }

        guard AppProtectionManager.shared.matchesPIN(passcode) else {
            lastError = FileLockerVaultError.invalidPIN.localizedDescription
            return false
        }

        do {
            sessionKey = try resolveSessionKey(passcode: passcode)
            isUnlocked = true
            lastError = nil
            loadMetadata()
            return true
        } catch {
            lastError = "Failed to unlock: \(error.localizedDescription)"
            return false
        }
    }

    func unlockWithBiometric() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            lastError = error?.localizedDescription ?? FileLockerVaultError.biometricsUnavailable.localizedDescription
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock File Locker"
            )
            if success {
                sessionKey = SymmetricKey(data: try loadBiometricVaultKey(using: context))
                isUnlocked = true
                lastError = nil
                loadMetadata()
                return true
            }
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    func lock() {
        for url in tempDecryptedURLs {
            CryptoHelper.secureDelete(url: url)
        }
        tempDecryptedURLs = []
        sessionKey = nil
        isUnlocked = false
        lockedFiles = []
    }

    // MARK: - File Operations

    func addFile(from sourceURL: URL) -> Bool {
        guard let key = sessionKey else {
            lastError = "File Locker is locked"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: sourceURL)
            let encrypted = try CryptoHelper.encrypt(data, using: key)
            let encFilename = UUID().uuidString
            let destURL = vaultDirectory.appendingPathComponent(encFilename)
            try encrypted.write(to: destURL)

            let entry = LockedFileEntry(
                id: UUID(),
                originalName: sourceURL.lastPathComponent,
                encryptedFilename: encFilename,
                fileSize: data.count,
                dateAdded: Date(),
                fileExtension: sourceURL.pathExtension.lowercased(),
                mimeType: mimeTypeForExtension(sourceURL.pathExtension)
            )
            lockedFiles.append(entry)
            saveMetadata()
            lastError = nil
            return true
        } catch {
            lastError = "Failed to add file: \(error.localizedDescription)"
            return false
        }
    }

    func addFileFromData(_ data: Data, name: String, fileExtension ext: String) -> Bool {
        guard let key = sessionKey else {
            lastError = "File Locker is locked"
            return false
        }

        do {
            let encrypted = try CryptoHelper.encrypt(data, using: key)
            let encFilename = UUID().uuidString
            let destURL = vaultDirectory.appendingPathComponent(encFilename)
            try encrypted.write(to: destURL)

            let entry = LockedFileEntry(
                id: UUID(),
                originalName: name,
                encryptedFilename: encFilename,
                fileSize: data.count,
                dateAdded: Date(),
                fileExtension: ext.lowercased(),
                mimeType: mimeTypeForExtension(ext)
            )
            lockedFiles.append(entry)
            saveMetadata()
            lastError = nil
            return true
        } catch {
            lastError = "Failed to add file: \(error.localizedDescription)"
            return false
        }
    }

    func decryptFile(_ entry: LockedFileEntry) -> Data? {
        guard let key = sessionKey else {
            lastError = "File Locker is locked"
            return nil
        }

        do {
            let encURL = vaultDirectory.appendingPathComponent(entry.encryptedFilename)
            let encrypted = try Data(contentsOf: encURL)
            return try CryptoHelper.decrypt(encrypted, using: key)
        } catch {
            lastError = "Decryption failed: \(error.localizedDescription)"
            return nil
        }
    }

    func decryptToTempURL(_ entry: LockedFileEntry) -> URL? {
        guard let decrypted = decryptFile(entry) else { return nil }

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("AppLockerFileLocker", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent(entry.originalName)
            try decrypted.write(to: tempURL)
            tempDecryptedURLs.append(tempURL)
            return tempURL
        } catch {
            lastError = "Failed to create temp file: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteFile(_ entry: LockedFileEntry) {
        let encURL = vaultDirectory.appendingPathComponent(entry.encryptedFilename)
        CryptoHelper.secureDelete(url: encURL)
        lockedFiles.removeAll { $0.id == entry.id }
        saveMetadata()
    }

    func renameFile(_ entry: LockedFileEntry, newName: String) {
        guard let index = lockedFiles.firstIndex(where: { $0.id == entry.id }) else { return }
        lockedFiles[index].originalName = newName
        saveMetadata()
    }

    // MARK: - Export

    func exportFile(_ entry: LockedFileEntry, to destinationURL: URL) -> Bool {
        guard let decrypted = decryptFile(entry) else { return false }
        do {
            try decrypted.write(to: destinationURL)
            lastError = nil
            return true
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Helpers

    func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "play.rectangle.fill"
        default: return "doc.fill"
        }
    }

    func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "txt": return "text/plain"
        case "html": return "text/html"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Statistics

    var totalFiles: Int { lockedFiles.count }

    var totalSize: Int64 {
        Int64(lockedFiles.reduce(0) { $0 + $1.fileSize })
    }

    var formattedTotalSize: String {
        formattedSize(Int(totalSize))
    }

    // MARK: - Persistence

    private func saveMetadata() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(lockedFiles) {
            userDefaults.set(data, forKey: metadataKey)
        }
    }

    private func loadMetadata() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = userDefaults.data(forKey: metadataKey),
              let decoded = try? decoder.decode([LockedFileEntry].self, from: data) else {
            return
        }
        lockedFiles = decoded
    }

    func resetAllData() {
        let entriesToDelete = lockedFiles
        lock()
        for entry in entriesToDelete {
            let encURL = vaultDirectory.appendingPathComponent(entry.encryptedFilename)
            try? FileManager.default.removeItem(at: encURL)
        }
        lockedFiles.removeAll()
        userDefaults.removeObject(forKey: metadataKey)
        deleteKeychainItem(account: masterKeyEnvelopeAccount)
        deleteKeychainItem(account: biometricMasterKeyAccount)
    }

    func rewrapVaultKey(currentPIN: String, newPIN: String) -> Bool {
        do {
            let salt = try CryptoHelper.getOrCreateSalt(keychainKey: saltKeychainKey)
            let newWrappingKey = try wrappingKey(passcode: newPIN, salt: salt)

            if let existingEnvelope = loadKeychainData(account: masterKeyEnvelopeAccount) {
                let currentWrappingKey = try wrappingKey(passcode: currentPIN, salt: salt)
                let masterKeyData = try CryptoHelper.decrypt(existingEnvelope, using: currentWrappingKey)
                try saveVaultEnvelope(masterKeyData, using: newWrappingKey)
                persistBiometricVaultKey(masterKeyData)
                if isUnlocked {
                    sessionKey = SymmetricKey(data: masterKeyData)
                }
                lastError = nil
                return true
            }

            guard hasPersistedVaultContent() else {
                lastError = nil
                return true
            }

            let legacyKey = CryptoHelper.deriveKey(passcode: currentPIN, salt: salt, context: legacyKeyContext)
            let masterKeyData = try migrateLegacyVault(from: legacyKey, using: newWrappingKey)
            persistBiometricVaultKey(masterKeyData)
            if isUnlocked {
                sessionKey = SymmetricKey(data: masterKeyData)
            }
            lastError = nil
            return true
        } catch {
            lastError = "Failed to update File Locker credentials: \(error.localizedDescription)"
            return false
        }
    }

    private func resolveSessionKey(passcode: String) throws -> SymmetricKey {
        let salt = try CryptoHelper.getOrCreateSalt(keychainKey: saltKeychainKey)
        let pinWrappingKey = try wrappingKey(passcode: passcode, salt: salt)

        if let existingEnvelope = loadKeychainData(account: masterKeyEnvelopeAccount) {
            let masterKeyData = try CryptoHelper.decrypt(existingEnvelope, using: pinWrappingKey)
            persistBiometricVaultKey(masterKeyData)
            return SymmetricKey(data: masterKeyData)
        }

        let masterKeyData: Data
        if hasPersistedVaultContent() {
            let legacyKey = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: legacyKeyContext)
            masterKeyData = try migrateLegacyVault(from: legacyKey, using: pinWrappingKey)
        } else {
            masterKeyData = try randomKeyData()
            try saveVaultEnvelope(masterKeyData, using: pinWrappingKey)
        }

        persistBiometricVaultKey(masterKeyData)
        return SymmetricKey(data: masterKeyData)
    }

    private func wrappingKey(passcode: String, salt: Data) throws -> SymmetricKey {
        guard let keyData = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt) else {
            throw CryptoError.keyDerivationFailed
        }
        return SymmetricKey(data: keyData)
    }

    private func hasPersistedVaultContent() -> Bool {
        if !lockedFiles.isEmpty {
            return true
        }

        let urls = (try? encryptedFileURLs()) ?? []
        return !urls.isEmpty
    }

    private func encryptedFileURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: vaultDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            !["migrating", "backup"].contains(url.pathExtension)
        }
    }

    private func randomKeyData() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw CryptoError.saltGenerationFailed }
        return Data(bytes)
    }

    private func migrateLegacyVault(from legacyKey: SymmetricKey, using newWrappingKey: SymmetricKey) throws -> Data {
        let masterKeyData = try randomKeyData()
        let newVaultKey = SymmetricKey(data: masterKeyData)
        let stagedFiles = try stageVaultMigration(from: legacyKey, to: newVaultKey)

        do {
            try saveVaultEnvelope(masterKeyData, using: newWrappingKey)
            try commitVaultMigration(stagedFiles)
            return masterKeyData
        } catch {
            rollbackVaultMigration(stagedFiles)
            deleteKeychainItem(account: masterKeyEnvelopeAccount)
            throw error
        }
    }

    private func stageVaultMigration(from oldKey: SymmetricKey, to newKey: SymmetricKey) throws -> [StagedVaultFile] {
        var stagedFiles: [StagedVaultFile] = []
        for originalURL in try encryptedFileURLs() {
            let encryptedData = try Data(contentsOf: originalURL)
            let decryptedData = try CryptoHelper.decrypt(encryptedData, using: oldKey)
            let reencryptedData = try CryptoHelper.encrypt(decryptedData, using: newKey)
            let stagedURL = originalURL.appendingPathExtension("migrating")
            let backupURL = originalURL.appendingPathExtension("backup")
            try? FileManager.default.removeItem(at: stagedURL)
            try? FileManager.default.removeItem(at: backupURL)
            try reencryptedData.write(to: stagedURL, options: .atomic)
            stagedFiles.append(StagedVaultFile(originalURL: originalURL, stagedURL: stagedURL, backupURL: backupURL))
        }
        return stagedFiles
    }

    private func commitVaultMigration(_ stagedFiles: [StagedVaultFile]) throws {
        var committedFiles: [StagedVaultFile] = []
        do {
            for file in stagedFiles {
                try FileManager.default.moveItem(at: file.originalURL, to: file.backupURL)
                do {
                    try FileManager.default.moveItem(at: file.stagedURL, to: file.originalURL)
                    committedFiles.append(file)
                } catch {
                    try? FileManager.default.moveItem(at: file.backupURL, to: file.originalURL)
                    throw error
                }
            }
            for file in committedFiles {
                try? FileManager.default.removeItem(at: file.backupURL)
            }
        } catch {
            for file in committedFiles.reversed() {
                try? FileManager.default.removeItem(at: file.originalURL)
                try? FileManager.default.moveItem(at: file.backupURL, to: file.originalURL)
            }
            for file in stagedFiles {
                try? FileManager.default.removeItem(at: file.stagedURL)
                try? FileManager.default.removeItem(at: file.backupURL)
            }
            throw error
        }
    }

    private func rollbackVaultMigration(_ stagedFiles: [StagedVaultFile]) {
        for file in stagedFiles {
            try? FileManager.default.removeItem(at: file.stagedURL)
            if FileManager.default.fileExists(atPath: file.backupURL.path) {
                try? FileManager.default.removeItem(at: file.originalURL)
                try? FileManager.default.moveItem(at: file.backupURL, to: file.originalURL)
            }
        }
    }

    private func saveVaultEnvelope(_ masterKeyData: Data, using wrappingKey: SymmetricKey) throws {
        let sealedEnvelope = try CryptoHelper.encrypt(masterKeyData, using: wrappingKey)
        guard saveKeychainData(sealedEnvelope, account: masterKeyEnvelopeAccount) else {
            throw FileLockerVaultError.keychainFailure(errSecInternalError)
        }
    }

    private func persistBiometricVaultKey(_ masterKeyData: Data) {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            deleteKeychainItem(account: biometricMasterKeyAccount)
            return
        }

        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else {
            return
        }

        let deleteQuery = keychainQuery(account: biometricMasterKeyAccount)
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery = keychainQuery(account: biometricMasterKeyAccount)
        addQuery[kSecValueData as String] = masterKeyData
        addQuery[kSecAttrAccessControl as String] = accessControl
        addQuery.removeValue(forKey: kSecAttrAccessible as String)
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadBiometricVaultKey(using context: LAContext) throws -> Data {
        var query = keychainQuery(account: biometricMasterKeyAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw FileLockerVaultError.biometricVaultUnavailable
            }
            throw FileLockerVaultError.keychainFailure(status)
        }

        guard let data = result as? Data else {
            throw FileLockerVaultError.biometricVaultUnavailable
        }

        return data
    }

    private func saveKeychainData(_ data: Data, account: String) -> Bool {
        var query = keychainQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemDelete(keychainQuery(account: account) as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func loadKeychainData(account: String) -> Data? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteKeychainItem(account: String) {
        SecItemDelete(keychainQuery(account: account) as CFDictionary)
    }

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
    }

    private struct StagedVaultFile {
        let originalURL: URL
        let stagedURL: URL
        let backupURL: URL
    }
}

// MARK: - Models

struct LockedFileEntry: Codable, Identifiable {
    let id: UUID
    var originalName: String
    let encryptedFilename: String
    let fileSize: Int
    let dateAdded: Date
    let fileExtension: String
    let mimeType: String
}
#endif
