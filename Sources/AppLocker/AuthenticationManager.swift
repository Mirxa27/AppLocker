// AuthenticationManager.swift
// Handles passcode verification, biometrics, and lockout logic

import Foundation
import LocalAuthentication
import Security
import CryptoKit

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var isLockedOut = false
    @Published var lockoutEndTime: Date?
    @Published var failedAttempts = 0
    @Published var authenticationError: String?
    
    private let keychainService    = "com.mirxa.AppLocker"
    private let passcodeKey        = "passcode"
    private let saltKey            = "passcode_salt"
    // Security-sensitive counters live in Keychain, not UserDefaults (tamper-resistant)
    private let failedAttemptsKey  = "failed_attempts"
    private let lockoutEndTimeKey  = "lockout_end_time"
    private let passcodeVersionKey = "passcode_version"
    private let lockoutDurations: [Int: TimeInterval] = [
        5: 30,      // 30 seconds after 5 attempts
        8: 120,     // 2 minutes after 8 attempts
        10: 300,    // 5 minutes after 10 attempts
        15: 900,    // 15 minutes after 15 attempts
        20: 3600    // 1 hour after 20 attempts
    ]
    private let maxFailedAttempts = 5
    private var lockoutTimer: Timer?
    
    private init() {
        loadFailedAttempts()
        checkLockoutStatus()
    }
    
    // MARK: - Passcode Management
    
    func isPasscodeSet() -> Bool {
        return getStoredPasscode() != nil
    }
    
    func setPasscode(_ passcode: String) -> Bool {
        // Generate new random salt
        var salt = Data(count: 32)
        let result = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }

        guard result == errSecSuccess else { return false }
        
        guard let hashedPasscode = hashPasscodeV2(passcode, salt: salt) else { return false }
        
        // Store in Keychain
        if storeInKeychain(key: passcodeKey, data: hashedPasscode) &&
           storeInKeychain(key: saltKey, data: salt) {
            _ = storeInKeychain(key: passcodeVersionKey, data: Data("v2".utf8))
            return true
        }
        return false
    }
    
    func changePasscode(currentPasscode: String, newPasscode: String) -> (success: Bool, error: String?) {
        guard isPasscodeSet() else {
            return (false, "No passcode is currently set")
        }
        
        guard verifyPasscode(currentPasscode) else {
            recordFailedAttempt()
            return (false, "Current passcode is incorrect")
        }
        
        guard newPasscode.count >= 4 else {
            return (false, "New passcode must be at least 4 characters")
        }
        
        guard currentPasscode != newPasscode else {
            return (false, "New passcode must be different from current passcode")
        }
        
        if setPasscode(newPasscode) {
            resetFailedAttempts()
            return (true, nil)
        }
        
        return (false, "Failed to save new passcode")
    }
    
    func resetAllData() -> Bool {
        // Delete passcode and salt from Keychain
        let passcodeDeleted = deleteFromKeychain(key: passcodeKey)
        let saltDeleted = deleteFromKeychain(key: saltKey)
        
        // Reset state
        isAuthenticated = false
        failedAttempts = 0
        isLockedOut = false
        lockoutEndTime = nil
        authenticationError = nil
        saveFailedAttempts()
        
        return passcodeDeleted && saltDeleted
    }
    
    func verifyPasscode(_ passcode: String) -> Bool {
        guard let storedHash = getStoredPasscode(),
              let salt = getSalt() else { return false }

        let version = retrieveFromKeychain(key: passcodeVersionKey).flatMap { String(data: $0, encoding: .utf8) } ?? "v1"
        if version == "v2" {
            guard let derived = hashPasscodeV2(passcode, salt: salt) else { return false }
            return storedHash == derived
        } else {
            return storedHash == hashPasscodeV1(passcode, salt: salt)
        }
    }
    
    private func hashPasscodeV1(_ passcode: String, salt: Data) -> Data {
        let inputData = Data(passcode.utf8) + salt
        let hash = SHA256.hash(data: inputData)
        return Data(hash)
    }

    private func hashPasscodeV2(_ passcode: String, salt: Data) -> Data? {
        return PBKDF2Helper.deriveKey(passcode: passcode, salt: salt)
    }

    /// Call after a successful v1 login to silently upgrade the stored hash.
    private func upgradeToPBKDF2(_ passcode: String) {
        guard let salt = getSalt(),
              let newHash = hashPasscodeV2(passcode, salt: salt) else { return }
        _ = storeInKeychain(key: passcodeKey, data: newHash)
        _ = storeInKeychain(key: passcodeVersionKey, data: Data("v2".utf8))
    }

    // Helper for per-app passcode — uses PBKDF2 (v2) with a dedicated context
    func hashPasscodeForStorage(_ passcode: String) -> String? {
        guard let salt = getSalt(),
              let data = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt) else { return nil }
        return data.base64EncodedString()
    }

    private func getStoredPasscode() -> Data? {
        return retrieveFromKeychain(key: passcodeKey)
    }
    
    private func getSalt() -> Data? {
        return retrieveFromKeychain(key: saltKey)
    }
    
    // MARK: - Failed Attempt Tracking & Lockout
    
    func recordFailedAttempt() {
        failedAttempts += 1
        saveFailedAttempts()
        
        // Capture intruder after 2 failed attempts
        if failedAttempts >= 2 {
            IntruderManager.shared.captureIntruder()
        }

        // Check if we should escalate lockout
        let sortedThresholds = lockoutDurations.keys.sorted()
        var applicableDuration: TimeInterval = 0
        
        for threshold in sortedThresholds {
            if failedAttempts >= threshold {
                applicableDuration = lockoutDurations[threshold] ?? 0
            }
        }
        
        if applicableDuration > 0 {
            startLockout(duration: applicableDuration)
        }
    }
    
    func resetFailedAttempts() {
        failedAttempts = 0
        isLockedOut = false
        lockoutEndTime = nil
        lockoutTimer?.invalidate()
        lockoutTimer = nil
        saveFailedAttempts()
    }
    
    private func startLockout(duration: TimeInterval) {
        isLockedOut = true
        lockoutEndTime = Date().addingTimeInterval(duration)

        storeDoubleInKeychain(key: lockoutEndTimeKey, value: lockoutEndTime!.timeIntervalSince1970)

        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            DispatchQueue.main.async {
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                if let endTime = self.lockoutEndTime, endTime <= Date() {
                    self.isLockedOut = false
                    self.lockoutEndTime = nil
                    timer.invalidate()
                    self.lockoutTimer = nil
                    _ = self.deleteFromKeychain(key: self.lockoutEndTimeKey)
                }
            }
        }
    }

    private func checkLockoutStatus() {
        if let savedEndTime = loadDoubleFromKeychain(key: lockoutEndTimeKey) {
            let endDate = Date(timeIntervalSince1970: savedEndTime)
            if endDate > Date() {
                isLockedOut = true
                lockoutEndTime = endDate

                // Start countdown timer
                lockoutTimer?.invalidate()
                lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                    DispatchQueue.main.async {
                        guard let self = self else {
                            timer.invalidate()
                            return
                        }
                        if let endTime = self.lockoutEndTime, endTime <= Date() {
                            self.isLockedOut = false
                            self.lockoutEndTime = nil
                            timer.invalidate()
                            self.lockoutTimer = nil
                            _ = self.deleteFromKeychain(key: self.lockoutEndTimeKey)
                        }
                    }
                }
            } else {
                isLockedOut = false
                lockoutEndTime = nil
                _ = deleteFromKeychain(key: lockoutEndTimeKey)
            }
        }
    }
    
    var lockoutRemainingSeconds: Int {
        guard let endTime = lockoutEndTime else { return 0 }
        return max(0, Int(endTime.timeIntervalSinceNow))
    }
    
    var lockoutRemainingFormatted: String {
        let seconds = lockoutRemainingSeconds
        if seconds >= 3600 {
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        } else if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func loadFailedAttempts() {
        failedAttempts = Int(loadDoubleFromKeychain(key: failedAttemptsKey) ?? 0)
    }

    private func saveFailedAttempts() {
        storeDoubleInKeychain(key: failedAttemptsKey, value: Double(failedAttempts))
    }

    // MARK: - Keychain Double Helpers (for tamper-resistant counter/timestamp storage)

    private func storeDoubleInKeychain(key: String, value: Double) {
        var v = value
        let data = Data(bytes: &v, count: MemoryLayout<Double>.size)
        _ = storeInKeychain(key: key, data: data)
    }

    private func loadDoubleFromKeychain(key: String) -> Double? {
        guard let data = retrieveFromKeychain(key: key),
              data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Double.self) }
    }
    
    // MARK: - Biometric Authentication
    
    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func authenticateWithBiometrics(completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"
        
        let reason = "Authenticate to unlock app"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                              localizedReason: reason) { success, error in
            Task { @MainActor in
                if success {
                    self.isAuthenticated = true
                    self.resetFailedAttempts()
                    completion(true, nil)
                } else {
                    let message = error?.localizedDescription ?? "Authentication failed"
                    completion(false, message)
                }
            }
        }
    }
    
    // MARK: - Authentication
    
    func authenticate(withPasscode passcode: String, forAppHash appHash: String? = nil) -> Bool {
        if isLockedOut {
            authenticationError = "Too many attempts. Try again in \(lockoutRemainingFormatted)"
            return false
        }
        
        // Check per-app passcode if provided (PBKDF2 v2)
        if let appHash = appHash, let salt = getSalt(),
           let derived = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt) {
            let inputHash = derived.base64EncodedString()
            if inputHash == appHash {
                isAuthenticated = true
                authenticationError = nil
                resetFailedAttempts()
                return true
            }
        }

        // Fallback to master passcode
        if verifyPasscode(passcode) {
            let version = retrieveFromKeychain(key: passcodeVersionKey).flatMap { String(data: $0, encoding: .utf8) } ?? "v1"
            if version != "v2" { upgradeToPBKDF2(passcode) }
            isAuthenticated = true
            authenticationError = nil
            resetFailedAttempts()
            return true
        } else {
            recordFailedAttempt()
            if isLockedOut {
                authenticationError = "Too many attempts. Locked for \(lockoutRemainingFormatted)"
            } else {
                let remaining = maxFailedAttempts - failedAttempts
                if remaining <= 3 && remaining > 0 {
                    authenticationError = "Incorrect passcode. \(remaining) attempts remaining before lockout"
                } else {
                    authenticationError = "Incorrect passcode"
                }
            }
            return false
        }
    }
    
    func logout() {
        isAuthenticated = false
    }
    
    // MARK: - Keychain Helpers
    
    private func storeInKeychain(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func retrieveFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
    
    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
