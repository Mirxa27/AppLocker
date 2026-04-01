// Sources/AppLocker/iOS/AppLocking/iOSAppLockManager.swift
#if os(iOS)
import Foundation
import SwiftUI
import LocalAuthentication
import Security
import CryptoKit
import UIKit
import Combine
import FamilyControls
import ManagedSettings

@MainActor
final class iOSAppLockManager: ObservableObject {
    static let shared = iOSAppLockManager()

    @Published var lockedApps: [LockedAppEntry] = []
    @Published var isMonitoring = false
    @Published var isAuthorized = false
    @Published var isLoading = false
    @Published var authorizationError: String?
    @Published var sessionUnlockedApps: Set<String> = []
    @Published var lastError: String?
    @Published var showUnlockPrompt = false
    @Published var pendingUnlockBundleID: String?

    private let store = ManagedSettingsStore(named: .init("AppLockerLocking"))
    private let lockedAppsKey = "com.applocker.ios.lockedApps"
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var unlockTimers: [String: Timer] = [:]

    @Published var unlockDuration: TimeInterval = 300 {
        didSet { userDefaults.set(unlockDuration, forKey: "com.applocker.ios.unlockDuration") }
    }

    @Published var autoLockOnBackground: Bool = true {
        didSet { userDefaults.set(autoLockOnBackground, forKey: "com.applocker.ios.autoLockOnBg") }
    }

    @Published var useBiometricForUnlock: Bool = true {
        didSet { userDefaults.set(useBiometricForUnlock, forKey: "com.applocker.ios.biometricUnlock") }
    }

