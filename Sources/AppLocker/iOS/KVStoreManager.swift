// Sources/AppLocker/iOS/KVStoreManager.swift
#if os(iOS)
import Foundation
import SwiftUI
import CryptoKit

@MainActor
class KVStoreManager: ObservableObject {
    static let shared = KVStoreManager()

    @Published var lockedApps: [LockedAppInfo] = []
    @Published var alertHistory: [AlertRecord] = []
    @Published var encryptedNotes: [EncryptedNote] = []
    @Published var notesSalt: Data? = nil
    @Published var lastMacDevice: String? = nil
    @Published var lastSyncTime: Date? = nil

    private let store = NSUbiquitousKeyValueStore.default
    private let historyKey = "com.applocker.ios.alertHistory"

    private init() {
        loadAlertHistory()
        decodeAllKeys()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    @objc private func kvStoreChanged(_ notification: Notification) {
        decodeAllKeys()
        if let data = store.data(forKey: "com.applocker.latestAlert"),
           let alert = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let appName  = alert["appName"]    as? String,
           let bundleID = alert["bundleID"]   as? String,
           let device   = alert["deviceName"] as? String,
           let ts       = alert["timestamp"]  as? TimeInterval,
           let type     = alert["type"]       as? String,
           Date().timeIntervalSince1970 - ts < 300 {

            let record = AlertRecord(
                appName: appName, bundleID: bundleID, deviceName: device,
                timestamp: Date(timeIntervalSince1970: ts), type: type
            )
            let isDuplicate = alertHistory.contains {
                $0.appName == appName && abs($0.timestamp.timeIntervalSince1970 - ts) < 5
            }
            if !isDuplicate {
                alertHistory.insert(record, at: 0)
                if alertHistory.count > 200 { alertHistory = Array(alertHistory.prefix(200)) }
                saveAlertHistory()
            }
        }
    }

    func decodeAllKeys() {
        if let b64 = store.string(forKey: "com.applocker.lockedApps"),
           let data = Data(base64Encoded: b64),
           let apps = try? JSONDecoder().decode([LockedAppInfo].self, from: data) {
            lockedApps = apps
        }

        if let b64 = store.string(forKey: "com.applocker.encryptedNotes"),
           let data = Data(base64Encoded: b64) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let notes = try? dec.decode([EncryptedNote].self, from: data) {
                encryptedNotes = notes
            }
        }

        if let b64 = store.string(forKey: "com.applocker.notesSalt"),
           let saltData = Data(base64Encoded: b64) {
            notesSalt = saltData
        }

        if let data = store.data(forKey: "com.applocker.latestAlert"),
           let alert = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            lastMacDevice = alert["deviceName"] as? String
            if let ts = alert["timestamp"] as? TimeInterval {
                lastSyncTime = Date(timeIntervalSince1970: ts)
            }
        }
    }

    func clearHistory() {
        alertHistory.removeAll()
        saveAlertHistory()
    }

    private func saveAlertHistory() {
        if let data = try? JSONEncoder().encode(alertHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadAlertHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let records = try? JSONDecoder().decode([AlertRecord].self, from: data) else { return }
        alertHistory = records
    }
}
#endif
