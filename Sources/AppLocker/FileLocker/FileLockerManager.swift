// Sources/AppLocker/FileLocker/FileLockerManager.swift
#if os(macOS)
import Foundation
import AppKit

enum FileLockerError: LocalizedError {
    case invalidFormat(String)
    case wrongPasscode
    case fileNotFound(String)
    case alreadyLocked(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let f): return "Invalid .aplk file: \(f)"
        case .wrongPasscode: return "Incorrect passcode — cannot decrypt"
        case .fileNotFound(let p): return "File not found: \(p)"
        case .alreadyLocked(let f): return "\(f) is already locked"
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
    private let aplkMagic = Data([0x41, 0x50, 0x4C, 0x4B])
    private let aplkVersion: UInt8 = 0x01
    private let headerSize = 37  // 4 magic + 1 version + 32 salt

    private init() { loadRecords() }

    // MARK: - Encrypt

    func lockFiles(passcode: String) {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"; return
        }
        let panel = NSOpenPanel()
        panel.title = "Select Files to Lock"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isProcessing = true
                for url in panel.urls {
                    await self.encryptItem(at: url, passcode: passcode)
                }
                self.isProcessing = false
                self.saveRecords()
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
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil) else { return }
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

            var container = aplkMagic
            container.append(aplkVersion)
            container.append(salt)
            container.append(ciphertext)

            let lockedURL = url.appendingPathExtension("aplk")
            try container.write(to: lockedURL)
            CryptoHelper.secureDelete(url: url)

            lockedFiles.append(LockedFileRecord(
                id: UUID(), originalPath: url.path,
                lockedPath: lockedURL.path, dateEncrypted: Date()
            ))
        } catch {
            lastError = "Failed to lock \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Decrypt

    func unlockFiles(passcode: String) {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"; return
        }
        let panel = NSOpenPanel()
        panel.title = "Select .aplk Files to Unlock"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isProcessing = true
                for url in panel.urls where url.pathExtension == "aplk" {
                    self.decryptFile(at: url, passcode: passcode)
                }
                self.isProcessing = false
                self.saveRecords()
            }
        }
    }

    private func decryptFile(at lockedURL: URL, passcode: String) {
        do {
            let container = try Data(contentsOf: lockedURL)
            guard container.count > headerSize else {
                throw FileLockerError.invalidFormat("too small")
            }
            guard container.prefix(4) == aplkMagic else {
                throw FileLockerError.invalidFormat("bad magic bytes")
            }
            let salt = container[5..<37]
            let ciphertext = container[37...]
            let key = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.filelockr.v1")
            let plaintext: Data
            do {
                plaintext = try CryptoHelper.decrypt(Data(ciphertext), using: key)
            } catch {
                throw FileLockerError.wrongPasscode
            }
            let originalURL = lockedURL.deletingPathExtension()
            try plaintext.write(to: originalURL)
            CryptoHelper.secureDelete(url: lockedURL)
            lockedFiles.removeAll { $0.lockedPath == lockedURL.path }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([LockedFileRecord].self, from: data) else { return }
        lockedFiles = records.filter { FileManager.default.fileExists(atPath: $0.lockedPath) }
    }

    func saveRecords() {
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
