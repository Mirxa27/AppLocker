// Sources/AppLocker/Shared/PBKDF2Helper.swift
import Foundation
import CommonCrypto

enum PBKDF2Helper {
    static let iterations: UInt32 = 200_000
    static let keyLength  = 32

    /// Derives a 32-byte key from passcode + salt using PBKDF2-HMAC-SHA256.
    /// Returns nil only if the passcode cannot be UTF-8 encoded (should never happen).
    static func deriveKey(passcode: String, salt: Data) -> Data? {
        guard let passwordData = passcode.data(using: .utf8) else { return nil }
        var derivedKey = Data(repeating: 0, count: keyLength)
        let rc: Int32 = derivedKey.withUnsafeMutableBytes { dkBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { pwBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        dkBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        return rc == kCCSuccess ? derivedKey : nil
    }
}
