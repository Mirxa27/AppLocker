// Sources/AppLocker/Shared/CloudKitManager.swift
import CloudKit
import Foundation

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    private let container = CKContainer(identifier: "iCloud.com.mirxa.AppLocker")
    private var db: CKDatabase { container.privateCloudDatabase }

    @Published var iCloudAvailable = false

    private init() {
        Task { await checkiCloudStatus() }
    }

    func checkiCloudStatus() async {
        let status = try? await container.accountStatus()
        iCloudAvailable = (status == .available)
    }

    // MARK: - Mac: publish events

    func publishBlockedApp(appName: String, bundleID: String) {
        guard iCloudAvailable else { return }
        let r = CKRecord(recordType: "BlockedAppEvent")
        r["appName"]    = appName    as CKRecordValue
        r["bundleID"]   = bundleID   as CKRecordValue
        r["deviceName"] = ProcessInfo.processInfo.hostName as CKRecordValue
        r["timestamp"]  = Date()     as CKRecordValue
        db.save(r) { _, _ in }
    }

    func publishFailedAuth(appName: String, bundleID: String, encryptedPhotoURL: URL? = nil) {
        guard iCloudAvailable else { return }
        let r = CKRecord(recordType: "FailedAuthEvent")
        r["appName"]    = appName    as CKRecordValue
        r["bundleID"]   = bundleID   as CKRecordValue
        r["deviceName"] = ProcessInfo.processInfo.hostName as CKRecordValue
        r["timestamp"]  = Date()     as CKRecordValue
        if let url = encryptedPhotoURL { r["photoAsset"] = CKAsset(fileURL: url) }
        db.save(r) { _, _ in }
    }

    func syncLockedAppList(_ apps: [LockedAppInfo]) {
        guard iCloudAvailable,
              let json = try? JSONEncoder().encode(apps) else { return }
        let device = ProcessInfo.processInfo.hostName
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-\(device).json")
        try? json.write(to: tmpURL)

        let recID = CKRecord.ID(recordName: "locked-\(device)")
        db.fetch(withRecordID: recID) { existing, _ in
            let r = existing ?? CKRecord(recordType: "LockedAppList", recordID: recID)
            r["deviceName"] = device as CKRecordValue
            r["apps"]       = CKAsset(fileURL: tmpURL)
            r["updatedAt"]  = Date() as CKRecordValue
            self.db.save(r) { _, _ in try? FileManager.default.removeItem(at: tmpURL) }
        }
    }

    // MARK: - iOS: subscribe to push

    func setupPushSubscriptions() {
        for (subID, recordType, title) in [
            ("sub-blocked",     "BlockedAppEvent",  "App Blocked"),
            ("sub-failed-auth", "FailedAuthEvent",  "Failed Unlock Attempt")
        ] as [(String, String, String)] {
            let sub = CKQuerySubscription(
                recordType: recordType,
                predicate: NSPredicate(value: true),
                subscriptionID: subID,
                options: .firesOnRecordCreation
            )
            let info = CKSubscription.NotificationInfo()
            info.title                      = title
            info.alertLocalizationKey       = "appName"
            info.soundName                  = "default"
            info.shouldSendContentAvailable = true
            sub.notificationInfo            = info
            db.save(sub) { _, _ in }
        }
    }

    // MARK: - Fetch events (iOS)

    func fetchBlockedEvents(limit: Int = 100) async throws -> [CKRecord] {
        let q = CKQuery(recordType: "BlockedAppEvent", predicate: NSPredicate(value: true))
        q.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let r = try await db.records(matching: q, resultsLimit: limit)
        return r.matchResults.compactMap { try? $0.1.get() }
    }

    func fetchFailedAuthEvents(limit: Int = 100) async throws -> [CKRecord] {
        let q = CKQuery(recordType: "FailedAuthEvent", predicate: NSPredicate(value: true))
        q.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let r = try await db.records(matching: q, resultsLimit: limit)
        return r.matchResults.compactMap { try? $0.1.get() }
    }

    func fetchLockedAppLists() async throws -> [CKRecord] {
        let q = CKQuery(recordType: "LockedAppList", predicate: NSPredicate(value: true))
        q.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        let r = try await db.records(matching: q, resultsLimit: 20)
        return r.matchResults.compactMap { try? $0.1.get() }
    }

    // MARK: - Prune old records (Mac, call on launch)

    func pruneOldRecords() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let predicate = NSPredicate(format: "timestamp < %@", cutoff as CVarArg)
        for recordType in ["BlockedAppEvent", "FailedAuthEvent"] {
            Task { [weak self] in
                guard let self else { return }
                let q = CKQuery(recordType: recordType, predicate: predicate)
                guard let results = try? await self.db.records(matching: q, resultsLimit: 500) else { return }
                let ids = results.matchResults.compactMap { try? $0.1.get().recordID }
                for id in ids { try? await self.db.deleteRecord(withID: id) }
            }
        }
    }
}
