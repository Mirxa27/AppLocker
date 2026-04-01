import Foundation
import XCTest
@testable import AppLocker

final class CryptoHelperTests: XCTestCase {
    func testEncryptDecryptRoundTrip() throws {
        let salt = Data(repeating: 7, count: 32)
        let key = CryptoHelper.deriveKey(passcode: "correct horse battery staple", salt: salt, context: "tests")
        let plaintext = Data("AppLocker end-to-end encryption".utf8)

        let ciphertext = try CryptoHelper.encrypt(plaintext, using: key)
        let decrypted = try CryptoHelper.decrypt(ciphertext, using: key)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptRejectsTamperedCiphertext() throws {
        let salt = Data(repeating: 3, count: 32)
        let key = CryptoHelper.deriveKey(passcode: "tamper-check", salt: salt, context: "tests")
        let plaintext = Data("Sensitive payload".utf8)
        let ciphertext = try CryptoHelper.encrypt(plaintext, using: key)

        var tampered = ciphertext
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01

        XCTAssertThrowsError(try CryptoHelper.decrypt(tampered, using: key))
    }

    func testPBKDF2DerivationIsDeterministic() {
        let salt = Data("shared-salt-value".utf8)

        let first = PBKDF2Helper.deriveKey(passcode: "app-locker", salt: salt)
        let second = PBKDF2Helper.deriveKey(passcode: "app-locker", salt: salt)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first?.count, PBKDF2Helper.keyLength)
    }

    func testPBKDF2RejectsEmptyInputs() {
        XCTAssertNil(PBKDF2Helper.deriveKey(passcode: "", salt: Data("salt".utf8)))
        XCTAssertNil(PBKDF2Helper.deriveKey(passcode: "passcode", salt: Data()))
    }
}