    private init() {
        loadLockedApps()
        loadSettings()
        setupNotificationObservers()
        checkAuthorizationStatus()
        reconcileShieldState()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        isLoading = true
        authorizationError = nil
        defer { isLoading = false }

        #if targetEnvironment(simulator)
        isAuthorized = false
        authorizationError = "Screen Time is not available on the simulator. Test on a physical device."
        clearShields()
        return
        #else
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            authorizationError = nil
            reconcileShieldState()
        } catch {
            isAuthorized = false
            authorizationError = "Screen Time authorization failed: \(error.localizedDescription). Ensure Family Controls is enabled for com.mirxa.AppLocker.Companion."
            clearShields()
        }
        #endif
    }

    func checkAuthorizationStatus() {
        #if targetEnvironment(simulator)
        isAuthorized = false
        authorizationError = "Screen Time is not available on the simulator."
        isMonitoring = false
        return
        #else
        let status = AuthorizationCenter.shared.authorizationStatus

        if #available(iOS 26.4, *) {
            switch status {
            case .approved, .approvedWithDataAccess:
                isAuthorized = true
                authorizationError = nil
            case .denied:
                isAuthorized = false
                authorizationError = "Screen Time access denied. Enable it in Settings > Screen Time."
            case .notDetermined:
                isAuthorized = false
                authorizationError = nil
            @unknown default:
                isAuthorized = false
                authorizationError = "Screen Time authorization status is unavailable."
            }
        } else {
            switch status {
            case .approved:
                isAuthorized = true
                authorizationError = nil
            case .denied:
                isAuthorized = false
                authorizationError = "Screen Time access denied. Enable it in Settings > Screen Time."
            case .notDetermined:
                isAuthorized = false
                authorizationError = nil
            @unknown default:
                isAuthorized = false
                authorizationError = "Screen Time authorization status is unavailable."
            }
        }
        #endif
    }

    // MARK: - App Management

    @discardableResult
    func addLockedApplications(from selection: FamilyActivitySelection, perAppPasscode: String? = nil) -> Int {
        guard isAuthorized else {
            lastError = "Screen Time authorization required before locking apps."
            return 0
        }

        let passcodeMaterial = makePasscodeMaterial(from: perAppPasscode)
        var additions: [LockedAppEntry] = []
        var duplicates: [String] = []
        var skipped: [String] = []

        let metadataByTokenKey: [String: ManagedSettings.Application] = Dictionary(
            uniqueKeysWithValues: selection.applications.compactMap { application in
                guard let token = application.token,
                      let tokenData = encodeApplicationToken(token) else {
                    return nil
                }
                return (tokenFingerprint(for: tokenData), application)
            }
        )

        let tokens = selection.applicationTokens.sorted { lhs, rhs in
            let left = metadataByTokenKey[tokenFingerprint(for: lhs)]?.localizedDisplayName
                ?? metadataByTokenKey[tokenFingerprint(for: lhs)]?.bundleIdentifier
                ?? tokenIdentifier(for: lhs)
            let right = metadataByTokenKey[tokenFingerprint(for: rhs)]?.localizedDisplayName
                ?? metadataByTokenKey[tokenFingerprint(for: rhs)]?.bundleIdentifier
                ?? tokenIdentifier(for: rhs)
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }

        for token in tokens {
            guard let tokenData = encodeApplicationToken(token) else {
                skipped.append("Selected App")
                continue
            }

            let metadata = metadataByTokenKey[tokenFingerprint(for: tokenData)]
            let bundleID = metadata?.bundleIdentifier ?? tokenIdentifier(for: tokenData)
            let displayName = metadata?.localizedDisplayName ?? metadata?.bundleIdentifier ?? "Protected App"

            if lockedApps.contains(where: { $0.bundleID == bundleID }) || additions.contains(where: { $0.bundleID == bundleID }) {
                duplicates.append(displayName)
                continue
            }

            additions.append(
                LockedAppEntry(
                    bundleID: bundleID,
                    displayName: displayName,
                    dateAdded: Date(),
                    perAppPasscodeHash: passcodeMaterial?.hashBase64,
                    lockOnLaunch: true,
                    requireBiometric: true,
                    tokenData: tokenData
                )
            )

            if let passcodeMaterial {
                saveToKeychain(key: "lock-passcode-\(bundleID)", data: passcodeMaterial.hash)
                saveToKeychain(key: "lock-salt-\(bundleID)", data: passcodeMaterial.salt)
            }
        }

        if additions.isEmpty {
            if !duplicates.isEmpty {
                lastError = duplicates.count == 1
                    ? "\(duplicates[0]) is already locked."
                    : "Selected apps are already locked."
            } else if !skipped.isEmpty {
                lastError = "One or more selected apps could not be resolved by Screen Time."
            }
            return 0
        }

        lockedApps.append(contentsOf: additions)
        lockedApps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        saveLockedApps()
        reconcileShieldState()

        if !skipped.isEmpty {
            lastError = "Locked \(additions.count) apps. \(skipped.count) app selections were skipped because iOS did not expose a bundle identifier."
        } else if !duplicates.isEmpty {
            lastError = "Locked \(additions.count) apps. Existing entries were left unchanged."
        } else {
            lastError = nil
        }

        return additions.count
    }

    func removeLockedApp(bundleID: String) {
        lockedApps.removeAll { $0.bundleID == bundleID }
        sessionUnlockedApps.remove(bundleID)
        unlockTimers[bundleID]?.invalidate()
        unlockTimers.removeValue(forKey: bundleID)
        deleteFromKeychain(key: "lock-passcode-\(bundleID)")
        deleteFromKeychain(key: "lock-salt-\(bundleID)")
        saveLockedApps()
        reconcileShieldState()
    }

    func updateLockSettings(bundleID: String, lockOnLaunch: Bool? = nil, requireBiometric: Bool? = nil) {
        guard let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        if let lockOnLaunch { lockedApps[index].lockOnLaunch = lockOnLaunch }
        if let requireBiometric { lockedApps[index].requireBiometric = requireBiometric }
        saveLockedApps()
        reconcileShieldState()
    }

    func updatePerAppPasscode(bundleID: String, newPasscode: String?) {
        guard let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) else { return }

        if let passcodeMaterial = makePasscodeMaterial(from: newPasscode) {
            saveToKeychain(key: "lock-passcode-\(bundleID)", data: passcodeMaterial.hash)
            saveToKeychain(key: "lock-salt-\(bundleID)", data: passcodeMaterial.salt)
            lockedApps[index].perAppPasscodeHash = passcodeMaterial.hashBase64
        } else {
            deleteFromKeychain(key: "lock-passcode-\(bundleID)")
            deleteFromKeychain(key: "lock-salt-\(bundleID)")
            lockedApps[index].perAppPasscodeHash = nil
        }

        saveLockedApps()
    }

    // MARK: - Session Management

    func unlockApp(bundleID: String, for duration: TimeInterval? = nil) {
        let duration = duration ?? unlockDuration
        sessionUnlockedApps.insert(bundleID)

        unlockTimers[bundleID]?.invalidate()
        unlockTimers[bundleID] = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lockApp(bundleID: bundleID)
            }
        }

        showUnlockPrompt = false
        pendingUnlockBundleID = nil
        lastError = nil
        reconcileShieldState()
    }

    func lockApp(bundleID: String) {
        sessionUnlockedApps.remove(bundleID)
        unlockTimers[bundleID]?.invalidate()
        unlockTimers.removeValue(forKey: bundleID)
        reconcileShieldState()
    }

    func lockAllApps() {
        sessionUnlockedApps.removeAll()
        unlockTimers.values.forEach { $0.invalidate() }
        unlockTimers.removeAll()
        reconcileShieldState()
    }

    func isAppLocked(bundleID: String) -> Bool {
        guard lockedApps.contains(where: { $0.bundleID == bundleID }) else { return false }
        return !sessionUnlockedApps.contains(bundleID)
    }

    // MARK: - Authentication

    func authenticateToUnlock(bundleID: String) async -> Bool {
        guard let entry = lockedApps.first(where: { $0.bundleID == bundleID }) else { return false }

        if entry.requireBiometric && useBiometricForUnlock {
            let success = await authenticateBiometric(reason: "Unlock \(entry.displayName)")
            if success {
                unlockApp(bundleID: bundleID)
                return true
            }
        }

        pendingUnlockBundleID = bundleID
        showUnlockPrompt = true
        return false
    }

    func verifyPasscode(_ passcode: String, for bundleID: String) -> Bool {
        let isValid: Bool

        if let salt = loadFromKeychain(key: "lock-salt-\(bundleID)"),
           let storedHash = loadFromKeychain(key: "lock-passcode-\(bundleID)"),
           let inputHash = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt) {
            isValid = storedHash == inputHash
        } else {
            isValid = AppProtectionManager.shared.verifyPIN(passcode)
        }

        guard isValid else { return false }
        unlockApp(bundleID: bundleID)
        return true
    }

    func cancelUnlockPrompt() {
        pendingUnlockBundleID = nil
        showUnlockPrompt = false
    }

    var pendingUnlockAppName: String? {
        guard let pendingUnlockBundleID else { return nil }
        return lockedApps.first(where: { $0.bundleID == pendingUnlockBundleID })?.displayName
    }

    private func authenticateBiometric(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    // MARK: - Background / Foreground

    func handleBackground() {
        if autoLockOnBackground {
            lockAllApps()
        }
    }

    func handleForeground() {
        checkAuthorizationStatus()
        reconcileShieldState()
    }

    func lockAll() {
        lockAllApps()
        lastError = nil
    }

    // MARK: - Shield Enforcement

    private func reconcileShieldState() {
        #if targetEnvironment(simulator)
        isMonitoring = false
        return
        #else
        guard isAuthorized else {
            clearShields()
            return
        }

        let applicationsToShield = lockedApps
            .filter { $0.lockOnLaunch && !sessionUnlockedApps.contains($0.bundleID) }
            .compactMap(applicationToken(for:))

        store.shield.applications = applicationsToShield.isEmpty ? nil : Set(applicationsToShield)
        isMonitoring = !applicationsToShield.isEmpty
        #endif
    }

    private func clearShields() {
        #if !targetEnvironment(simulator)
        store.shield.applications = nil
        #endif
        isMonitoring = false
    }

    private func applicationToken(for entry: LockedAppEntry) -> ApplicationToken? {
        #if targetEnvironment(simulator)
        return nil
        #else
        if let tokenData = entry.tokenData,
           let token = decodeApplicationToken(from: tokenData) {
            return token
        }
        guard entry.hasResolvedBundleIdentifier else {
            return nil
        }
        return Application(bundleIdentifier: entry.bundleID).token
        #endif
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.applocker.ios.locking",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.applocker.ios.locking",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.applocker.ios.locking",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Persistence

    private func saveLockedApps() {
        guard let data = try? JSONEncoder().encode(lockedApps) else { return }
        userDefaults.set(data, forKey: lockedAppsKey)
        NSUbiquitousKeyValueStore.default.set(data.base64EncodedString(), forKey: "com.applocker.ios.lockedAppsList")
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func loadLockedApps() {
        if let data = userDefaults.data(forKey: lockedAppsKey),
           let apps = try? JSONDecoder().decode([LockedAppEntry].self, from: data) {
            lockedApps = apps
            return
        }

        guard let encoded = NSUbiquitousKeyValueStore.default.string(forKey: "com.applocker.ios.lockedAppsList"),
              let data = Data(base64Encoded: encoded),
              let apps = try? JSONDecoder().decode([LockedAppEntry].self, from: data) else {
            return
        }

        lockedApps = apps
        userDefaults.set(data, forKey: lockedAppsKey)
    }

    private func loadSettings() {
        unlockDuration = userDefaults.double(forKey: "com.applocker.ios.unlockDuration")
        if unlockDuration <= 0 { unlockDuration = 300 }

        if userDefaults.object(forKey: "com.applocker.ios.autoLockOnBg") != nil {
            autoLockOnBackground = userDefaults.bool(forKey: "com.applocker.ios.autoLockOnBg")
        }

        if userDefaults.object(forKey: "com.applocker.ios.biometricUnlock") != nil {
            useBiometricForUnlock = userDefaults.bool(forKey: "com.applocker.ios.biometricUnlock")
        }
    }

    // MARK: - Statistics

    var lockedAppCount: Int { lockedApps.count }
    var currentlyUnlockedCount: Int { sessionUnlockedApps.count }
    var shieldedAppCount: Int { lockedApps.filter { $0.lockOnLaunch && !sessionUnlockedApps.contains($0.bundleID) }.count }

    func resetAllData() {
        lockedApps.removeAll()
        sessionUnlockedApps.removeAll()
        unlockTimers.values.forEach { $0.invalidate() }
        unlockTimers.removeAll()
        clearShields()

        userDefaults.removeObject(forKey: lockedAppsKey)
        userDefaults.removeObject(forKey: "com.applocker.ios.unlockDuration")
        userDefaults.removeObject(forKey: "com.applocker.ios.autoLockOnBg")
        userDefaults.removeObject(forKey: "com.applocker.ios.biometricUnlock")
        NSUbiquitousKeyValueStore.default.removeObject(forKey: "com.applocker.ios.lockedAppsList")
    }

    // MARK: - Internals

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleBackground()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleForeground()
                }
            }
            .store(in: &cancellables)
    }

    private func makePasscodeMaterial(from passcode: String?) -> PasscodeMaterial? {
        guard let passcode, !passcode.isEmpty,
              let salt = try? CryptoHelper.randomSalt(),
              let hash = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt) else {
            return nil
        }

        return PasscodeMaterial(hash: hash, salt: salt)
    }

    private func encodeApplicationToken(_ token: ApplicationToken) -> Data? {
        try? JSONEncoder().encode(token)
    }

    private func decodeApplicationToken(from data: Data) -> ApplicationToken? {
        try? JSONDecoder().decode(ApplicationToken.self, from: data)
    }

    private func tokenIdentifier(for token: ApplicationToken) -> String {
        guard let tokenData = encodeApplicationToken(token) else {
            return "token:unresolved"
        }
        return tokenIdentifier(for: tokenData)
    }

    private func tokenIdentifier(for data: Data) -> String {
        "token:\(tokenFingerprint(for: data))"
    }

    private func tokenFingerprint(for token: ApplicationToken) -> String {
        guard let tokenData = encodeApplicationToken(token) else {
            return UUID().uuidString.lowercased()
        }
        return tokenFingerprint(for: tokenData)
    }

    private func tokenFingerprint(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private struct PasscodeMaterial {
    let hash: Data
    let salt: Data

    var hashBase64: String {
        hash.base64EncodedString()
    }
}

struct LockedAppEntry: Codable, Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    let dateAdded: Date
    var perAppPasscodeHash: String?
    var lockOnLaunch: Bool
    var requireBiometric: Bool
    var tokenData: Data?

    var hasResolvedBundleIdentifier: Bool {
        !bundleID.isEmpty && !bundleID.hasPrefix("token:")
    }

    var displayIdentifier: String {
        hasResolvedBundleIdentifier ? bundleID : "Screen Time token"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }

    static func == (lhs: LockedAppEntry, rhs: LockedAppEntry) -> Bool {
        lhs.bundleID == rhs.bundleID
    }
}
#endif
