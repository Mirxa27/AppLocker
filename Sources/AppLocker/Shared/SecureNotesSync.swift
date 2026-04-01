import Foundation

enum SecureNotesSync {
    static let notesStoreKey = "com.applocker.encryptedNotes"
    static let notesSaltStoreKey = "com.applocker.notesSalt"

    static func encodeEnvelope(_ envelope: EncryptedNotesEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func encodeEnvelopeToBase64(_ envelope: EncryptedNotesEnvelope) throws -> String {
        try encodeEnvelope(envelope).base64EncodedString()
    }

    static func decodeEnvelope(from data: Data) throws -> EncryptedNotesEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let envelope = try? decoder.decode(EncryptedNotesEnvelope.self, from: data) {
            return envelope
        }

        let legacyNotes = try decoder.decode([EncryptedNote].self, from: data)
        let updatedAt = legacyNotes.map(\.modifiedAt).max() ?? Date.distantPast
        return EncryptedNotesEnvelope(updatedAt: updatedAt, notes: legacyNotes)
    }

    static func decodeEnvelope(fromBase64 base64: String?) -> EncryptedNotesEnvelope? {
        guard let base64,
              let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? decodeEnvelope(from: data)
    }

    static func preferredEnvelope(local: EncryptedNotesEnvelope?, remote: EncryptedNotesEnvelope?) -> EncryptedNotesEnvelope? {
        switch (local, remote) {
        case let (local?, remote?):
            return remote.updatedAt >= local.updatedAt ? remote : local
        case let (local?, nil):
            return local
        case let (nil, remote?):
            return remote
        case (nil, nil):
            return nil
        }
    }

    static func makeEnvelope(notes: [EncryptedNote], updatedAt: Date = Date()) -> EncryptedNotesEnvelope {
        EncryptedNotesEnvelope(updatedAt: updatedAt, notes: notes)
    }
}
