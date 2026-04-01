import Foundation
import XCTest
@testable import AppLocker

final class SecureNotesSyncTests: XCTestCase {
    private func makeNote(id: UUID = UUID(), title: String, modifiedAt: Date) -> EncryptedNote {
        EncryptedNote(
            id: id,
            title: title,
            encryptedBody: Data(title.utf8),
            createdAt: modifiedAt.addingTimeInterval(-120),
            modifiedAt: modifiedAt
        )
    }

    func testEnvelopeRoundTripPreservesNotesAndTimestamp() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let envelope = EncryptedNotesEnvelope(
            updatedAt: updatedAt,
            notes: [makeNote(title: "Alpha", modifiedAt: updatedAt)]
        )

        let base64 = try SecureNotesSync.encodeEnvelopeToBase64(envelope)
        let decoded = SecureNotesSync.decodeEnvelope(fromBase64: base64)

        XCTAssertEqual(decoded?.updatedAt, updatedAt)
        XCTAssertEqual(decoded?.notes.count, 1)
        XCTAssertEqual(decoded?.notes.first?.title, "Alpha")
    }

    func testLegacyArrayPayloadStillDecodes() throws {
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let legacyNotes = [makeNote(title: "Legacy", modifiedAt: modifiedAt)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacyNotes)

        let decoded = try SecureNotesSync.decodeEnvelope(from: data)

        XCTAssertEqual(decoded.notes.count, 1)
        XCTAssertEqual(decoded.notes.first?.title, "Legacy")
        XCTAssertEqual(decoded.updatedAt, modifiedAt)
    }

    func testPreferredEnvelopeUsesNewestDataset() {
        let older = EncryptedNotesEnvelope(
            updatedAt: Date(timeIntervalSince1970: 100),
            notes: [makeNote(title: "Old", modifiedAt: Date(timeIntervalSince1970: 90))]
        )
        let newer = EncryptedNotesEnvelope(
            updatedAt: Date(timeIntervalSince1970: 200),
            notes: []
        )

        let resolved = SecureNotesSync.preferredEnvelope(local: older, remote: newer)

        XCTAssertEqual(resolved?.updatedAt, newer.updatedAt)
        XCTAssertTrue(resolved?.notes.isEmpty == true)
    }
}
