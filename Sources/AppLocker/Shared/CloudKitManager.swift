// CloudKitManager.swift
// CloudKit requires the com.apple.developer.icloud-services entitlement which in turn
// requires a provisioning profile for Developer ID distribution. Without a profile the
// OS blocks the launch entirely. Cross-device sync is handled by NSUbiquitousKeyValueStore
// in NotificationManager, so this manager is a safe no-op stub.

import Foundation

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    @Published var iCloudAvailable = false

    private init() {}

    // MARK: - No-op stubs (CloudKit disabled — no provisioning profile)

    func checkiCloudStatus() async {}
    func publishBlockedApp(appName: String, bundleID: String) {}
    func publishFailedAuth(appName: String, bundleID: String, encryptedPhotoURL: URL? = nil) {}
    func syncLockedAppList(_ apps: [LockedAppInfo]) {}
    func setupPushSubscriptions() {}
    func pruneOldRecords() {}

    // Fetch stubs return empty arrays so callers don't need to change.
    func fetchBlockedEvents(limit: Int = 100) async throws -> [Any] { [] }
    func fetchFailedAuthEvents(limit: Int = 100) async throws -> [Any] { [] }
    func fetchLockedAppLists() async throws -> [Any] { [] }
}
