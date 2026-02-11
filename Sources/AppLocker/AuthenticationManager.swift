// AuthenticationManager.swift
// Manages passcode and biometric authentication with lockout protection

import Foundation
import LocalAuthentication
import Security
import CryptoKit

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var authenticationError: String?
    @Published var failedAttempts: Int = 0
    @Published var isLockedOut = false
    @Published var lockoutEndTime: Date?
    
    private let passcodeKey = "com.applocker.passcode"
    private let saltKey = "com.applocker.salt"
    private let keychainService = "com.applocker.auth"
    
    // Lockout settings
    private let maxFailedAttempts = 5
    private let lockoutDurations: [Int: TimeInterval] = [
        5: 30,      // 5 failures = 30 seconds
        8: 120,     // 8 failures = 2 minutes
        10: 300,    // 10 failures = 5 minutes
        15: 900,    // 15 failures = 15 minutes
        20: 3600    // 20 failures = 1 hour
    ]
    
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
        guard passcode.count >= 4 else { return false }
        
        // Generate salt
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        
        // Hash passcode with salt
        let hashedPasscode = hashPasscode(passcode, salt: salt)
        
        // Store in Keychain
        if storeInKeychain(key: passcodeKey, data: hashedPasscode) &&
           storeInKeychain(key: saltKey, data: salt) {
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
        
        let inputHash = hashPasscode(passcode, salt: salt)
        return storedHash == inputHash
    }
    
    private func hashPasscode(_ passcode: String, salt: Data) -> Data {
        let inputData = Data(passcode.utf8) + salt
        let hash = SHA256.hash(data: inputData)
        return Data(hash)
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
        
        UserDefaults.standard.set(lockoutEndTime!.timeIntervalSince1970, forKey: "com.applocker.lockoutEndTime")
        
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if let endTime = self.lockoutEndTime, endTime <= Date() {
                self.isLockedOut = false
                self.lockoutEndTime = nil
                timer.invalidate()
                self.lockoutTimer = nil
                UserDefaults.standard.removeObject(forKey: "com.applocker.lockoutEndTime")
            }
        }
    }
    
    private func checkLockoutStatus() {
        if let savedEndTime = UserDefaults.standard.object(forKey: "com.applocker.lockoutEndTime") as? TimeInterval {
            let endDate = Date(timeIntervalSince1970: savedEndTime)
            if endDate > Date() {
                isLockedOut = true
                lockoutEndTime = endDate
                
                // Start countdown timer
                lockoutTimer?.invalidate()
                lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    if let endTime = self.lockoutEndTime, endTime <= Date() {
                        self.isLockedOut = false
                        self.lockoutEndTime = nil
                        timer.invalidate()
                        self.lockoutTimer = nil
                        UserDefaults.standard.removeObject(forKey: "com.applocker.lockoutEndTime")
                    }
                }
            } else {
                isLockedOut = false
                lockoutEndTime = nil
                UserDefaults.standard.removeObject(forKey: "com.applocker.lockoutEndTime")
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
        failedAttempts = UserDefaults.standard.integer(forKey: "com.applocker.failedAttempts")
    }
    
    private func saveFailedAttempts() {
        UserDefaults.standard.set(failedAttempts, forKey: "com.applocker.failedAttempts")
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
            DispatchQueue.main.async {
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
    
    func authenticate(withPasscode passcode: String) -> Bool {
        if isLockedOut {
            authenticationError = "Too many attempts. Try again in \(lockoutRemainingFormatted)"
            return false
        }
        
        if verifyPasscode(passcode) {
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
