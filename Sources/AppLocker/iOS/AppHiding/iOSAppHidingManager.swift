// Sources/AppLocker/iOS/AppHiding/iOSAppHidingManager.swift
#if os(iOS)
import Foundation
import FamilyControls
import ManagedSettings
import CryptoKit
import SwiftUI

@MainActor
final class iOSAppHidingManager: ObservableObject {
    static let shared = iOSAppHidingManager()

    @Published var hiddenApps: [HiddenApp] = []
    @Published var isAuthorized = false
    @Published var authorizationError: String?
    @Published var isLoading = false

    private let store = ManagedSettingsStore(named: .init("AppLockerHiddenApps"))
    private let hiddenAppsKey = "com.applocker.ios.hiddenApps"
    private let userDefaults = UserDefaults.standard

    static let restrictedBundleIDs: Set<String> = [
        "com.apple.mobilephone",
        "com.apple.MobileSMS",
        "com.apple.mobilesafari",
        "com.apple.Preferences",
        "com.apple.AppStore",
        "com.apple.calculator",
        "com.apple.mobiletimer",
        "com.apple.Maps",
        "com.apple.Health",
        "com.apple.findmy",
    ]

    private init() {
        loadHiddenApps()
        checkAuthorizationStatus()
        applyAllShields()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        isLoading = true
        authorizationError = nil
        defer { isLoading = false }

        #if targetEnvironment(simulator)
        authorizationError = "Screen Time is not available on the simulator. Test on a physical device."
        isAuthorized = false
        clearAllShields()
        return
        #else
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            authorizationError = nil
            applyAllShields()
        } catch {
            authorizationError = "Screen Time authorization failed: \(error.localizedDescription). Ensure Family Controls is enabled for com.mirxa.AppLocker.Companion."
            isAuthorized = false
            clearAllShields()
        }
        #endif
    }

    func checkAuthorizationStatus() {
        #if targetEnvironment(simulator)
        isAuthorized = false
        authorizationError = "Screen Time is not available on the simulator."
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

    // MARK: - App Hiding

    @discardableResult
    func hideApplications(from selection: FamilyActivitySelection) -> Int {
        guard isAuthorized else {
            authorizationError = "Screen Time authorization required"
            return 0
        }

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

        var additions: [HiddenApp] = []
        var blockedRestricted = 0

        for token in tokens {
            guard let tokenData = encodeApplicationToken(token) else {
                continue
            }

            let metadata = metadataByTokenKey[tokenFingerprint(for: tokenData)]
            let bundleID = metadata?.bundleIdentifier ?? tokenIdentifier(for: tokenData)

            guard !Self.restrictedBundleIDs.contains(bundleID) else {
                blockedRestricted += 1
                continue
            }
            guard !hiddenApps.contains(where: { $0.bundleID == bundleID }) else { continue }
            guard !additions.contains(where: { $0.bundleID == bundleID }) else { continue }

            additions.append(
                HiddenApp(
                    bundleID: bundleID,
                    displayName: metadata?.localizedDisplayName ?? metadata?.bundleIdentifier ?? "Protected App",
                    dateHidden: Date(),
                    shieldEnabled: true,
                    tokenData: tokenData
                )
            )
        }

        guard !additions.isEmpty else {
            if blockedRestricted > 0 {
                authorizationError = "System apps cannot be hidden."
            }
            return 0
        }

        hiddenApps.append(contentsOf: additions)
        hiddenApps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        saveHiddenApps()
        applyAllShields()

        if blockedRestricted > 0 {
            authorizationError = "Hidden \(additions.count) apps. Restricted system apps were skipped."
        } else {
            authorizationError = nil
        }

        return additions.count
    }

    func hideApp(bundleID: String, displayName _: String) {
        var selection = FamilyActivitySelection()
        if let token = Application(bundleIdentifier: bundleID).token {
            selection.applicationTokens.insert(token)
            _ = hideApplications(from: selection)
        } else {
            authorizationError = "Unable to resolve the selected app with Screen Time."
        }
    }

    func unhideApp(bundleID: String) {
        guard isAuthorized else { return }

        hiddenApps.removeAll { $0.bundleID == bundleID }
        saveHiddenApps()
        applyAllShields()
    }

    func toggleShield(bundleID: String) {
        guard isAuthorized,
              let index = hiddenApps.firstIndex(where: { $0.bundleID == bundleID }) else { return }

        hiddenApps[index].shieldEnabled.toggle()
        saveHiddenApps()
        applyAllShields()
    }

    // MARK: - Shield Application

    private func applyAllShields() {
        #if !targetEnvironment(simulator)
        guard isAuthorized else {
            clearAllShields()
            return
        }

        let tokens = Set(
            hiddenApps
                .filter { $0.shieldEnabled }
                .compactMap(applicationToken(for:))
        )

        store.shield.applications = tokens.isEmpty ? nil : tokens
        #endif
    }

    private func applicationToken(for app: HiddenApp) -> ApplicationToken? {
        #if targetEnvironment(simulator)
        return nil
        #else
        if let tokenData = app.tokenData,
           let token = decodeApplicationToken(from: tokenData) {
            return token
        }
        guard app.hasResolvedBundleIdentifier else {
            return nil
        }
        return Application(bundleIdentifier: app.bundleID).token
        #endif
    }

    func clearAllShields() {
        #if !targetEnvironment(simulator)
        store.shield.applications = nil
        #endif
    }

    // MARK: - Persistence

    private func saveHiddenApps() {
        if let data = try? JSONEncoder().encode(hiddenApps) {
            userDefaults.set(data, forKey: hiddenAppsKey)
        }
    }

    private func loadHiddenApps() {
        guard let data = userDefaults.data(forKey: hiddenAppsKey),
              let apps = try? JSONDecoder().decode([HiddenApp].self, from: data) else {
            return
        }
        hiddenApps = apps
    }

    // MARK: - Statistics

    var shieldedAppCount: Int {
        hiddenApps.filter { $0.shieldEnabled }.count
    }

    var totalHiddenCount: Int {
        hiddenApps.count
    }

    func recentlyHidden(days: Int = 7) -> [HiddenApp] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return hiddenApps.filter { $0.dateHidden >= cutoff }
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

struct HiddenApp: Codable, Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    let dateHidden: Date
    var shieldEnabled: Bool
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

    static func == (lhs: HiddenApp, rhs: HiddenApp) -> Bool {
        lhs.bundleID == rhs.bundleID
    }
}
#endif
