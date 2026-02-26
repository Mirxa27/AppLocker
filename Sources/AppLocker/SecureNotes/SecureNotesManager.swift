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

    func unlock(passcode: String) -> Bool {
        guard AuthenticationManager.shared.verifyPasscode(passcode) else {
            lastError = "Incorrect passcode"; return false
        }
        do {
            let salt = try CryptoHelper.getOrCreateSalt(keychainKey: keychainSaltKey)
            sessionKey = CryptoHelper.deriveKey(passcode: passcode, salt: salt, context: "applocker.notes.v1")
            isUnlocked = true
            lastError = nil
            loadNotes()
            // Sync salt to iCloud KV so iOS companion can derive the same notes key
            NSUbiquitousKeyValueStore.default.set(
                salt.base64EncodedString(),
                forKey: "com.applocker.notesSalt"
            )
            NSUbiquitousKeyValueStore.default.synchronize()
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

    private func loadNotes() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: notesFileURL),
              let decoded = try? decoder.decode([EncryptedNote].self, from: data) else {
            notes = []; return
        }
        notes = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func saveNotes() {
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
}
#endif
