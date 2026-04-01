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
    private let kvStore = NSUbiquitousKeyValueStore.default
    private var kvObserver: NSObjectProtocol?

    private var notesFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("AppLocker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes_meta.json")
    }

    private init() {
        kvObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFromRemoteStore()
            }
        }
        kvStore.synchronize()
    }

    deinit {
        if let kvObserver {
            NotificationCenter.default.removeObserver(kvObserver)
        }
    }

    func unlock(passcode: String) -> Bool {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"; return false
        }
        do {
            let salt = try CryptoHelper.getOrCreateSalt(keychainKey: keychainSaltKey)
            sessionKey = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.notes.v1")
            isUnlocked = true
            lastError = nil
            kvStore.set(salt.base64EncodedString(), forKey: SecureNotesSync.notesSaltStoreKey)
            kvStore.synchronize()
            loadResolvedNotes()
            return true
        } catch {
            lastError = error.localizedDescription; return false
        }
    }

    func lock() {
        sessionKey = nil; isUnlocked = false; notes = []
    }

    func createNote() -> EncryptedNote? {
        guard let key = sessionKey,
              let emptyBody = try? CryptoHelper.encrypt(Data("".utf8), using: key) else { return nil }
        let note = EncryptedNote(id: UUID(), title: "New Note", encryptedBody: emptyBody,
                                  createdAt: Date(), modifiedAt: Date())
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

    private func loadResolvedNotes() {
        let localEnvelope = loadLocalEnvelope()
        let remoteEnvelope = SecureNotesSync.decodeEnvelope(fromBase64: kvStore.string(forKey: SecureNotesSync.notesStoreKey))
        guard let resolved = SecureNotesSync.preferredEnvelope(local: localEnvelope, remote: remoteEnvelope) else {
            notes = []
            return
        }

        notes = resolved.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        persistEnvelope(resolved, syncRemote: remoteEnvelope?.updatedAt != resolved.updatedAt)
    }

    func saveNotes() {
        let envelope = SecureNotesSync.makeEnvelope(notes: notes)
        persistEnvelope(envelope)
    }

    private func refreshFromRemoteStore() {
        guard let remoteEnvelope = SecureNotesSync.decodeEnvelope(fromBase64: kvStore.string(forKey: SecureNotesSync.notesStoreKey)) else {
            return
        }

        let localEnvelope = loadLocalEnvelope()
        guard let resolved = SecureNotesSync.preferredEnvelope(local: localEnvelope, remote: remoteEnvelope) else {
            return
        }

        persistEnvelope(resolved, syncRemote: false)
        if isUnlocked {
            notes = resolved.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    private func loadLocalEnvelope() -> EncryptedNotesEnvelope? {
        guard let data = try? Data(contentsOf: notesFileURL) else {
            return nil
        }
        return try? SecureNotesSync.decodeEnvelope(from: data)
    }

    private func persistEnvelope(_ envelope: EncryptedNotesEnvelope, syncRemote: Bool = true) {
        do {
            let data = try SecureNotesSync.encodeEnvelope(envelope)
            try data.write(to: notesFileURL, options: .atomic)
            if syncRemote {
                kvStore.set(data.base64EncodedString(), forKey: SecureNotesSync.notesStoreKey)
                kvStore.synchronize()
            }
        } catch {
            lastError = "Failed to save notes: \(error.localizedDescription)"
            AppLogger.cloud.error("Failed to persist secure notes envelope: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
