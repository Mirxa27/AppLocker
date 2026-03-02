import CloudKit
import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#endif

@MainActor
final class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    @Published private(set) var iCloudAvailable = false
    @Published private(set) var lastSyncError: String?

    private let container = CKContainer(identifier: "iCloud.com.mirxa.AppLocker")
    private var db: CKDatabase { container.privateCloudDatabase }
    private var accountObserver: NSObjectProtocol?

    private enum RecordType {
        static let blockedAppEvent = "BlockedAppEvent"
        static let failedAuthEvent = "FailedAuthEvent"
        static let lockedAppList = "LockedAppList"
    }

    private enum Field {
        static let appName = "appName"
        static let bundleID = "bundleID"
        static let deviceName = "deviceName"
        static let timestamp = "timestamp"
        static let photoAsset = "photoAsset"
        static let appsAsset = "apps"
        static let updatedAt = "updatedAt"
    }

    private init() {
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkiCloudStatus()
            }
        }

        Task { [weak self] in
            await self?.checkiCloudStatus()
        }
    }

    deinit {
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
    }

    func checkiCloudStatus() async {
        do {
            let status = try await fetchAccountStatus()
            iCloudAvailable = (status == .available)
            if iCloudAvailable {
                lastSyncError = nil
            }
        } catch {
            iCloudAvailable = false
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Publish Events

    func publishBlockedApp(appName: String, bundleID: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ensureCloudAvailable()
                let record = CKRecord(recordType: RecordType.blockedAppEvent)
                record[Field.appName] = appName as CKRecordValue
                record[Field.bundleID] = bundleID as CKRecordValue
                record[Field.deviceName] = Self.currentDeviceName as CKRecordValue
                record[Field.timestamp] = Date() as CKRecordValue
                _ = try await save(record)
            } catch {
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    func publishFailedAuth(appName: String, bundleID: String, encryptedPhotoURL: URL? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ensureCloudAvailable()

                let record = CKRecord(recordType: RecordType.failedAuthEvent)
                record[Field.appName] = appName as CKRecordValue
                record[Field.bundleID] = bundleID as CKRecordValue
                record[Field.deviceName] = Self.currentDeviceName as CKRecordValue
                record[Field.timestamp] = Date() as CKRecordValue

                if let encryptedPhotoURL {
                    record[Field.photoAsset] = CKAsset(fileURL: encryptedPhotoURL)
                }

                _ = try await save(record)

                if let encryptedPhotoURL,
                   encryptedPhotoURL.isFileURL,
                   encryptedPhotoURL.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
                    try? FileManager.default.removeItem(at: encryptedPhotoURL)
                }
            } catch {
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    func syncLockedAppList(_ apps: [LockedAppInfo]) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ensureCloudAvailable()

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let json = try encoder.encode(apps)

                let deviceToken = Self.sanitizedRecordComponent(Self.currentDeviceName)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("locked-\(deviceToken)-\(UUID().uuidString).json")
                try json.write(to: tempURL, options: .atomic)

                let recordID = CKRecord.ID(recordName: "locked-\(deviceToken)")
                let existing = try? await fetchRecord(recordID: recordID)
                let record = existing ?? CKRecord(recordType: RecordType.lockedAppList, recordID: recordID)

                record[Field.deviceName] = Self.currentDeviceName as CKRecordValue
                record[Field.appsAsset] = CKAsset(fileURL: tempURL)
                record[Field.updatedAt] = Date() as CKRecordValue

                _ = try await save(record)
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    // MARK: - Subscriptions / Retention

    func setupPushSubscriptions() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ensureCloudAvailable()
                try await ensureSubscription(
                    id: "sub-blocked-events",
                    recordType: RecordType.blockedAppEvent,
                    title: "App Blocked"
                )
                try await ensureSubscription(
                    id: "sub-failed-auth-events",
                    recordType: RecordType.failedAuthEvent,
                    title: "Failed Unlock Attempt"
                )
            } catch {
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    func pruneOldRecords() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ensureCloudAvailable()
                let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
                let predicate = NSPredicate(format: "timestamp < %@", cutoff as CVarArg)

                for type in [RecordType.blockedAppEvent, RecordType.failedAuthEvent] {
                    let stale = try await fetchRecords(
                        recordType: type,
                        predicate: predicate,
                        sortField: Field.timestamp,
                        ascending: true,
                        limit: 400
                    )
                    try await deleteRecords(ids: stale.map(\.recordID))
                }
            } catch {
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    // MARK: - Query APIs

    func fetchBlockedEvents(limit: Int = 100) async throws -> [CKRecord] {
        try await ensureCloudAvailable()
        return try await fetchRecords(
            recordType: RecordType.blockedAppEvent,
            predicate: NSPredicate(value: true),
            sortField: Field.timestamp,
            ascending: false,
            limit: limit
        )
    }

    func fetchFailedAuthEvents(limit: Int = 100) async throws -> [CKRecord] {
        try await ensureCloudAvailable()
        return try await fetchRecords(
            recordType: RecordType.failedAuthEvent,
            predicate: NSPredicate(value: true),
            sortField: Field.timestamp,
            ascending: false,
            limit: limit
        )
    }

    func fetchLockedAppLists(limit: Int = 50) async throws -> [CKRecord] {
        try await ensureCloudAvailable()
        return try await fetchRecords(
            recordType: RecordType.lockedAppList,
            predicate: NSPredicate(value: true),
            sortField: Field.updatedAt,
            ascending: false,
            limit: limit
        )
    }

    func loadAssetData(from record: CKRecord, field: String = Field.photoAsset) async -> Data? {
        guard let asset = record[field] as? CKAsset,
              let fileURL = asset.fileURL else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL)
        }.value
    }

    // MARK: - Internals

    private func ensureCloudAvailable() async throws {
        if !iCloudAvailable {
            await checkiCloudStatus()
        }
        guard iCloudAvailable else {
            throw CloudKitManagerError.iCloudUnavailable
        }
    }

    private func fetchAccountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            db.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let saved {
                    continuation.resume(returning: saved)
                } else {
                    continuation.resume(throwing: CloudKitManagerError.invalidCloudKitResponse)
                }
            }
        }
    }

    private func fetchRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            db.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CloudKitManagerError.invalidCloudKitResponse)
                }
            }
        }
    }

    private func fetchRecords(
        recordType: String,
        predicate: NSPredicate,
        sortField: String,
        ascending: Bool,
        limit: Int
    ) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: sortField, ascending: ascending)]

            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = limit

            var records: [CKRecord] = []

            operation.recordMatchedBlock = { _, result in
                if case let .success(record) = result {
                    records.append(record)
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            self.db.add(operation)
        }
    }

    private func deleteRecords(ids: [CKRecord.ID]) async throws {
        guard !ids.isEmpty else { return }

        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
            operation.savePolicy = .ifServerRecordUnchanged
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            self.db.add(operation)
        }
    }

    private func ensureSubscription(id: String, recordType: String, title: String) async throws {
        do {
            _ = try await fetchSubscription(subscriptionID: id)
            return
        } catch let ckError as CKError where ckError.code == .unknownItem {
            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: NSPredicate(value: true),
                subscriptionID: id,
                options: .firesOnRecordCreation
            )

            let info = CKSubscription.NotificationInfo()
            info.title = title
            info.alertBody = "New security event received from AppLocker."
            info.shouldSendContentAvailable = true
            info.soundName = "default"
            subscription.notificationInfo = info

            _ = try await saveSubscription(subscription)
        }
    }

    private func fetchSubscription(subscriptionID: String) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            db.fetch(withSubscriptionID: subscriptionID) { subscription, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let subscription {
                    continuation.resume(returning: subscription)
                } else {
                    continuation.resume(throwing: CloudKitManagerError.invalidCloudKitResponse)
                }
            }
        }
    }

    private func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            db.save(subscription) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let saved {
                    continuation.resume(returning: saved)
                } else {
                    continuation.resume(throwing: CloudKitManagerError.invalidCloudKitResponse)
                }
            }
        }
    }

    private static var currentDeviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #elseif os(iOS)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    private static func sanitizedRecordComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let scalarView = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let normalized = String(scalarView)
        return String(normalized.prefix(64))
    }
}

enum CloudKitManagerError: LocalizedError {
    case iCloudUnavailable
    case invalidCloudKitResponse

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud account is unavailable for CloudKit sync"
        case .invalidCloudKitResponse:
            return "CloudKit returned an unexpected empty response"
        }
    }
}
