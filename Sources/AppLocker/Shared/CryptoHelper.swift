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
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("AppLocker CryptoHelper: failed to save salt '\(key)' to Keychain, status: \(status)")
        }
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
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > 0,
              let fh = try? FileHandle(forWritingTo: url) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        // Truncate to 0 and re-write zeros — simplest correct approach
        do {
            try fh.truncate(atOffset: 0)
            let chunkSize = 65536
            let zeros = Data(repeating: 0, count: min(size, chunkSize))
            var written = 0
            while written < size {
                let remaining = size - written
                let toWrite = remaining < chunkSize ? Data(repeating: 0, count: remaining) : zeros
                try fh.write(contentsOf: toWrite)
                written += toWrite.count
            }
            try fh.synchronize()
            try fh.close()
        } catch {
            try? fh.close()
        }
        try? FileManager.default.removeItem(at: url)
    }
}
