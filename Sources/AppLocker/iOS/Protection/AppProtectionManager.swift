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

    private let pinKey       = "com.applocker.ios.pin"
    private let keychainSvc  = "com.applocker.ios"
    private var backgroundedAt: Date?
    private let bgLockDelay: TimeInterval = 60

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

    func isPINSet() -> Bool { loadPIN() != nil }

    func setPIN(_ pin: String) -> Bool {
        guard pin.count >= 4 else { authError = "PIN must be at least 4 digits"; return false }
        return savePIN(pin)
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = loadPIN() else { authError = "No PIN set"; return false }
        if stored == pin { isAppLocked = false; authError = nil; return true }
        authError = "Incorrect PIN"
        return false
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
        let data = Data(pin.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainSvc,
            kSecAttrAccount as String: pinKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(q as CFDictionary)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    private func loadPIN() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainSvc,
            kSecAttrAccount as String: pinKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var res: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &res) == errSecSuccess,
              let data = res as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#endif
