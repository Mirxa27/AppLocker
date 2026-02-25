// Sources/AppLocker/iOS/Protection/AppProtectionManager.swift
#if os(iOS)
import Foundation
import LocalAuthentication
import UIKit
import Security

@MainActor
class AppProtectionManager: ObservableObject {
    static let shared = AppProtectionManager()

    @Published var isAppLocked       = true
    @Published var isJailbroken      = false
    @Published var isScreenRecording = false
    @Published var authError: String?
    @Published var isLockedOut       = false
    @Published var lockoutEndTime:   Date?

    private let pinKey       = "com.applocker.ios.pin"
    private let pinSaltKey   = "com.applocker.ios.pin.salt"
    private let keychainSvc  = "com.applocker.ios"
    private var backgroundedAt: Date?
    private let bgLockDelay: TimeInterval = 60
    private var failedAttempts = 0
    private var lockoutTimer: Timer?
    private let maxAttempts = 5
    private let lockoutDuration: TimeInterval = 300  // 5 min after maxAttempts

    private init() {
        isJailbroken = Self.detectJailbreak()
        startScreenRecordingMonitor()
    }

    // MARK: - Biometric

    func authenticateBiometric() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            authError = err?.localizedDescription ?? "Biometrics unavailable"
            return false
        }
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Open AppLocker"
            )
            if ok { isAppLocked = false; authError = nil }
            return ok
        } catch {
            authError = error.localizedDescription
            return false
        }
    }

    // MARK: - PIN

    func isPINSet() -> Bool { loadPINHash() != nil }

    func setPIN(_ pin: String) -> Bool {
        guard pin.count >= 4 else { authError = "PIN must be at least 4 digits"; return false }
        return savePIN(pin)
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard !isLockedOut else {
            let remaining = Int(max(0, lockoutEndTime?.timeIntervalSinceNow ?? 0))
            authError = "Too many attempts. Try again in \(remaining)s"
            return false
        }
        guard let stored = loadPINHash(), let salt = loadPINSalt() else {
            authError = "No PIN set"; return false
        }
        guard let inputHash = PBKDF2Helper.deriveKey(passcode: pin, salt: salt) else { return false }
        if stored == inputHash {
            failedAttempts = 0; isAppLocked = false; authError = nil; return true
        }
        failedAttempts += 1
        if failedAttempts >= maxAttempts { triggerLockout() }
        else {
            let remaining = maxAttempts - failedAttempts
            authError = remaining <= 2
                ? "Incorrect PIN. \(remaining) attempt\(remaining == 1 ? "" : "s") remaining"
                : "Incorrect PIN"
        }
        return false
    }

    private func triggerLockout() {
        isLockedOut    = true
        lockoutEndTime = Date().addingTimeInterval(lockoutDuration)
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let end = self.lockoutEndTime else { return }
                if end <= Date() {
                    self.isLockedOut = false; self.lockoutEndTime = nil
                    self.failedAttempts = 0; self.lockoutTimer?.invalidate()
                }
            }
        }
        authError = "Too many attempts. Locked for \(Int(lockoutDuration / 60)) minutes."
    }

    // MARK: - Background lock

    func handleBackground() { backgroundedAt = Date() }

    func handleForeground() {
        defer { backgroundedAt = nil }
        guard let ts = backgroundedAt,
              Date().timeIntervalSince(ts) > bgLockDelay else { return }
        isAppLocked = true
    }

    func lock() { isAppLocked = true }

    // MARK: - Screen recording

    private func startScreenRecordingMonitor() {
        isScreenRecording = UIScreen.main.isCaptured
        NotificationCenter.default.addObserver(
            self, selector: #selector(captureChanged),
            name: UIScreen.capturedDidChangeNotification, object: nil
        )
    }

    @objc private func captureChanged() {
        isScreenRecording = UIScreen.main.isCaptured
    }

    // MARK: - Jailbreak detection

    private static func detectJailbreak() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash", "/usr/sbin/sshd",
            "/etc/apt", "/private/var/lib/apt/"
        ]
        for path in suspiciousPaths where FileManager.default.fileExists(atPath: path) { return true }
        let testPath = "/private/jb_\(UUID().uuidString)"
        if (try? "x".write(toFile: testPath, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: testPath)
            return true
        }
        return false
        #endif
    }

    // MARK: - Keychain PIN helpers

    private func savePIN(_ pin: String) -> Bool {
        guard let salt = try? CryptoHelper.randomSalt(),
              let hash = PBKDF2Helper.deriveKey(passcode: pin, salt: salt) else { return false }
        return saveToKeychain(key: pinKey, data: hash)
            && saveToKeychain(key: pinSaltKey, data: salt)
    }

    private func loadPINHash() -> Data? { loadFromKeychain(key: pinKey) }
    private func loadPINSalt()  -> Data? { loadFromKeychain(key: pinSaltKey) }

    private func saveToKeychain(key: String, data: Data) -> Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainSvc,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(q as CFDictionary)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    private func loadFromKeychain(key: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainSvc,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var res: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &res) == errSecSuccess,
              let data = res as? Data else { return nil }
        return data
    }
}
#endif
